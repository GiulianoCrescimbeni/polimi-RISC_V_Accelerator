#!/usr/bin/env python3

import argparse
import sys
import os
from typing import List, Optional
from elftools.elf.elffile import ELFFile
import subprocess
import shutil
import concurrent.futures
import multiprocessing
import traceback
from tqdm import tqdm

IMEM_DEPTH = 2 ** 18
DMEM_DEPTH = 2 ** 18

# Dual-ELF flow: pin .data/.bss to a fixed address so layout is independent of
# .text size differences between the two builds (with/without -DUSE_MAC_INSN).
DUAL_TDATA = 0x130000

def run_gen(test: str) -> None:
    """Run the generator for a test."""
    # Create the folder for the test
    os.makedirs(f"work/{test}", exist_ok=True)
    test_path = test.split(".")
    extension = ""
    if test_path[0] == "c":
        extension = ".c"
    elif test_path[0] == "asm":
        extension = ".s"
    elif test_path[0] == "elf":
        extension == None
    # Try and compile the test, if it fails, print the error and exit
    try:
        if extension == ".s":
            os.system(f"riscv64-unknown-elf-gcc -O0 -I{os.path.join('tests', test_path[0])} -march=rv32im -mabi=ilp32 -o work/{test}/test.elf -nostdlib {os.path.join('tests', test_path[0], test_path[1] + extension)} -Wl,-Ttext=0x100000 > {os.path.join('work', test, 'compile.log')}")
        elif extension == ".c":
            os.system(f"riscv64-unknown-elf-gcc -O0 -I{os.path.join('tests', test_path[0])} -march=rv32im -mabi=ilp32 -o work/{test}/test.elf -fno-builtin-printf -fno-common -falign-functions=4 {os.path.join('tests', test_path[0], test_path[1] + extension)} {os.path.join('tests', test_path[0], 'lib', 'vedas_printf.o')} {os.path.join('tests', test_path[0], 'asm_functions', 'eot_sequence.s')} $LOADLIBES $LDLIBS -lm -Wl,-Ttext=0x100000 > {os.path.join('work', test, 'compile.log')}")
        else:
            os.system(f"cp {os.path.join('tests', test_path[0], test_path[1])} work/{test}/test.elf")

        os.system(f"riscv64-unknown-elf-objdump  -D work/{test}/test.elf > work/{test}/test.dump")

    # Get the reset vector from the elf file --> beginning of the _start function
    # Get the reset vector (address of _start) from the ELF file
        elf_path = os.path.join("work", test, "test.elf")
        with open(elf_path, "rb") as f:
            elf = ELFFile(f)
            symtab = elf.get_section_by_name('.symtab')
            if symtab is None:
                raise RuntimeError("No symbol table found in ELF file")
            reset_vector = None
            for symbol in symtab.iter_symbols():
                if symbol.name == "_start":
                    reset_vector = symbol['st_value']
                    return reset_vector
            if reset_vector is None:
                raise RuntimeError("Could not find _start symbol in ELF file")
            # You can now use reset_vector as needed (for debugging, logging, etc.)
            # print(f"Reset vector for {test}: 0x{reset_vector:X}")
    except Exception as e:
        print(f"Error compiling test {test}: {e}")
        sys.exit(1)

def run_iss(test: str, reset_vector: int) -> None:
    """Run the ISS for a test."""
    # Create the folder for the test
    elf_path = os.path.join("work", test, "test.elf")
    # Check if I have a memory initialization file for this test
    test_path = test.split(".")
    dmem_path = os.path.join("tests", test_path[0], test_path[1] + ".mem")
    has_dmem = os.path.exists(dmem_path)
    if has_dmem:
        # Copy the file in the work directory
        shutil.copy(dmem_path, os.path.join("work", test, "dmem.hex"))
    # try and run the ISS
    try:
        import subprocess
        cmd = ""
        if has_dmem:
            cmd = f"python3 ./tools/rv_iss.py {elf_path} {hex(reset_vector)} 0x7FFFF000 0x1000 -o {os.path.join('work', test, 'iss.log')} -m {os.path.join('work', test, 'dmem.hex')}"
        else:
            cmd = f"python3 ./tools/rv_iss.py {elf_path} {hex(reset_vector)} 0x7FFFF000 0x1000 -o {os.path.join('work', test, 'iss.log')}"
        result = subprocess.run(cmd, shell=True)
        if result.returncode != 0:
            print(f"ISS returned error code {result.returncode} for test {test}. See iss.log for details.")
            sys.exit(1)
    except Exception as e:
        print(f"Error running ISS for test {test}: {e}")
        sys.exit(1)

