    /*
     * MAC-instruction benchmark, 8x loop unrolled. Uses the custom MAC
     * (opcode 0x0B / funct3 4 / funct7 1). Twin of mac_bench_base_unrolled.s.
     *
     * Note: ISS doesn't decode opcode 0x0B (rv_iss.py treats it as NOP), so
     * the `make sim` ISS<->RTL comparison will print FAILED for this test.
     * That's expected — what matters is the cycle count in stats.txt.
     *
     * Total work: 12500 outer iterations x 8 = 100000 MACs, matching the
     * non-unrolled mac_bench_mac.s for a like-for-like cycle comparison.
     */
    .globl   _start
    .section .text

_start:
    li       x10, 7              # const a
    li       x11, 6              # const b
    li       x12, 0              # accumulator
    li       x13, 12500          # outer iteration count (12500 * 8 = 100000)
    li       x14, 0              # i

loop_mac_unrolled:
    .word    0x02B5460B          # MAC x12, x10, x11
    .word    0x02B5460B
    .word    0x02B5460B
    .word    0x02B5460B
    .word    0x02B5460B
    .word    0x02B5460B
    .word    0x02B5460B
    .word    0x02B5460B
    addi     x14, x14, 1
    blt      x14, x13, loop_mac_unrolled

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
