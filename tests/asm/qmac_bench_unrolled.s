    /*
     * Quad-MAC benchmark, 8x loop unrolled. Twin of mac_bench_mac_unrolled.s.
     * Custom QMAC (opcode 0x0B / funct3 5 / funct7 1).
     *
     * Amortises the addi/blt/branch-flush cost over 8 back-to-back QMACs per
     * outer iteration. Single accumulator (x12), so the 8 QMACs form a RAW
     * dependency chain on the accumulator.
     *
     * Total work: 3125 outer iterations x 8 = 25000 QMACs = 100000 INT8
     * MAC-equivalent operations, matching the scalar ASM benchmarks for a
     * like-for-like cycle comparison.
     *
     * ISS note: opcode 0x0B is NOP in rv_iss.py -> `make sim` prints FAILED;
     * only the RTL stats.txt is meaningful.
     */
    .globl   _start
    .section .text

_start:
    li       x10, 0x01010101    # rs1 = {1,1,1,1}
    li       x11, 0x02020202    # rs2 = {2,2,2,2}
    li       x12, 0             # accumulator
    li       x13, 3125          # outer iteration count (3125 * 8 = 25000 QMACs)
    li       x14, 0             # i

loop_qmac_unrolled:
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    addi     x14, x14, 1
    blt      x14, x13, loop_qmac_unrolled

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