def prepare_imem(test: str) -> None:
    """Prepare the IMEM for a test."""
    imem_path = os.path.join("work", test, "imem.hex")
    dmem_path = os.path.join("work", test, "dmem.hex")
    elf_path = os.path.join("work", test, "test.elf")

    test_path = test.split(".")
    
    # Read the ELF file using elftools
    with open(elf_path, 'rb') as f:
        elf = ELFFile(f)
        # Get the .text section
        text_section = elf.get_section_by_name('.text')
        if not text_section:
            print("Error: No .text section found in ELF file")
            sys.exit(1)
            
        # Read the instruction data
        imem_data = text_section.data()
        if len(imem_data) > IMEM_DEPTH:
            print(f"Warning: Instruction memory truncated to {IMEM_DEPTH} bytes")
            imem_data = imem_data[:IMEM_DEPTH]
        
        # Pad with zeros to fill IMEM_DEPTH
        if len(imem_data) < IMEM_DEPTH:
            imem_data = imem_data + b'\x00' * (IMEM_DEPTH - len(imem_data))
        
        # Build a single data memory image containing all relevant sections
        dmem_image = bytearray(b'\x00' * DMEM_DEPTH)

        # Helper to copy data from a section into dmem_image at correct offset
        def copy_section_to_dmem(section):
            if not section:
                return
            base_addr = section.header['sh_addr'] - 0x100000
            data = section.data()
            if base_addr < 0 or base_addr >= DMEM_DEPTH:
                print(f"Warning: Section {section.name} base address 0x{base_addr+0x100000:x} (offset {base_addr}) out of DMEM image range")
                return
            max_bytes = min(len(data), DMEM_DEPTH - base_addr)
            dmem_image[base_addr:base_addr+max_bytes] = data[:max_bytes]
            if len(data) > max_bytes:
                print(f"Warning: Section {section.name} truncated in DMEM file to {max_bytes} bytes")

        # Copy all relevant sections in any order; later sections may overwrite overlapping regions.
        for secname in ['.data', '.rodata', '.bss', '.sdata', ".init_array", ".fini_array"]:
            sec = elf.get_section_by_name(secname)
            copy_section_to_dmem(sec)

        # Write out the merged DMEM image, 4 bytes per line, little-endian words
        with open(dmem_path, "w") as f:
            dmem_path = os.path.join("tests", test_path[0], test_path[1] + ".mem")
            has_dmem = os.path.exists(dmem_path)
            if has_dmem:
                os.system(f"cp {dmem_path} work/{test}/dmem.hex") 
            else:
                for i in range(0, DMEM_DEPTH, 4):
                    word = dmem_image[i:i+4]
                    # If less than 4 bytes (should not happen), pad with zeros
                    if len(word) < 4:
                        word = word + b'\x00' * (4 - len(word))
                    hex_str = '{:08x}'.format(int.from_bytes(word, byteorder='little'))
                    f.write(f"{hex_str}  // {hex(i)}\n")

    # Write the instruction memory as hex, 4 bytes per line
    with open(imem_path, "w") as f:
        for i in range(0, IMEM_DEPTH, 4):
            # Get 4 bytes
            word = imem_data[i:i+4]
            # Convert to hex string, removing '0x' prefix and padding to 8 chars
            hex_str = '{:08x}'.format(int.from_bytes(word, byteorder='little'))
            f.write(f"{hex_str}\n")

def read_task_list(filename: str) -> List[str]:
    """Read and return list of tests from file."""
    try:
        with open(filename, 'r') as f:
            return [line.strip() for line in f if line.strip()]
    except Exception as e:
        print(f"Error reading task list file: {e}")
        return []

