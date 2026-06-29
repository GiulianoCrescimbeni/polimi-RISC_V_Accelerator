    .globl   _start
    .section .text

    /*
     * Accumulator RAW hazard against a multi-cycle producer.
     * MUL writes x12 through the 3-stage multiplier (RSB[12]=1).  The following
     * mac_8 reads x12 as its accumulator (rs3, Variant-1 port), so it must stall
     * until the MUL write-back completes before accumulating.
     *
     *   x12 = 1000 * 2 = 2000
     *   dot = {1,2,3,4}.{5,6,7,8} = 5+12+21+32 = 70
     *   x12 = 2000 + 70 = 2070 (0x816)
     */
_start:
    li       x1,  1000
    li       x2,  2
    li       x10, 0x04030201     # rs1 = {4,3,2,1}
    li       x11, 0x08070605     # rs2 = {8,7,6,5}
    li       x12, 50
    mul      x12, x1, x2         # x12 enters MUL pipeline (3 cycles), x12 = 2000
    .word    0x02B5560B          # mac_8 x12, x10, x11 -> stalls until x12 WB, then 2070 (0x816)
    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
