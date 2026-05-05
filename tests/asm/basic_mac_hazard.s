    .globl   _start
    .section .text

_start:
    li       x1,  1000
    li       x2,  2
    li       x3,  3
    li       x12, 50
    mul      x12, x1, x2         # x12 enters MUL pipeline (3 cycles), RSB[12]=1, x12 = 2000
    .word    0x0211C60B          # MAC x12, x3, x1  -> stalls until x12 WB completes
                                 # then: x12 = 2000 + (3 * 1000) = 5000 (0x1388)
    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
