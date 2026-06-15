    .globl   _start
    .section .text

    /*
     * Back-to-back QMAC accumulator forwarding.
     * The second QMAC consumes x12 produced by the first.  QMAC is single-cycle
     * (write-back at EX+1), so WB->rs3 forwarding must deliver the accumulator
     * with zero extra stalls.  Lane 0 only -> arithmetic matches the scalar MAC.
     */
_start:
    li       x10, 2              # rs1 = {2,0,0,0}
    li       x11, 3              # rs2 = {3,0,0,0}
    li       x20, 4              # rs1 = {4,0,0,0}
    li       x21, 5              # rs2 = {5,0,0,0}
    li       x12, 0              # accumulator init
    .word    0x02B5560B          # QMAC x12, x10, x11  -> x12 = 0 + 2*3 = 6
    .word    0x035A560B          # QMAC x12, x20, x21  -> x12 = 6 + 4*5 = 26 (0x1A)
    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
