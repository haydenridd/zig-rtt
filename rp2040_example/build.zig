const std = @import("std");

const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});
    const mz = MicroBuild.init(b, mz_dep) orelse return;

    const optimize = b.standardOptimizeOption(.{});
    const firmware = mz.add_firmware(.{
        .name = "rtt_example",
        .target = mz.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const rtt_dep = b.dependency("rtt", .{}).module("rtt");
    firmware.add_app_import("rtt", rtt_dep, .{});

    mz.install_firmware(firmware, .{});
    mz.install_firmware(firmware, .{ .format = .elf });
}
