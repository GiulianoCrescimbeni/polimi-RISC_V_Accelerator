/*
 * 2D convolution benchmark — 4x INT8 mac_8 configuration.
 *
 * Same "valid" 2D convolution as conv2d.c, but the data is INT8 and each kernel
 * ROW is processed as a single 4-lane dot product:
 *
 *   out[oi][oj] = sum_{ki=0..3} dot4( img[oi+ki][oj..oj+3], ker[ki][0..3] )
 *
 * The four pixels of a kernel row are contiguous in memory, so each row packs
 * into one 32-bit word and feeds exactly one mac_8: 4 mac_8s per output instead
 * of 16 scalar MACs.
 *
 * BIT-PARITY SIZING (mac/bit analysis).
 *   One 32-bit MAC and one mac_8 both move 64 operand bits per instruction, so a
 *   fair "same number of bits" comparison requires the SAME number of
 *   accelerator instructions — which means mac_8 must do 4x the MAC arithmetic
 *   of mac_32 (INT8 operands are 1/4 the width). conv2d.c runs 2500 outputs x
 *   16 = 40000 MAC instructions. To match that instruction count this kernel
 *   uses a 103x103 image -> 100x100 = 10000 outputs x 4 mac_8 = 40000 mac_8
 *   instructions = 160000 INT8 MACs = exactly 4x the 40000 scalar MACs (the
 *   output side is 2x mac_32's because matching instruction counts needs
 *   OH8^2 = 4*OH^2).
 *
 *   Footprint: the dual flow pins .data at 0x130000 and the DCCM ends at
 *   0x140000, so all globals must fit in 64 KiB. img(103*103)+out(4*100*100)
 *   ~= 50 KiB, within budget. (A 125x125 image overflowed the DCCM and hung
 *   the LSU — keep the footprint under 64 KiB.)
 *
 * Two builds:
 *   make sim     T=c.conv2d_mac_8 -> WITHOUT USE_MAC_INSN, mac_8() = scalar 4-lane
 *                                   reference (unpack + 4 MUL + saturate)
 *   make sim-mac T=conv2d_mac_8   -> WITH    USE_MAC_INSN, mac_8() = custom mac_8
 *                                   (one single-cycle instruction)
 * Compare work/c.conv2d_mac_8/stats.txt vs work/cdual.conv2d_mac_8/stats.txt;
 * the dual flow also diffs out[] (ISS scalar vs RTL mac_8) for correctness.
 *
 * Values are tiny (pixels 0..7, weights -3..3) so the accumulator never
 * saturates and the mac_8 build reproduces the scalar result bit-for-bit.
 */

extern void eot_sequence();

#ifdef USE_MAC_INSN
static inline int mac_8(int acc, int a, int b) {
    __asm__ volatile (
        ".insn r 0x0B, 0x5, 0x1, %0, %1, %2"
        : "+r"(acc)
        : "r"(a), "r"(b)
    );
    return acc;
}
#else
static inline int mac_8(int acc, int a, int b) {
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

#define H  103            /* 4x the MAC work of conv2d.c (bit-parity) */
#define W  103
#define K  4              /* kernel width == 4 lanes per mac_8 */
#define OH (H - K + 1)
#define OW (W - K + 1)

volatile signed char img[H * W];
volatile signed char ker[K * K];
volatile int out[OH * OW];

/* Pack four signed bytes into one 32-bit word, lane 0 in the low byte
   (the lane order the mac_8 expects). */
static inline int pack4(int b0, int b1, int b2, int b3) {
    return (b0 & 0xFF) | ((b1 & 0xFF) << 8) |
           ((b2 & 0xFF) << 16) | ((b3 & 0xFF) << 24);
}

int main() {
    /* Same generator as conv2d.c (asymmetric, so lane order matters), just
       evaluated over a larger image. */
    for (int i = 0; i < H; i++)
        for (int j = 0; j < W; j++)
            img[i * W + j] = (signed char)((i * 3 + j * 2) & 7);   /* 0..7 */

    for (int ki = 0; ki < K; ki++)
        for (int kj = 0; kj < K; kj++)
            ker[ki * K + kj] = (signed char)(ki - kj);            /* -3..3 */

    /* Each kernel row is constant -> pre-pack once. */
    int kerw[K];
    for (int ki = 0; ki < K; ki++)
        kerw[ki] = pack4(ker[ki * K + 0], ker[ki * K + 1],
                         ker[ki * K + 2], ker[ki * K + 3]);

    for (int oi = 0; oi < OH; oi++) {
        for (int oj = 0; oj < OW; oj++) {
            int acc = 0;
            for (int ki = 0; ki < K; ki++) {
                const int base = (oi + ki) * W + oj;
                int imgw = pack4(img[base + 0], img[base + 1],
                                 img[base + 2], img[base + 3]);
                acc = mac_8(acc, imgw, kerw[ki]);
            }
            out[oi * OW + oj] = acc;
        }
    }

    eot_sequence();
    return 0;
}
