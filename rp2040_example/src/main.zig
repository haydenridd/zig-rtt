const std = @import("std");
const rtt = @import("rtt");
const microzig = @import("microzig");
const mdf = microzig.drivers;
const rp2xxx = microzig.hal;
const ClockDevice = rp2xxx.drivers.ClockDevice;
var cd = ClockDevice{};
const clock = cd.clock_device();
const Pin = rp2xxx.gpio.Pin;
const gpio = rp2xxx.gpio;

/// Dummy example of defining a custom locking/unlocking mechanisms for thread safety
const pretend_thread_safety = struct {
    var locked: bool = false;

    const Context = *bool;

    fn lock(context: Context) void {
        context.* = true;
    }

    fn unlock(context: Context) void {
        context.* = false;
    }

    var generic_lock: rtt.GenericLock(Context, lock, unlock) = .{
        .context = &locked,
    };
};

// Configure RTT with specific sizes/names for up and down channels (2 of each) as
// well as a custom locking routine and specific linker placement.
const rtt_instance = rtt.RTT(.{
    .up_channels = &.{
        .{ .name = "Terminal", .mode = .NoBlockSkip, .buffer_size = 128 },
        .{ .name = "Up2", .mode = .NoBlockSkip, .buffer_size = 256 },
    },
    .down_channels = &.{
        .{ .name = "Terminal", .mode = .BlockIfFull, .buffer_size = 512 },
        .{ .name = "Down2", .mode = .BlockIfFull, .buffer_size = 1024 },
    },
    .exclusive_access = pretend_thread_safety.generic_lock.any(),
    .linker_section = ".rtt_cb",
});

// Configure RTT with all default settings:
// const rtt_instance = rtt.RTT(.{});

// Configure RTT with default settings but disable exclusive access protection
// const rtt_instance = rtt.RTT(.{ .exclusive_access = null });

// Set up RTT channel 0 as a logger

var rtt_logger: ?rtt_instance.Writer = null;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_prefix = comptime "[{}.{:0>6}] " ++ level.asText();
    const prefix = comptime level_prefix ++ switch (scope) {
        .default => ": ",
        else => " (" ++ @tagName(scope) ++ "): ",
    };

    if (rtt_logger) |writer| {
        const current_time = clock.get_time_since_boot();
        const seconds = current_time.to_us() / std.time.us_per_s;
        const microseconds = current_time.to_us() % std.time.us_per_s;

        writer.print(prefix ++ format ++ "\r\n", .{ seconds, microseconds } ++ args) catch {};
    }
}

/// Assigns our custom RTT logging function to MicroZig's log function
/// A "pub const std_options" decl could be used here instead if not using MicroZig
pub const microzig_options = microzig.Options{
    .logFn = log,
};

pub fn main() !void {

    // Don't forget to bring a blinky!
    var led_gpio = rp2xxx.gpio.num(25);
    led_gpio.set_direction(.out);
    led_gpio.set_function(.sio);
    led_gpio.put(1);

    rtt_instance.init();

    // Manually write some bytes to RTT up channel 0 so that is shows up in RTT Viewer
    _ = try rtt_instance.write(0, "Hello RTT!\n");

    // Use std.log instead
    rtt_logger = rtt_instance.writer(0);
    std.log.info("Hello from std.log!\n", .{});

    // Now infinitely wait for a complete line, and print it
    const reader = rtt_instance.reader(0);
    const max_line_len = 1024;
    var line_buffer = try std.BoundedArray(u8, max_line_len).init(0);
    var blink_deadline = mdf.time.make_timeout_us(clock.get_time_since_boot(), 500_000);
    var led_val: u1 = 0;
    while (true) {
        const now = clock.get_time_since_boot();
        // Toggle LED every 500 msec
        if (blink_deadline.is_reached_by(now)) {
            led_gpio.put(led_val);
            led_val = if (led_val == 0) 1 else 0;
            blink_deadline = mdf.time.make_timeout_us(now, 500_000);
        }

        // Read some bytes into line buffer, continuing if we get end of stream before our delimiter
        reader.streamUntilDelimiter(line_buffer.writer(), '\n', line_buffer.unusedCapacitySlice().len) catch |err| switch (err) {
            error.EndOfStream => continue,
            error.StreamTooLong => {
                std.log.err("Line is not allowed to exceed {d} characters, discarding the following data: \"{s}\"", .{ max_line_len, line_buffer.constSlice() });
                try line_buffer.resize(0);
                continue;
            },
            else => @panic("Unknown error on RTT reader"),
        };
        std.log.info("Got a line: \"{s}\"", .{line_buffer.constSlice()});
        try line_buffer.resize(0);
    }
}
