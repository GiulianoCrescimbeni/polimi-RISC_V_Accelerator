/*
 * MAC performance benchmark — MAC-dominated kernel.
 *
 * Designed to be A/B compared on the RTL across two pipelines:
 *   make sim     T=c.mac_bench   -> compiled without USE_MAC_INSN, mac() = MUL+ADD
 *   make sim-mac T=mac_bench     -> compiled with    USE_MAC_INSN, mac() = custom MAC
 * Diff work/c.mac_bench/stats.txt vs work/cdual.mac_bench/stats.txt.
 *
 * Kernel: REPS outer iterations of a length-N dot product, accumulating into a
 * single register. The init phase touches the same arrays so the steady-state
 * inner loop is dominated by mac() calls, not by setup overhead.
 *
 * The accumulator is kept register-resident — no final volatile store — so the
 * cycle count reflects only the kernel itself plus the one-shot init. With
 * REPS=1024 the init/teardown is well under 0.1% of total cycles, letting the
 * measured speedup approach the asymptotic instruction-count ratio.
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
#define REPS 1024

volatile int a_arr[N];
volatile int b_arr[N];

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
    /* Keep `acc` live without writing it to memory: prevents the compiler from
     * eliminating the hot loop while removing the trailing volatile store that
     * would otherwise add fixed overhead to the cycle count. */
    __asm__ volatile ("" :: "r"(acc));

    eot_sequence();
    return 0;
}