def run_verilator(test: str, reset_vector: int) -> None:
    """Execute Verilator simulation."""
    has_dmem = os.path.exists(os.path.join("work", test, "dmem.hex"))
    verilator_cmd = f"export PROJ=$(pwd) && cd {os.path.join('work', test)} && verilator --cc --trace --trace-structs --build --timing --top-module core_top_tb --exe $PROJ/dv/verilator/core_top_tb.cpp -f $PROJ/rtl/core_top.flist -DICCM_INIT_FILE='\"imem.hex\"' -DRESET_VECTOR=32\\'h{hex(reset_vector).lstrip('0x')} -DSTACK_POINTER_INIT_VALUE=32\\'h80000000"
    if has_dmem:
        verilator_cmd += f" -DDCCM_INIT_FILE='\"dmem.hex\"'"
    else:
        verilator_cmd += f" -DDCCM_INIT_FILE='\"\"'"
    verilator_cmd += f" && make -j -C obj_dir -f Vcore_top_tb.mk Vcore_top_tb"
    verilator_cmd += f" && ./obj_dir/Vcore_top_tb"
    
    # Redirect both stdout and stderr to sim.log
    sim_log_path = os.path.join('work', test, 'sim.log')
    with open(sim_log_path, 'w') as sim_log:
        process = subprocess.Popen(verilator_cmd, shell=True, stdout=sim_log, stderr=subprocess.STDOUT)
        process.wait()
        # Get the exit code
        exit_code = process.returncode
        if exit_code != 0:
            print(f"Error: Verilator returned exit code {exit_code}")
            sim_log.close()
            sys.exit(1)
    
def run_xsim(test: str, reset_vector: int) -> None:
    """Execute XSim simulation."""
    has_dmem = os.path.exists(os.path.join("work", test, "dmem.hex"))
    xsim_cmd = f"export PROJ=$(pwd) && cd {os.path.join('work', test)} && xvlog -sv -f $PROJ/rtl/core_top.flist --define ICCM_INIT_FILE='\"imem.hex\"' --define RESET_VECTOR=32\\'h{hex(reset_vector).lstrip('0x')} --define STACK_POINTER_INIT_VALUE=32\\'h80000000"
    if has_dmem:
        xsim_cmd += f" --define DCCM_INIT_FILE='\"dmem.hex\"'"
    else:
        xsim_cmd += f" --define DCCM_INIT_FILE='\"\"'"
    xsim_cmd += f" && xelab -top core_top_tb -snapshot sim --debug wave && xsim sim --runall"
    
    # Redirect both stdout and stderr to sim.log
    sim_log_path = os.path.join('work', test, 'sim.log')
    with open(sim_log_path, 'w') as sim_log:
        process = subprocess.Popen(xsim_cmd, shell=True, stdout=sim_log, stderr=subprocess.STDOUT)
        process.wait()
        # Get the exit code
        exit_code = process.returncode
        if exit_code != 0:
            print(f"Error: XSim returned exit code {exit_code}")
            sim_log.close()
            sys.exit(1)

def read_iss_log(test: str):
    """Read and parse ISS log file."""
    with open(os.path.join("work", test, "iss.log"), "r") as f:
        iss_log = f.read()
    iss_exe = []
    for line in iss_log.split("\n"):
        if line != "":
            line = line.split(";") 
            iss_exe.append({
                'pc': line[0],
                'instr': line[1],
                'mnemonic': line[2],
                'touch': line[3:]
            })
    return iss_exe

def read_rtl_log(test: str):
    """Read and parse RTL log file."""
    with open(os.path.join("work", test, "rtl.log"), "r") as f:
        rtl_log = f.read()
    rtl_exe = []
    for line in rtl_log.split("\n"):
        if line != "":
            line = line.split(";")
            rtl_exe.append({
                'pc': line[1],
                'instr': line[2],
                'touch': line[3:]
            })
    return rtl_exe

