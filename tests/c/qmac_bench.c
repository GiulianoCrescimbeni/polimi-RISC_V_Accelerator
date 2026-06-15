/*
 * Quad-MAC performance benchmark — INT8 dot-product kernel.
 *
 * A/B compared on the RTL across two builds:
 *   make sim     T=c.qmac_bench  -> without USE_MAC_INSN, qmac() = scalar C
 *                                   (4 unpacks + 4 MUL + adds + saturation)
 *   make sim-mac T=qmac_bench    -> with    USE_MAC_INSN, qmac() = custom QMAC
 *                                   (one single-cycle instruction)
 * Diff work/c.qmac_bench/stats.txt vs work/cdual.qmac_bench/stats.txt.
 *
 * Kernel: REPS outer iterations of a length-N packed-INT8 dot product,
 * accumulating into a single register.  Each element holds four signed 8-bit
 * lanes, so one qmac() call does four INT8 MACs.  Values are kept small so the
 * accumulator never saturates and both builds compute the identical result.
 *
 * Sizing: N=64, REPS=256 -> 16384 qmac() calls x 4 lanes = 65536 INT8
 * MAC-equivalent operations, i.e. exactly the same amount of multiply-
 * accumulate work as the scalar C mac_bench (N=64, REPS=1024 = 65536 scalar
 * MACs). The two are therefore directly comparable, side by side.
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

#define N    64
#define REPS 256   /* 64 * 256 = 16384 QMACs = 65536 INT8 MAC-equivalent ops */

volatile int a_arr[N];
volatile int b_arr[N];

int main() {
    /* Each word packs four signed bytes; keep magnitudes tiny (1..4) so the
       running accumulator stays well within INT32 over REPS*N*4 products. */
    for (int i = 0; i < N; i++) {
        int la = (i & 3) + 1;          /* 1..4 */
        int lb = ((i >> 2) & 3) + 1;   /* 1..4 */
        a_arr[i] = (la & 0xFF) | ((la & 0xFF) << 8) | ((la & 0xFF) << 16) | ((la & 0xFF) << 24);
        b_arr[i] = (lb & 0xFF) | ((lb & 0xFF) << 8) | ((lb & 0xFF) << 16) | ((lb & 0xFF) << 24);
    }

    int acc = 0;
    for (int r = 0; r < REPS; r++) {
        for (int i = 0; i < N; i++) {
            acc = qmac(acc, a_arr[i], b_arr[i]);
        }
    }
    /* Keep `acc` live without a memory store so the hot loop is not eliminated. */
    __asm__ volatile ("" :: "r"(acc));

    eot_sequence();
    return 0;
}
