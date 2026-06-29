/*
 * 2D convolution benchmark — scalar 32-bit path.
 *
 * Computes a "valid" 2D convolution of an HxW image with a KxK kernel,
 * out[oi][oj] = sum_{ki,kj} img[oi+ki][oj+kj] * ker[ki][kj], accumulating in a
 * 32-bit register. This is the realistic workload version of mac_bench.c.
 *
 * Two builds give the first two of the three configurations under study:
 *   make sim     T=c.conv2d   -> WITHOUT USE_MAC_INSN, mac() = MUL+ADD
 *                                ("standard" architecture, baseline)
 *   make sim-mac T=conv2d     -> WITH    USE_MAC_INSN, mac() = custom 32-bit MAC
 *                                ("mac_32" architecture)
 * Compare work/c.conv2d/stats.txt vs work/cdual.conv2d/stats.txt.
 *
 * The 4x INT8 mac_8 configuration lives in conv2d_mac_8.c. For the
 * mac/bit analysis it is sized to issue the SAME number of accelerator
 * instructions as this file (bit-parity: one MAC and one mac_8 both move 64
 * operand bits), so it does 4x the MAC arithmetic on a 4x-larger INT8 image.
 *
 * Sizing: 53x53 image, 4x4 kernel -> 50x50 = 2500 outputs x 16 taps = 40000
 * scalar MAC instructions. Image/kernel values are kept small so the
 * accumulator never overflows and the MAC build reproduces the baseline result
 * bit-for-bit (verified by the dual ISS<->RTL state diff).
 *
 * Footprint note: the dual flow pins .data at 0x130000 and the DCCM ends at
 * 0x140000, so all globals must fit in 64 KiB. Here img(4*53*53)+out(4*50*50)
 * ~= 21 KiB, well within budget.
 */

extern void eot_sequence();

#ifdef USE_MAC_INSN
static inline int mac(int acc, int a, int b) {
    __asm__ volatile (
        ".insn r 0x0B, 0x4, 0x1, %0, %1, %2"
        : "+r"(acc)
        : "r"(a), "r"(b)
    );
    return acc;
}
#else
static inline int mac(int acc, int a, int b) {
    return acc + a * b;
}
#endif

#define H  53
#define W  53
#define K  4
#define OH (H - K + 1)
#define OW (W - K + 1)

volatile int img[H * W];
volatile int ker[K * K];
volatile int out[OH * OW];

int main() {
    /* Deterministic, small-magnitude image and kernel. */
    for (int i = 0; i < H; i++)
        for (int j = 0; j < W; j++)
            img[i * W + j] = (i * 3 + j * 2) & 7;   /* 0..7 */

    /* Asymmetric kernel: every lane within a row is distinct, so a wrong
       lane order in the mac_8 path would change the result. */
    for (int ki = 0; ki < K; ki++)
        for (int kj = 0; kj < K; kj++)
            ker[ki * K + kj] = ki - kj;             /* -3..3 */

    for (int oi = 0; oi < OH; oi++) {
        for (int oj = 0; oj < OW; oj++) {
            int acc = 0;
            for (int ki = 0; ki < K; ki++)
                for (int kj = 0; kj < K; kj++)
                    acc = mac(acc, img[(oi + ki) * W + (oj + kj)],
                                   ker[ki * K + kj]);
            out[oi * OW + oj] = acc;
        }
    }

    eot_sequence();
    return 0;
}
