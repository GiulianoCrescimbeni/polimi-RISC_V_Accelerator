/*
 * MAC performance benchmark — MAC-dominated kernel.
 *
 * Designed to be A/B compared on the RTL across two pipelines:
 *   make sim     T=c.mac_bench   -> compiled without USE_MAC_INSN, mac() = MUL+ADD
 *   make sim-mac T=mac_bench     -> compiled with    USE_MAC_INSN, mac() = custom MAC
 * Diff work/c.mac_bench/stats.txt vs work/cdual.mac_bench/stats.txt.
 *
 * Kernel: REPS outer iterations of a length-N dot product, accumulating into a
 * single global. The init phase touches the same arrays so the steady-state
 * inner loop is dominated by mac() calls, not by setup overhead.
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

#define N    64
#define REPS 4

volatile int a_arr[N];
volatile int b_arr[N];
volatile int result;

int main() {
    for (int i = 0; i < N; i++) {
        a_arr[i] = i + 1;
        b_arr[i] = (i * 2) + 3;
    }

    int acc = 0;
    for (int r = 0; r < REPS; r++) {
        for (int i = 0; i < N; i++) {
            acc = mac(acc, a_arr[i], b_arr[i]);
        }
    }
    result = acc;

    eot_sequence();
    return 0;
}
