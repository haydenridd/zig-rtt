# RTT Implementation in Zig

Work in progress. Goal is to integrate into MicroZig. For now this repo serves as a development/test bed that uses the rp2040 to test RTT functionality.

Functionality supported from original:
- 

Functionality not yet supported from original:
- 

# TODO:
- Implementation
    - make accesses to read/write offsets `volatile`
    - add memory barriers where neccessary
    - add locking where neccessary 
    - allow linker section placement via build options
- Testing:
    - Max number of up/down channels supported by RTT
    - Max virtual terminals supported by RTT
    