def compare_results(test: str) -> None:
    # Read both log files in parallel using threads
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            iss_future = executor.submit(read_iss_log, test)
            rtl_future = executor.submit(read_rtl_log, test)
            
            # Wait for both to complete
            iss_exe = iss_future.result()
            rtl_exe = rtl_future.result()

        # Compare the logs
        test_passed = True
        sim_log_path = os.path.join('work', test, 'sim.log')
        with open(sim_log_path, 'a') as sim_log:
            pbar = tqdm(range(len(iss_exe)), desc=f"Comparing {test}", unit="instr", ncols=100, leave=False)
            for iss_idx in pbar:
                if str(iss_exe[iss_idx]['pc']).upper() != str(rtl_exe[iss_idx]['pc']).upper():
                    sim_log.write(f"Error: PC Mismatch at PC {iss_exe[iss_idx]['pc']}\n")
                    sim_log.write(f"ISS: {iss_exe[iss_idx]['pc']}\n")
                    sim_log.write(f"RTL: {rtl_exe[iss_idx]['pc']}\n")
                    test_passed = False
                elif str(iss_exe[iss_idx]['instr']).upper() != str(rtl_exe[iss_idx]['instr']).upper():
                    sim_log.write(f"Error: Instruction mismatch at PC {iss_exe[iss_idx]['pc']}\n")
                    sim_log.write(f"ISS: {iss_exe[iss_idx]['instr']}\n")
                    sim_log.write(f"RTL: {rtl_exe[iss_idx]['instr']}\n")
                    test_passed = False
                # Diffetent lenght of touch
                elif len(iss_exe[iss_idx]['touch']) != len(rtl_exe[iss_idx]['touch']):
                    sim_log.write(f"Error: Result mismatch at PC {iss_exe[iss_idx]['pc']} for instruction --> {iss_exe[iss_idx]['mnemonic']}\n")
                    sim_log.write(f"ISS: {iss_exe[iss_idx]['touch']}\n")
                    sim_log.write(f"RTL: {rtl_exe[iss_idx]['touch']}\n")
                    test_passed = False
                # Same length, check each element
                else:
                    for touch_idx in range(len(iss_exe[iss_idx]['touch'])):
                        # Remove comments after '//' from ISS value before comparison
                        iss_touch = str(iss_exe[iss_idx]['touch'][touch_idx])
                        iss_touch = iss_touch.split("//")[0].strip() if "//" in iss_touch else iss_touch
                        rtl_touch = str(rtl_exe[iss_idx]['touch'][touch_idx])
                        if iss_touch.upper() != rtl_touch.upper():
                            sim_log.write(f"Error: Result mismatch at PC {iss_exe[iss_idx]['pc']} for instruction --> {iss_exe[iss_idx]['mnemonic']}\n")
                            sim_log.write(f"ISS: {iss_exe[iss_idx]['touch'][touch_idx]}\n")
                            sim_log.write(f"RTL: {rtl_exe[iss_idx]['touch'][touch_idx]}\n")
                            test_passed = False
                if not test_passed:
                    break
            pbar.close()
    except:
        test_passed = False

    if test_passed:
        print(f"{test} {'.' * (50 - len(test))}. \033[92mPASSED\033[0m")
    else:
        print(f"{test} {'.' * (50 - len(test))}. \033[91mFAILED\033[0m")

def process_rtl_log(test: str):
    """Process the RTL log file."""
    with open(os.path.join("work", test, "rtl.log"), "r") as f:
        rtl_lines = f.readlines()
    
    # Remove newlines and filter empty lines
    rtl_lines = [line.rstrip('\n') for line in rtl_lines if line.strip()]
    total_lines = len(rtl_lines) - 1
    line_idx = 0
    pbar = tqdm(total=total_lines, desc=f"Processing RTL log {test}", unit="line", leave=False, ncols=100)
    
    while line_idx < total_lines:
        if line_idx + 1 >= len(rtl_lines):
            break
            
        line_parts = rtl_lines[line_idx].split(";")
        nxt_line_parts = rtl_lines[line_idx + 1].split(";")
        
        # Check if we need to merge (same PC and instruction, both have memory effects)
        if (len(line_parts) > 3 and len(nxt_line_parts) > 3 and 
            line_parts[1] == nxt_line_parts[1] and 
            line_parts[2] == nxt_line_parts[2] and
            "mem[" in line_parts[3] and "mem[" in nxt_line_parts[3]):
            
            effect = line_parts[3]
            nxt_effect = nxt_line_parts[3]
            
            # Get the memory address
            mem_addr = effect.split("[")[1].split("]")[0]
            alignment = int(mem_addr, 16) % 4
            
            # For unaligned stores, we need to merge the two parts
            # First part is the lower bytes (at higher address)
            # Second part is the higher bytes (at lower address)
            # For example, storing 0xCAFEBABE at 0xE:
            # First store: mem[0xE]=0xBABE (lower 2 bytes)
            # Second store: mem[0x10]=0xCAFE (higher 2 bytes)
            # We need to merge them to get: mem[0xE]=0xCAFEBABE
            lower_bytes = effect.split("=")[1].lstrip("0x")[:8-alignment*2]
            higher_bytes = nxt_effect.split("=")[1].lstrip("0x")[:8-alignment*2]
            
            # Combine them to get the full value
            merged_value = higher_bytes + lower_bytes
            
            # Update the current line with merged value
            rtl_lines[line_idx] = f"{line_parts[0]};{line_parts[1]};{line_parts[2]};mem[{mem_addr}]=0x{merged_value}"
            
            # Remove the next line
            del rtl_lines[line_idx + 1]
            total_lines -= 1
            line_idx += 1
        else:
            line_idx += 1
        
        pbar.update(1)
    
    pbar.close()
    
    # Write the updated rtl_log
    with open(os.path.join("work", test, "rtl.log"), "w") as f:
        f.write("\n".join(rtl_lines))

