    /*
     * Baseline MAC benchmark — RV32IM only (mul + add), 8x unrolled with
     * 8 parallel accumulators (software register renaming).
     *
     * Goal: break the single-accumulator dependency chain that capped the
     * non-renamed unrolled benchmark (mac_bench_base_unrolled.s) at ~1.24x
     * speedup. Each mul writes a private temp, each add updates a private
     * accumulator. The 8 (mul, add) pairs are mutually independent inside
     * one outer iteration, so the multiplier pipeline can stream them
     * without RAW stalls.
     *
     * Total work: 12500 outer iterations x 8 = 100000 mul+add pairs,
     * matching mac_bench_base.s / mac_bench_base_unrolled.s.
     *
     * Register map:
     *   x10        const a
     *   x11        const b
     *   x13        outer-loop limit (12500)
     *   x14        outer-loop counter i
     *   x12, x15..x21    8 parallel accumulators
     *   x22..x29         8 parallel mul temps
     */
    .globl   _start
    .section .text

_start:
    li       x10, 7              # const a
    li       x11, 6              # const b
    li       x13, 12500          # outer iteration count
    li       x14, 0              # i

    # zero all 8 accumulators
    li       x12, 0
    li       x15, 0
    li       x16, 0
    li       x17, 0
    li       x18, 0
    li       x19, 0
    li       x20, 0
    li       x21, 0

loop_base_par:
    mul      x22, x10, x11
    add      x12, x12, x22
    mul      x23, x10, x11
    add      x15, x15, x23
    mul      x24, x10, x11
    add      x16, x16, x24
    mul      x25, x10, x11
    add      x17, x17, x25
    mul      x26, x10, x11
    add      x18, x18, x26
    mul      x27, x10, x11
    add      x19, x19, x27
    mul      x28, x10, x11
    add      x20, x20, x28
    mul      x29, x10, x11
    add      x21, x21, x29
    addi     x14, x14, 1
    blt      x14, x13, loop_base_par

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
