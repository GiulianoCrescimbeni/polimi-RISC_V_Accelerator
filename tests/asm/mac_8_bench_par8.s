    /*
     * mac_8 benchmark, 8x unrolled with 8 parallel accumulators (software
     * register renaming). Twin of mac_bench_par8_mac.s.
     * Custom mac_8 (opcode 0x0B / funct3 5 / funct7 1).
     *
     * Each mac_8 writes its own accumulator, so the 8 mac_8s inside one outer
     * iteration are mutually independent (no RAW chain on a single accumulator).
     * This mirrors the par8 MAC benchmark and lets us see whether breaking the
     * accumulator chain helps the mac_8 the way it helped the 3-stage MAC.
     * (The mac_8 is single-cycle, so the chain is expected to matter far less.)
     *
     * mac/bit fairness: mac_8 count == MAC count (same operand bits/instr).
     * Total work: 12500 outer iterations x 8 = 100000 mac_8s = 400000 INT8 MACs
     * (4x the arithmetic), matching the 100000 MAC instructions of the other
     * ASM MAC benchmarks for a like-for-like cycle comparison at equal bits.
     *
     * ISS note: opcode 0x0B is NOP in rv_iss.py -> `make sim` prints FAILED;
     * only the RTL stats.txt is meaningful.
     *
     * Register map:
     *   x10        packed rs1
     *   x11        packed rs2
     *   x13        outer-loop limit (12500)
     *   x14        outer-loop counter i
     *   x12, x15..x21    8 parallel mac_8 accumulators
     */
    .globl   _start
    .section .text

_start:
    li       x10, 0x01010101    # rs1 = {1,1,1,1}
    li       x11, 0x02020202    # rs2 = {2,2,2,2}
    li       x13, 12500         # outer iteration count (12500 * 8 = 100000 mac_8s, mac/bit)
    li       x14, 0             # i

    # zero all 8 accumulators
    li       x12, 0
    li       x15, 0
    li       x16, 0
    li       x17, 0
    li       x18, 0
    li       x19, 0
    li       x20, 0
    li       x21, 0

loop_mac_8_par:
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11
    .insn r 0x0B, 0x5, 0x1, x15, x10, x11
    .insn r 0x0B, 0x5, 0x1, x16, x10, x11
    .insn r 0x0B, 0x5, 0x1, x17, x10, x11
    .insn r 0x0B, 0x5, 0x1, x18, x10, x11
    .insn r 0x0B, 0x5, 0x1, x19, x10, x11
    .insn r 0x0B, 0x5, 0x1, x20, x10, x11
    .insn r 0x0B, 0x5, 0x1, x21, x10, x11
    addi     x14, x14, 1
    blt      x14, x13, loop_mac_8_par

    # final reduction: collapse the 8 partial sums into x12
    add      x12, x12, x15
    add      x12, x12, x16
    add      x12, x12, x17
    add      x12, x12, x18
    add      x12, x12, x19
    add      x12, x12, x20
    add      x12, x12, x21

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
