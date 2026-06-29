    /*
     * mac_8 benchmark — custom mac_8 (opcode 0x0B / funct3 5 / funct7 1),
     * non-unrolled. Twin of mac_bench_mac.s / mac_bench_base.s.
     *
     * One mac_8 performs four signed INT8 multiply-accumulates in a single
     * instruction. mac/bit fairness: a mac_8 and a 32-bit MAC each move 64
     * operand bits per instruction, so the fair comparison runs the SAME number
     * of accelerator instructions. This kernel therefore issues 100000 mac_8s
     * (= 400000 INT8 MACs = 4x the arithmetic), matching the 100000 MAC
     * instructions of mac_bench_mac.s / mul+add pairs of mac_bench_base.s.
     * Cycle counts are then directly comparable at equal operand-bit throughput.
     *
     * ISS note: opcode 0x0B is treated as NOP by rv_iss.py, so `make sim`
     * ISS<->RTL comparison prints FAILED. Only the RTL stats.txt is meaningful.
     *
     * Single accumulator (x12): exercises the mac_8 accumulator dependency chain.
     */
    .globl   _start
    .section .text

_start:
    li       x10, 0x01010101    # rs1 = {1,1,1,1}  (4x INT8)
    li       x11, 0x02020202    # rs2 = {2,2,2,2}  (4x INT8)
    li       x12, 0             # accumulator
    li       x13, 100000        # mac_8 count = MAC count (mac/bit); 100000 * 4 lanes = 400000 INT8 MACs
    li       x14, 0             # i

loop_mac_8:
    .insn r 0x0B, 0x5, 0x1, x12, x10, x11    # mac_8 x12 += dot4(x10, x11)
    addi     x14, x14, 1
    blt      x14, x13, loop_mac_8

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