def calculate_perf_stats(test: str):
    # Open the rtl log file for this test
    rtl_log_path = os.path.join("work", test, "rtl.log")
    with open(rtl_log_path, "r") as f:
        rtl_lines = f.readlines()
    # Get the first line of the rtl log
    first_line = rtl_lines[0].split(";")
    # Get The last line of the rtl log
    last_line = rtl_lines[-1].split(";")
    # The number of instructions is how many lines in the RTL log we have
    num_instructions = len(rtl_lines)
    # The number of cycles is the difference between the last line and the first line
    num_cycles = int(last_line[0]) - int(first_line[0])
    # The number of cycles per instruction is the number of cycles divided by the number of instructions
    cycles_per_instruction = num_cycles / num_instructions
    # The number of instructions per cycle is the number of instructions divided by the number of cycles
    instructions_per_cycle = num_instructions / num_cycles

    # Prepare the performance stats as a pretty table
    headers = ["Metric", "Value"]
    rows = [
        ["Number of instructions", num_instructions],
        ["Number of cycles", num_cycles],
        ["Cycles per instruction", f"{cycles_per_instruction:.4f}"],
        ["Instructions per cycle", f"{instructions_per_cycle:.4f}"]
    ]

    col_width_0 = max(len(headers[0]), max(len(str(row[0])) for row in rows))
    col_width_1 = max(len(headers[1]), max(len(str(row[1])) for row in rows))

    table_lines = []
    table_lines.append(f"{headers[0]:<{col_width_0}} | {headers[1]:<{col_width_1}}")
    table_lines.append(f"{'-'*col_width_0}-+-{'-'*col_width_1}")
    for row in rows:
        table_lines.append(f"{row[0]:<{col_width_0}} | {row[1]:<{col_width_1}}")
    table_str = "\n".join(table_lines)

    # Write the table to 'stats.txt' in the test's folder
    stats_path = os.path.join("work", test, "stats.txt")
    with open(stats_path, "w") as stats_file:
        stats_file.write(table_str)

def run_gen_dual(test: str):
    """Compile two ELFs from the same C source: one without USE_MAC_INSN
    (for the ISS, emits MUL+ADD), one with -DUSE_MAC_INSN (for the RTL,
    emits the custom MAC).  .data is pinned via -Tdata so both ELFs share
    the same global layout regardless of .text-size differences.

    Returns (reset_vector, iss_elf, rtl_elf).
    """
    os.makedirs(f"work/{test}", exist_ok=True)
    test_path = test.split(".")
    src = os.path.join("tests", "c", test_path[1] + ".c")
    inc_dir = os.path.join("tests", "c")
    eot = os.path.join("tests", "c", "asm_functions", "eot_sequence.s")
    # Match the existing C-test compile flags (default crt0 provides _start);
    # we deliberately do NOT link vedas_printf.o here because the dual flow
    # verifies via globals, not UART writes.
    common_flags = (f"-O0 -I{inc_dir} -march=rv32im -mabi=ilp32 "
                    "-fno-builtin-printf -fno-common -falign-functions=4")
    ld_flags = (f"-Wl,-Ttext=0x100000 -Wl,-Tdata=0x{DUAL_TDATA:X}")

    iss_elf = os.path.join("work", test, "test_iss.elf")
    rtl_elf = os.path.join("work", test, "test_rtl.elf")
    log = os.path.join("work", test, "compile.log")

    iss_cmd = (f"riscv64-unknown-elf-gcc {common_flags} -o {iss_elf} "
               f"{src} {eot} {ld_flags} > {log} 2>&1")
    rtl_cmd = (f"riscv64-unknown-elf-gcc -DUSE_MAC_INSN {common_flags} "
               f"-o {rtl_elf} {src} {eot} {ld_flags} >> {log} 2>&1")

    if os.system(iss_cmd) != 0:
        raise RuntimeError(f"Failed to compile ISS ELF for {test} (see {log})")
    if os.system(rtl_cmd) != 0:
        raise RuntimeError(f"Failed to compile RTL ELF for {test} (see {log})")

    os.system(f"riscv64-unknown-elf-objdump -D {iss_elf} > {iss_elf}.dump")
    os.system(f"riscv64-unknown-elf-objdump -D {rtl_elf} > {rtl_elf}.dump")

    # Reset vector (address of _start) — same in both ELFs since .text is at 0x100000
    with open(iss_elf, "rb") as f:
        elf = ELFFile(f)
        symtab = elf.get_section_by_name('.symtab')
        if symtab is None:
            raise RuntimeError("No symbol table in ELF")
        reset_vector = None
        for sym in symtab.iter_symbols():
            if sym.name == "_start":
                reset_vector = sym['st_value']
                break
        if reset_vector is None:
            raise RuntimeError("No _start symbol in ELF")
    return reset_vector, iss_elf, rtl_elf


