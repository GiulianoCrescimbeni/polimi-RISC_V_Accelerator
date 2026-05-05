    .globl   _start
    .section .text

_start:
    li       x10, 2
    li       x11, 3
    li       x20, 4
    li       x21, 5
    li       x12, 0              # accumulator init
    .word    0x02B5460B          # MAC x12, x10, x11  -> x12 = 0 + 2*3 = 6
    .word    0x035A460B          # MAC x12, x20, x21  -> x12 = 6 + 4*5 = 26 (0x1A)
                                 # Second MAC depends on x12 from first MAC.
                                 # WB->rs3 forwarding should trigger; zero extra stalls.
    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
