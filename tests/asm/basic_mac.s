    .globl   _start
    .section .text

_start:
    li       x10, 7
    li       x11, 6
    li       x12, 100
    .word    0x02B5460B          # MAC x12, x10, x11  -> x12 = 100 + 7*6 = 142 (0x8E)
    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