def compute_state_range(elf_path: str):
    """Return (base_byte_addr, num_words) covering the user-defined globals
    in the writable segment of the given ELF.

    We pick OBJECT symbols (with non-zero size, name NOT starting with '__')
    that fall in .data/.bss/.sdata/.sbss.  This excludes:
      - .rodata / .init_array / .fini_array — read-only segment, addresses
        shift between the two ELFs because .text size differs.
      - libc internals like __atexit0, __malloc_* — these get populated at
        startup with function pointers into .text, again shifting between
        the two ELFs (real, but not functional output).

    What's left is exactly what the test author put in globals — results[],
    y_out[], etc. — which is the committed functional output we want to diff."""
    writable = ('.data', '.bss', '.sdata', '.sbss')
    lo = None
    hi = None
    with open(elf_path, "rb") as f:
        elf = ELFFile(f)
        # Map section index -> name so we can filter symbols by their section.
        sec_names = {idx: sec.name for idx, sec in enumerate(elf.iter_sections())}
        symtab = elf.get_section_by_name('.symtab')
        if symtab is None:
            raise RuntimeError(f"No symbol table in {elf_path}")
        for sym in symtab.iter_symbols():
            if sym['st_info']['type'] != 'STT_OBJECT':
                continue
            if sym['st_size'] == 0:
                continue
            if sym.name.startswith('__'):
                continue
            shndx = sym['st_shndx']
            if not isinstance(shndx, int):
                continue
            if sec_names.get(shndx) not in writable:
                continue
            addr = sym['st_value']
            end = addr + sym['st_size']
            lo = addr if lo is None else min(lo, addr)
            hi = end if hi is None else max(hi, end)
    if lo is None:
        raise RuntimeError(
            f"No user-defined globals found in {elf_path}. "
            "Add a `volatile int results[]` (or similar) in .bss/.data "
            "to commit the values you want to verify.")
    base = lo & ~0x3
    end = (hi + 3) & ~0x3
    num_words = (end - base) // 4
    return base, num_words


def run_iss_dual(test: str, reset_vector: int, iss_elf: str,
                 state_base: int, state_words: int):
    """Run the ISS on the no-MAC ELF and dump final state."""
    state_file = os.path.join("work", test, "iss.state")
    iss_log = os.path.join("work", test, "iss.log")
    cmd = (f"python3 ./tools/rv_iss.py {iss_elf} {hex(reset_vector)} "
           f"0x7FFFF000 0x1000 -o {iss_log} "
           f"--state-file {state_file} --state-base 0x{state_base:X} "
           f"--state-words {state_words}")
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        raise RuntimeError(f"ISS failed for {test} (rc={result.returncode})")


def prepare_imem_dual(test: str, rtl_elf: str):
    """Build imem.hex / dmem.hex from the RTL ELF for the verilator/xsim run."""
    imem_path = os.path.join("work", test, "imem.hex")
    dmem_path = os.path.join("work", test, "dmem.hex")

    with open(rtl_elf, 'rb') as f:
        elf = ELFFile(f)
        text_section = elf.get_section_by_name('.text')
        if not text_section:
            raise RuntimeError("No .text section in RTL ELF")
        imem_data = text_section.data()
        if len(imem_data) > IMEM_DEPTH:
            imem_data = imem_data[:IMEM_DEPTH]
        if len(imem_data) < IMEM_DEPTH:
            imem_data = imem_data + b'\x00' * (IMEM_DEPTH - len(imem_data))

        dmem_image = bytearray(b'\x00' * DMEM_DEPTH)
        for secname in ['.data', '.rodata', '.bss', '.sdata',
                        '.init_array', '.fini_array']:
            sec = elf.get_section_by_name(secname)
            if not sec:
                continue
            base_addr = sec['sh_addr'] - 0x100000
            data = sec.data()
            if base_addr < 0 or base_addr >= DMEM_DEPTH:
                continue
            n = min(len(data), DMEM_DEPTH - base_addr)
            dmem_image[base_addr:base_addr + n] = data[:n]

    with open(imem_path, "w") as f:
        for i in range(0, IMEM_DEPTH, 4):
            word = imem_data[i:i + 4]
            if len(word) < 4:
                word = word + b'\x00' * (4 - len(word))
            f.write('{:08x}\n'.format(int.from_bytes(word, 'little')))

    with open(dmem_path, "w") as f:
        for i in range(0, DMEM_DEPTH, 4):
            word = dmem_image[i:i + 4]
            if len(word) < 4:
                word = word + b'\x00' * (4 - len(word))
            f.write('{:08x}  // {:#x}\n'.format(
                int.from_bytes(word, 'little'), i))


