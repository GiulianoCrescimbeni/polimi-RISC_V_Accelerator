#!/bin/bash
# Performance matrix (mac/bit convention): standard / mac_32 / mac_8 per family.
# Reads cycle counts from each work/<test>/stats.txt afterwards.
set -u
cd "$(dirname "$0")/.."

run() { echo ">>> RUN $1"; NO_VCD=1 eval "$2" >/dev/null 2>&1; echo "<<< DONE $1"; }

# family            standard                         mac_32                              mac_8
run "mac_bench.c|standard" "make sim T=c.mac_bench"
run "mac_bench.c|mac_32"   "make sim-mac T=mac_bench"
run "mac_bench.c|mac_8"    "make sim-mac T=mac_8_bench"

run "mac_bench.asm|standard" "make sim T=asm.mac_bench_base"
run "mac_bench.asm|mac_32"   "make sim T=asm.mac_bench_mac"
run "mac_bench.asm|mac_8"    "make sim T=asm.mac_8_bench"

run "unrolled.asm|standard" "make sim T=asm.mac_bench_base_unrolled"
run "unrolled.asm|mac_32"   "make sim T=asm.mac_bench_mac_unrolled"
run "unrolled.asm|mac_8"    "make sim T=asm.mac_8_bench_unrolled"

run "par8.asm|standard" "make sim T=asm.mac_bench_par8_base"
run "par8.asm|mac_32"   "make sim T=asm.mac_bench_par8_mac"
run "par8.asm|mac_8"    "make sim T=asm.mac_8_bench_par8"

run "conv2d.c|standard" "make sim T=c.conv2d"
run "conv2d.c|mac_32"   "make sim-mac T=conv2d"
run "conv2d.c|mac_8"    "make sim-mac T=conv2d_mac_8"

echo "##### MATRIX DONE #####"
