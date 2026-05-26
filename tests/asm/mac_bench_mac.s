    /*
     * MAC-instruction benchmark — uses the custom MAC (opcode 0x0B / funct3 4 /
     * funct7 1).  Twin of mac_bench_base.s; identical setup, identical loop
     * structure, but the (mul+add) pair is replaced by a single MAC.
     *
     * Note: ISS doesn't decode opcode 0x0B (rv_iss.py treats it as NOP), so the
     * `make sim` ISS↔RTL comparison will print FAILED for this test. That's
     * expected — what matters here is work/asm.mac_bench_mac/stats.txt, which
     * comes from the RTL log alone.
     *
     *   x12 += x10 * x11    repeated 100000 times via custom MAC
     */
    .globl   _start
    .section .text

_start:
    li       x10, 7              # const a
    li       x11, 6              # const b
    li       x12, 0              # accumulator
    li       x13, 100000         # iteration count
    li       x14, 0              # i

loop_mac:
    .word    0x02B5460B          # MAC x12, x10, x11  -> x12 += x10 * x11
    addi     x14, x14, 1
    blt      x14, x13, loop_mac

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