def run_verilator_dual(test: str, reset_vector: int, state_base: int,
                       state_words: int):
    """Run verilator with state-dump plusargs."""
    has_dmem = os.path.exists(os.path.join("work", test, "dmem.hex"))
    cmd = (f"export PROJ=$(pwd) && cd {os.path.join('work', test)} && "
           f"verilator --cc --trace --trace-structs --build --timing "
           f"--top-module core_top_tb --exe $PROJ/dv/verilator/core_top_tb.cpp "
           f"-f $PROJ/rtl/core_top.flist "
           f"-DICCM_INIT_FILE='\"imem.hex\"' "
           f"-DRESET_VECTOR=32\\'h{hex(reset_vector).lstrip('0x')} "
           f"-DSTACK_POINTER_INIT_VALUE=32\\'h80000000")
    cmd += (f" -DDCCM_INIT_FILE='\"dmem.hex\"'" if has_dmem
            else f" -DDCCM_INIT_FILE='\"\"'")
    cmd += (f" && make -j -C obj_dir -f Vcore_top_tb.mk Vcore_top_tb"
            f" && ./obj_dir/Vcore_top_tb "
            f"+STATE_DUMP_BASE={state_base:08x} "
            f"+STATE_DUMP_WORDS={state_words}")
    sim_log_path = os.path.join('work', test, 'sim.log')
    with open(sim_log_path, 'w') as sim_log:
        proc = subprocess.Popen(cmd, shell=True, stdout=sim_log,
                                stderr=subprocess.STDOUT)
        proc.wait()
        if proc.returncode != 0:
            raise RuntimeError(f"Verilator failed (rc={proc.returncode})")


def run_xsim_dual(test: str, reset_vector: int, state_base: int,
                  state_words: int):
    has_dmem = os.path.exists(os.path.join("work", test, "dmem.hex"))
    cmd = (f"export PROJ=$(pwd) && cd {os.path.join('work', test)} && "
           f"xvlog -sv -f $PROJ/rtl/core_top.flist "
           f"--define ICCM_INIT_FILE='\"imem.hex\"' "
           f"--define RESET_VECTOR=32\\'h{hex(reset_vector).lstrip('0x')} "
           f"--define STACK_POINTER_INIT_VALUE=32\\'h80000000")
    cmd += (f" --define DCCM_INIT_FILE='\"dmem.hex\"'" if has_dmem
            else f" --define DCCM_INIT_FILE='\"\"'")
    cmd += (f" && xelab -top core_top_tb -snapshot sim --debug wave"
            f" && xsim sim --runall "
            f"--testplusarg STATE_DUMP_BASE={state_base:08x} "
            f"--testplusarg STATE_DUMP_WORDS={state_words}")
    sim_log_path = os.path.join('work', test, 'sim.log')
    with open(sim_log_path, 'w') as sim_log:
        proc = subprocess.Popen(cmd, shell=True, stdout=sim_log,
                                stderr=subprocess.STDOUT)
        proc.wait()
        if proc.returncode != 0:
            raise RuntimeError(f"XSim failed (rc={proc.returncode})")


