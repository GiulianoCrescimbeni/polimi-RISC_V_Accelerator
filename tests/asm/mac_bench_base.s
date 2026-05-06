    /*
     * Baseline MAC benchmark — RV32IM only (mul + add).
     * Twin of mac_bench_mac.s. Run both with `make sim` and diff stats.txt.
     *
     * Kernel: 1024-iter dot-product-like accumulation with constants in regs,
     * so cycle count reflects only the hot loop (no memory, no init noise).
     *   x12 += x10 * x11    repeated 1024 times
     */
    .globl   _start
    .section .text

_start:
    li       x10, 7              # const a
    li       x11, 6              # const b
    li       x12, 0              # accumulator
    li       x13, 1024           # iteration count
    li       x14, 0              # i

loop_base:
    mul      x15, x10, x11       # x15 = a * b
    add      x12, x12, x15       # acc += x15
    addi     x14, x14, 1
    blt      x14, x13, loop_base

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
