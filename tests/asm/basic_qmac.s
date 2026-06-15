    .globl   _start
    .section .text

    /*
     * Quad-MAC (SIMD INT8) basic test — opcode 0x0B / funct3 5 / funct7 1.
     *   QMAC x12, x10, x11 : x12 = x12 + SUM_i rs1[i]*rs2[i]   (4x signed int8)
     *
     *   rs1 = {4,3,2,1}  (0x04030201)   rs2 = {8,7,6,5}  (0x08070605)
     *   dot = 1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70
     *   x12 = 100 + 70 = 170 (0xAA)
     */
_start:
    li       x10, 0x04030201
    li       x11, 0x08070605
    li       x12, 100
    .word    0x02B5560B          # QMAC x12, x10, x11 -> x12 = 170 (0xAA)
    nop
    nop
    nop
    nop
    nop
    .include "eot_sequence.s"