def compare_final_state(test: str):
    """Diff iss.state vs rtl.state line-by-line. Both files have format:
       mem[0xADDR]=0xVALUE
    The two files must have the same set of addresses (same dump range)."""
    iss_path = os.path.join("work", test, "iss.state")
    rtl_path = os.path.join("work", test, "rtl.state")
    sim_log_path = os.path.join('work', test, 'sim.log')

    if not os.path.exists(iss_path) or not os.path.exists(rtl_path):
        with open(sim_log_path, 'a') as f:
            f.write(f"State file missing: iss={os.path.exists(iss_path)} "
                    f"rtl={os.path.exists(rtl_path)}\n")
        print(f"{test} {'.' * (50 - len(test))}. \033[91mFAILED\033[0m")
        return

    def parse(path):
        d = {}
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                # mem[0xADDR]=0xVALUE
                lhs, _, rhs = line.partition('=')
                addr = lhs[lhs.index('[')+1:lhs.index(']')]
                d[addr.lower()] = rhs.strip().lower()
        return d

    iss = parse(iss_path)
    rtl = parse(rtl_path)

    mismatches = []
    addrs = sorted(set(iss.keys()) | set(rtl.keys()))
    for a in addrs:
        if iss.get(a) != rtl.get(a):
            mismatches.append((a, iss.get(a, "<missing>"),
                                  rtl.get(a, "<missing>")))

    with open(sim_log_path, 'a') as f:
        if mismatches:
            f.write(f"\n=== Final state mismatches ({len(mismatches)}) ===\n")
            for a, i, r in mismatches[:50]:
                f.write(f"{a}: ISS={i}  RTL={r}\n")
        else:
            f.write("\n=== Final state matches ===\n")

    if mismatches:
        print(f"{test} {'.' * (50 - len(test))}. \033[91mFAILED\033[0m  "
              f"({len(mismatches)} word mismatches)")
    else:
        print(f"{test} {'.' * (50 - len(test))}. \033[92mPASSED\033[0m")


def run_e2e_dual(test: str, simulator: str):
    """Dual-ELF pipeline: ISS on no-MAC ELF, RTL on MAC ELF, compare final
    memory state of .data/.bss/.rodata."""
    try:
        reset_vector, iss_elf, rtl_elf = run_gen_dual(test)
        state_base, state_words = compute_state_range(iss_elf)
        run_iss_dual(test, reset_vector, iss_elf, state_base, state_words)
        prepare_imem_dual(test, rtl_elf)
        if simulator == "verilator":
            run_verilator_dual(test, reset_vector, state_base, state_words)
        else:
            run_xsim_dual(test, reset_vector, state_base, state_words)
        # The RTL run drops rtl.state in work/<test>/ (cwd of the simulator).
        compare_final_state(test)
    except Exception as e:
        print(f"Error running dual test {test}: {e}")
        print(traceback.format_exc())
        sys.exit(1)


def run_e2e(test: str, simulator: str):
    """Run a test through the entire pipeline."""
    try:
        reset_vector = run_gen(test)
        run_iss(test, reset_vector)
        prepare_imem(test)
        if simulator == "verilator":
            run_verilator(test, reset_vector)
        else:
            run_xsim(test, reset_vector)
        process_rtl_log(test)
        compare_results(test)
        calculate_perf_stats(test)
    except Exception as e:
        print(f"Error running test {test}: {e}")
        print(traceback.format_exc())
        sys.exit(1)

def main():
    # Parse arguments
    parser = argparse.ArgumentParser(
        description="Simulation Manager for running tests with different simulators"
    )
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-t", "--task-list", help="Path to the task list file")
    group.add_argument("-n", "--test-name", help="Name of the test to run")
    
    parser.add_argument(
        "-s", "--simulator",
        required=True,
        choices=["verilator", "xsim"],
        help="Name of the simulator to use"
    )
    
    args = parser.parse_args()
    
    # Create work directory
    os.makedirs("work", exist_ok=True)
    
    # Get list of tests to run
    tests = []
    if args.task_list:
        if not os.path.exists(args.task_list):
            print(f"Error: Task list file '{args.task_list}' not found")
            sys.exit(1)
        tests = read_task_list(args.task_list)
        if not tests:
            print("Error: No valid tests found in task list")
            sys.exit(1)
    else:
        tests = [args.test_name]
    
    # Get number of CPU cores
    num_cores = multiprocessing.cpu_count()
    
    # Pick pipeline per test: "cdual.<name>" goes through the dual-ELF flow.
    def dispatch(test):
        if test.split(".")[0] == "cdual":
            return run_e2e_dual(test, args.simulator)
        return run_e2e(test, args.simulator)

    # Run tests in parallel using thread pool
    with concurrent.futures.ThreadPoolExecutor(max_workers=num_cores) as executor:
        # Submit all tasks to the thread pool
        future_to_test = {executor.submit(dispatch, test): test for test in tests}
        
        # Process completed tasks
        for future in concurrent.futures.as_completed(future_to_test):
            test = future_to_test[future]
            try:
                future.result()  # This will raise any exceptions that occurred
                # Print a detailed tracebacki on exception
            except Exception as e:
                print(f"Error running test {test}: {e}")
                continue

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)
