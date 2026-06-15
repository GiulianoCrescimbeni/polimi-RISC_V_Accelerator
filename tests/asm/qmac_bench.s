    /*
     * Quad-MAC benchmark — custom QMAC (opcode 0x0B / funct3 5 / funct7 1),
     * non-unrolled. Twin of mac_bench_mac.s / mac_bench_base.s.
     *
     * One QMAC performs four signed INT8 multiply-accumulates in a single
     * instruction, so to do the SAME 100000 MAC-equivalent operations as the
     * scalar MAC/baseline ASM benchmarks this kernel runs 25000 iterations
     * (25000 x 4 lanes = 100000 INT8 MACs). This makes the cycle count directly
     * comparable, side by side, with mac_bench_base.s (mul;add) and
     * mac_bench_mac.s (scalar MAC).
     *
     * ISS note: opcode 0x0B is treated as NOP by rv_iss.py, so `make sim`
     * ISS<->RTL comparison prints FAILED. Only the RTL stats.txt is meaningful.
     *
     * Single accumulator (x12): exercises the QMAC accumulator dependency chain.
     */
    .globl   _start
    .section .text

_start:
    li       x10, 0x01010101    # rs1 = {1,1,1,1}  (4x INT8)
    li       x11, 0x02020202    # rs2 = {2,2,2,2}  (4x INT8)
    li       x12, 0             # accumulator
    li       x13, 25000         # iteration count (25000 * 4 lanes = 100000 INT8 MACs)
    li       x14, 0             # i

loop_qmac:
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11    # QMAC x12 += dot4(x10, x11)
    addi     x14, x14, 1
    blt      x14, x13, loop_qmac

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
