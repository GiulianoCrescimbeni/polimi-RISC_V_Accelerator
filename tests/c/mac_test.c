/*
 * MAC (Multiply-Accumulate) functional verification test.
 *
 * Compiled twice in the dual-ELF flow:
 *   - without USE_MAC_INSN -> mac() expands to (acc + a*b), GCC emits MUL+ADD
 *     This ELF is fed to the ISS (which only knows RV32IM).
 *   - with -DUSE_MAC_INSN  -> mac() emits the custom MAC instruction
 *     (opcode 0x0B / funct3 0x4 / funct7 0x1, semantics: rd = rd + rs1*rs2).
 *     This ELF is fed to the RTL (which decodes the custom MAC).
 *
 * Both runs MUST leave the same final state in `results[]` (placed in .bss),
 * since this is a globally-visible deterministic location independent of
 * register allocation, stack frames, or printf state.
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

#define IAXPY_N 8

/* Globals: same address in both ELFs. */
volatile int results[16];
volatile int y_out[IAXPY_N];

int main() {
    /* Unit cases */
    results[0] = mac(100, 7, 6);          /* 142  */
    results[1] = mac(0,   5, 4);          /* 20   */
    results[2] = mac(-100, 3, 5);         /* -85  */

    /* Dot product */
    int a_arr[4] = {1, 2, 3, 4};
    int b_arr[4] = {5, 6, 7, 8};
    int acc = 0;
    for (int i = 0; i < 4; i++) {
        acc = mac(acc, a_arr[i], b_arr[i]);
    }
    results[3] = acc;                     /* 70   */

    /* Chained dependency (forwarding stress) */
    int x = 1;
    x = mac(x, 2, 3);
    x = mac(x, 4, 5);
    x = mac(x, 6, 7);
    results[4] = x;                       /* 69   */

    /* Self-MAC (rd == rs1) */
    int s = 3;
    s = mac(s, s, 4);                     /* 3 + 3*4 = 15 */
    results[5] = s;

    /* iaxpy kernel: y[i] = a*x[i] + y[i] */
    int scale = 3;
    int xv[IAXPY_N] = {1, 2, 3, 4, 5, 6, 7, 8};
    int yv[IAXPY_N] = {10, 20, 30, 40, 50, 60, 70, 80};
    for (int i = 0; i < IAXPY_N; i++) {
        yv[i] = mac(yv[i], scale, xv[i]);
    }
    for (int i = 0; i < IAXPY_N; i++) {
        y_out[i] = yv[i];
    }

    eot_sequence();
    return 0;
}
