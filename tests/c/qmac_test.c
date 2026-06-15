/*
 * Quad-MAC (SIMD INT8) functional verification test.
 *
 * Compiled twice in the dual-ELF flow (tools/sim_manager.py / make sim-mac):
 *   - without USE_MAC_INSN -> qmac() is a scalar C reference: it unpacks the
 *     four signed 8-bit lanes, sums the four products onto the accumulator and
 *     saturates to the signed 32-bit range.  This ELF is fed to the ISS (which
 *     only knows RV32IM).
 *   - with -DUSE_MAC_INSN  -> qmac() emits the custom QMAC instruction
 *     (opcode 0x0B / funct3 0x5 / funct7 0x1):
 *       rd = sat32( rd + SUM_i (int8)rs1[i] * (int8)rs2[i] )
 *     This ELF is fed to the RTL (which decodes the custom QMAC).
 *
 * Both runs MUST leave the same final state in `results[]` (placed in .bss),
 * a globally-visible deterministic location independent of register allocation.
 */

extern void eot_sequence();

#ifdef USE_MAC_INSN
static inline int qmac(int acc, int a, int b) {
    __asm__ volatile (
        ".insn r 0x0B, 0x5, 0x1, %0, %1, %2"
        : "+r"(acc)
        : "r"(a), "r"(b)
    );
    return acc;
}
#else
static inline int qmac(int acc, int a, int b) {
    long long s = (long long)acc;
    s += (long long)(signed char)(a      ) * (signed char)(b      );
    s += (long long)(signed char)(a >>  8) * (signed char)(b >>  8);
    s += (long long)(signed char)(a >> 16) * (signed char)(b >> 16);
    s += (long long)(signed char)(a >> 24) * (signed char)(b >> 24);
    if (s >  2147483647LL) s =  2147483647LL;
    if (s < -2147483648LL) s = -2147483648LL;
    return (int)s;
}
#endif

/* Pack four signed bytes into a 32-bit word (lane 0 in the low byte). */
static inline int pack(int x0, int x1, int x2, int x3) {
    return ((x0 & 0xFF)      ) | ((x1 & 0xFF) <<  8) |
           ((x2 & 0xFF) << 16) | ((x3 & 0xFF) << 24);
}

/* Global: same address in both ELFs. */
volatile int results[16];

int main() {
    /* Basic positive: {1,2,3,4}.{5,6,7,8} = 5+12+21+32 = 70; +100 = 170 */
    results[0] = qmac(100, pack(1, 2, 3, 4), pack(5, 6, 7, 8));

    /* Mixed signs: {-1,-2,3,4}.{5,6,7,8} = -5-12+21+32 = 36; +0 = 36 */
    results[1] = qmac(0, pack(-1, -2, 3, 4), pack(5, 6, 7, 8));

    /* Negative accumulator: {1,1,1,1}.{1,1,1,1} = 4; -100 = -96 */
    results[2] = qmac(-100, pack(1, 1, 1, 1), pack(1, 1, 1, 1));

    /* Positive saturation: dot = 4*127*127 = 64516, acc near INT_MAX -> clamp */
    results[3] = qmac(0x7FFFFFF0, pack(127, 127, 127, 127), pack(127, 127, 127, 127));

    /* Negative saturation: dot = 4*(-128*127) = -65024, acc near INT_MIN -> clamp */
    results[4] = qmac(0x80000010, pack(-128, -128, -128, -128), pack(127, 127, 127, 127));

    /* Chained dependency (accumulator-forwarding stress) */
    int x = 0;
    x = qmac(x, pack(1, 2, 3, 4), pack(1, 1, 1, 1));   /* +10  -> 10  */
    x = qmac(x, pack(2, 2, 2, 2), pack(3, 3, 3, 3));   /* +24  -> 34  */
    x = qmac(x, pack(-1, -1, -1, -1), pack(5, 5, 5, 5));/* -20  -> 14  */
    results[5] = x;                                     /* 14  */

    /* Self (rd == rs1): accumulator register also feeds rs1 */
    int s = pack(2, 2, 2, 2);
    s = qmac(s, s, pack(1, 1, 1, 1));                   /* (2+2+2+2)=8 + (2|2|2|2 packed value) */
    results[6] = s;

    eot_sequence();
    return 0;
}
