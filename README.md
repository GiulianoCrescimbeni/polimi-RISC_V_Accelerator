# RISC-V ISA Acceleration for AI Kernels
Custom RISC-V ISA extension that accelerates the multiply–accumulate (MAC) loops
at the heart of neural-network inference and DSP kernels. Two custom instructions
— **`mac_32`** (scalar fused MAC) and **`mac_8`** (4-lane INT8 SIMD MAC) — are
designed, implemented in SystemVerilog and evaluated on a set of benchmarks under
an equal *operand-bit* (MAC-per-bit) comparison.

The work is built on top of [**Tiny-Vedas**](https://github.com/spzbrnmrc/Tiny-Vedas),
a compact 4-stage in-order RV32IM core (IFU → IDU0 → IDU1 → EXU). This repository
adds the two functional units inside the execute stage, the decode/hazard support
they require, and a dual-ELF verification and benchmarking flow.

> Academic project — Advanced Computer Architectures, Politecnico di Milano
> (2025–2026). Author: **Giuliano Crescimbeni**.

## What this project adds

### The two custom instructions
| Instruction | Semantics | Precision | Latency | Where it lives |
|:-----------:|:----------|:---------:|:-------:|:---------------|
| `mac_32` | `rd ← rd + rs1·rs2` | 32-bit | 3 cycles (multiplier pipeline) | fused into `rtl/exu/mul.sv` |
| `mac_8`  | `rd ← sat₃₂(rd + Σᵢ rs1[i]·rs2[i])`, 4 signed INT8 lanes | INT8 → 32-bit saturating | 1 cycle | dedicated `rtl/exu/mac_8.sv` |

Both are **destructive**: the destination `rd` also acts as the accumulator (third
source), so no extra encoding bits are needed.

### Encoding
Both instructions live in the RISC-V **Custom-0** opcode space and share the
M-extension `funct7` prefix, differing only in `funct3` — so no standard RV32IM
encoding is touched.

| Instruction | opcode | funct7 | funct3 |
|:-----------:|:------:|:------:|:------:|
| `mac_32` | `0x0B` (Custom-0) | `0000001` | `100` |
| `mac_8`  | `0x0B` (Custom-0) | `0000001` | `101` |

In C the instructions are emitted through the GCC `.insn` directive:
`.insn r 0x0B,0x4,0x1,...` (`mac_32`) and `.insn r 0x0B,0x5,0x1,...` (`mac_8`).

### Microarchitecture highlights
- **`mac_32`** grafts a 32-bit adder at stage E3 of the existing 3-stage
  multiplier, folding the product into the accumulator before write-back. A third
  register-file read port supplies the accumulator, the register scoreboard (RSB)
  is extended to catch RAW hazards on `rd`, and EXU→IDU1 forwarding is replicated
  for the third operand.
- **`mac_8`** is a dedicated single-cycle combinational unit beside the
  ALU/MUL/DIV/LSU: four parallel signed 8×8 multipliers feed an adder tree, and
  the dot product is added to the 32-bit accumulator on 33 bits (guard bit) and
  saturated. It reuses the accumulator infrastructure but never enters the
  multiplier pipeline, so for hazard purposes it behaves as a single-cycle op.
- **Single write-back per cycle**: since every FU drives one OR-combined
  write-back bus, dispatch holds a single-cycle producer in execute while the LSU
  is busy, fixing a load/`mac_8` write-back collision surfaced by the convolution
  benchmark.

## Features (base core, provided by Tiny-Vedas)

### Architecture
- **ISA**: RISC-V RV32IM + the `mac_32`/`mac_8` custom extension
- **Pipeline**: 4-stage in-order (IFU → IDU0 → IDU1 → EXU)
- **Data Width**: 32-bit (XLEN = 32)
- **Memory**: Harvard architecture with separate instruction and data memories
- **Hazards**: register forwarding (EXU → IDU1), pipeline flush on branches,
  multi-cycle multiplier/divider

### Instruction Set Support
- **Base RV32IM**: full arithmetic, logical, shift, comparison, branch, jump,
  load/store, and MUL/DIV support (see Tiny-Vedas)
- **Custom extension**: `mac_32`, `mac_8`

## Project Structure

```
polimi-RISC_V_Accelerator/
├── rtl/                        # RTL design files
│   ├── core_top.sv            # Top-level processor module
│   ├── ifu/ifu.sv             # Instruction fetch unit
│   ├── idu/                   # Instruction decode units
│   │   ├── idu0.sv            # Decode stage 0 (register read)
│   │   ├── idu1.sv            # Decode stage 1 (dispatch + hazards, MAC-aware)
│   │   ├── reg_file.sv        # Register file (3rd read port for accumulator)
│   │   └── decode.sv          # Decode logic (mac_32/mac_8 decoded here)
│   ├── exu/                   # Execute unit
│   │   ├── exu.sv             # Execute top-level (write-back arbitration)
│   │   ├── alu.sv             # Arithmetic logic unit
│   │   ├── mul.sv             # Multiplier + fused mac_32 adder
│   │   ├── div.sv             # Divider unit
│   │   ├── lsu.sv             # Load/store unit
│   │   └── mac_8.sv           # Single-cycle 4×INT8 SIMD MAC unit  (NEW)
│   ├── include/               # Global definitions
│   └── lib/                   # Utility / memory / behavioral models
├── tests/
│   ├── asm/                   # Assembly tests + benchmarks
│   │   ├── basic_mac*.s       # mac_32 correctness/forwarding/hazard tests
│   │   ├── basic_mac_8*.s     # mac_8 correctness/forwarding/hazard tests
│   │   ├── mac_bench_*.s      # mac_bench: base / mac_32, incl. unrolled & par8
│   │   └── mac_8_bench*.s     # mac_8 benchmarks (base / unrolled / par8)
│   └── c/                     # C tests and benchmarks
│       ├── mac_bench.c        # length-64 dot product (mac_32)
│       ├── mac_8_bench.c      # length-64 dot product (mac_8)
│       ├── conv2d.c           # 2D convolution (standard / mac_32)
│       └── conv2d_mac_8.c     # 2D convolution (mac_8)
├── dv/                        # Design verification (SystemVerilog + Verilator)
├── tools/                     # sim_manager.py, decode-table gen, RISC-V ISS
├── work/                      # Per-test build/sim output
├── report.tex                 # Project report (PoliMi Executive Summary format)
├── Makefile                   # Build and simulation targets
└── LICENSE                    # Apache 2.0 license
```

## Quick Start

### Prerequisites
- **Verilator** (cycle-accurate RTL simulation)
- **RISC-V toolchain**: `riscv64-unknown-elf-gcc` (targets `rv32im` / `ilp32`)
- **Python 3** (build scripts and the golden-model ISS)

### Running simulations
Two entry points, both driven by `tools/sim_manager.py`:

```bash
# Base flow (single ELF): assembly tests and base/mac_32 benchmarks
make sim T=basic_mac_8            # -> asm.basic_mac_8
make sim T=asm.mac_bench_mac      # mac_32 dot-product benchmark

# Dual-ELF MAC flow: RTL build vs. Python ISS golden model
make sim-mac T=mac_bench          # -> cdual.mac_bench
make sim-mac T=conv2d             # 2D convolution, standard vs mac_32
make sim-mac T=qmac_bench         # mac_8 (quad-MAC) benchmark
```

> **Tip:** long benchmarks produce multi-GB waveform dumps. Set `NO_VCD=1` to
> disable VCD generation when you only need cycle/instruction counts.

## Verification

Correctness is signed off with a **dual-ELF** flow: each C test is compiled twice,
switched by the `USE_MAC_INSN` symbol —
- a portable `acc + a*b` (or scalar four-lane reference for `mac_8`) build that
  runs on a **Python RV32IM ISS** golden model, and
- the custom `.insn` build that runs on the **Verilator** RTL.

The source is identical, so any difference comes purely from the ISA extension;
operand magnitudes are kept small so no overflow/saturation occurs and the two
builds must leave **bit-for-bit identical** final state in the committed result
globals.

## Benchmarks & Results

Each testbench is run on three configurations — `standard` (RV32IM `mul+add`),
`mac_32`, and `mac_8` — under the **MAC-per-bit** convention: a `mac_32` and a
`mac_8` both move 64 operand bits per instruction, so a fair equal-bit comparison
issues the same number of accelerator instructions (making `mac_8` do 4× the MAC
arithmetic at INT8 precision).

| Benchmark | Description | `mac_32` speedup | `mac_8` speedup |
|:---------:|:------------|:----------------:|:---------------:|
| mac_bench (C)   | length-64 dot product, single accumulator | 1.06× | 1.20× |
| mac_bench (asm) | hand-written assembly version             | 1.20× | 1.50× |
| unrolled (asm)  | 8× unrolled, single accumulator           | 1.24× | 3.13× |
| par8 (asm)      | 8× unrolled, 8 accumulators (SW renaming) | **2.76×** | 3.13× |
| conv2d (C)      | "valid" 2D convolution, 4×4 kernel        | 1.04× | 0.56× |

Speedup = `cycles_standard / cycles_config` (higher is faster).

**Takeaways:**
- `mac_32` removes one `add` per MAC but every MAC traverses the 3-stage
  multiplier and serialises on the accumulator RAW chain — it only takes off with
  software register renaming (**par8, 2.76×**).
- `mac_8`, being single-cycle, never suffers the accumulator chain and improves
  CPI throughout, reaching **3.13×** — but its INT8 precision must be acceptable,
  and on `conv2d` operand marshalling (four byte loads + shifts per instruction)
  dominates, dropping it to **0.56×**.

See [`MAC_Implementation_Report.pdf`](MAC_Implementation_Report.pdf) for the full methodology, tables and discussion.

## Credits & License

The base RV32IM core is [**Tiny-Vedas**](https://github.com/spzbrnmrc/Tiny-Vedas)
by siliscale, used as a reference for a
[free course on RISC-V Processor Design](https://youtu.be/izPdo7n1u1I). The
`mac_32`/`mac_8` ISA extension, its RTL, verification and benchmarks are the
contribution of this project.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
