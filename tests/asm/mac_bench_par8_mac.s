    /*
     * MAC benchmark, 8x unrolled with 8 parallel accumulators
     * (software register renaming on top of the custom MAC instruction).
     *
     * Goal: break the single-accumulator dependency chain that capped
     * mac_bench_mac_unrolled.s at ~1.24x speedup. Each MAC writes its own
     * destination register, so the 8 MACs inside one outer iteration are
     * mutually independent and the 3-stage multiplier pipeline can keep
     * multiple MACs in flight at once.
     *
     * ISS note: opcode 0x0B is treated as NOP by rv_iss.py, so `make sim`
     * ISS<->RTL comparison will print FAILED. Only the RTL stats.txt is
     * meaningful here.
     *
     * Total work: 12500 outer iterations x 8 = 100000 MACs, matching the
     * other ASM MAC benchmarks for a like-for-like cycle comparison.
     *
     * Register map:
     *   x10        const a
     *   x11        const b
     *   x13        outer-loop limit (12500)
     *   x14        outer-loop counter i
     *   x12, x15..x21    8 parallel MAC accumulators
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

loop_mac_par:
    .insn r 0x0B, 0x4, 0x1, x12, x10, x11      # MAC x12 += x10*x11
    .insn r 0x0B, 0x4, 0x1, x15, x10, x11      # MAC x15 += x10*x11
    .insn r 0x0B, 0x4, 0x1, x16, x10, x11      # MAC x16 += x10*x11
    .insn r 0x0B, 0x4, 0x1, x17, x10, x11
    .insn r 0x0B, 0x4, 0x1, x18, x10, x11
    .insn r 0x0B, 0x4, 0x1, x19, x10, x11
    .insn r 0x0B, 0x4, 0x1, x20, x10, x11
    .insn r 0x0B, 0x4, 0x1, x21, x10, x11      # MAC x21 += x10*x11
    addi     x14, x14, 1
    blt      x14, x13, loop_mac_par

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
