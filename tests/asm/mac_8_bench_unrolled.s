    /*
     * mac_8 benchmark, 8x loop unrolled. Twin of mac_bench_mac_unrolled.s.
     * Custom mac_8 (opcode 0x0B / funct3 5 / funct7 1).
     *
     * Amortises the addi/blt/branch-flush cost over 8 back-to-back mac_8s per
     * outer iteration. Single accumulator (x12), so the 8 mac_8s form a RAW
     * dependency chain on the accumulator.
     *
     * mac/bit fairness: mac_8 count == MAC count (same operand bits/instr).
     * Total work: 12500 outer iterations x 8 = 100000 mac_8s = 400000 INT8 MACs
     * (4x the arithmetic), matching the 100000 MAC instructions of
     * mac_bench_mac_unrolled.s for a like-for-like cycle comparison at equal bits.
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
    li       x13, 12500         # outer iteration count (12500 * 8 = 100000 mac_8s, mac/bit)
    li       x14, 0             # i

loop_mac_8_unrolled:
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    addi     x14, x14, 1
    blt      x14, x13, loop_mac_8_unrolled

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
