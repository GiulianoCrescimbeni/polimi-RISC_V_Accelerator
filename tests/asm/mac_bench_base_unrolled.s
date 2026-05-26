    /*
     * Baseline MAC benchmark — RV32IM only (mul + add), 8x loop unrolled.
     * Twin of mac_bench_mac_unrolled.s. Designed to push the compute share
     * of the loop close to 100% by amortizing the addi/blt/branch-flush
     * cost over 8 mul+add pairs per outer iteration.
     *
     * Total work: 12500 outer iterations x 8 = 100000 mul+add pairs,
     * matching mac_bench_base.s for a like-for-like cycle comparison.
     */
    .globl   _start
    .section .text

_start:
    li       x10, 7              # const a
    li       x11, 6              # const b
    li       x12, 0              # accumulator
    li       x13, 12500          # outer iteration count (12500 * 8 = 100000)
    li       x14, 0              # i

loop_base_unrolled:
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    mul      x15, x10, x11
    add      x12, x12, x15
    addi     x14, x14, 1
    blt      x14, x13, loop_base_unrolled

    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
