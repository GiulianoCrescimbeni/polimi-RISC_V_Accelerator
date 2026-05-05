# Open Decode Tables

A tool for generating SystemVerilog instruction decoders from YAML table definitions. This project provides a flexible and maintainable way to define instruction decode tables and automatically generate synthesizable SystemVerilog code.

## Overview

Open Decode Tables takes a YAML file describing instruction patterns and their decode outputs, and generates:
- A SystemVerilog module implementing the decoder logic
- A SystemVerilog typedef defining the output structure

This approach separates the instruction decode specification from the implementation, making it easier to maintain and verify instruction decoders for various instruction set architectures.

## Features

- **YAML-based table definitions**: Define instruction patterns and decode outputs in a human-readable format
- **Automatic validation**: Validates that all decode fields are defined in the output structure
- **SystemVerilog generation**: Generates synthesizable SystemVerilog code with casez statements
- **Flexible pattern matching**: Supports wildcard patterns (`.`) for instruction encoding flexibility
- **Multiple backends**: Currently supports a native backend (with placeholder for espresso optimization)

## Project Structure

```
open-decode-tables/
├── src/
│   └── main.py          # Main generator script
├── tables/
│   └── rv32im.yaml      # Example: RISC-V RV32IM decode table
├── gen/                  # Generated output directory (gitignored)
│   ├── rv32im_decoder.sv # Generated decoder module
│   └── decode_out_t.svh # Generated output type definition
├── LICENSE               # Apache License 2.0
└── README.md            # This file
```

## Requirements

- Python 3.x
- PyYAML (`pip install pyyaml`)

## Usage

### Basic Usage

```bash
python src/main.py -t tables/rv32im.yaml
```

This will generate:
- `gen/rv32im_decoder.sv` - The decoder module
- `gen/decode_out_t.svh` - The output type definition

### Command Line Options

```
-t, --table    : Path to the YAML table definition file (required)
-b, --backend  : Backend to use - "native" or "espresso" (default: native)
-o, --output   : Output directory for generated files (default: gen)
```

### Example

```bash
# Generate with default settings
python src/main.py -t tables/rv32im.yaml

# Specify custom output directory
python src/main.py -t tables/rv32im.yaml -o output/

# Use espresso backend (when implemented)
python src/main.py -t tables/rv32im.yaml -b espresso
```

## YAML Table Format

The YAML table file defines the decoder specification with the following structure:

```yaml
module_name: <module_name>        # Name of the generated SystemVerilog module
input: <bit_width>                # Width of the input instruction (e.g., 32)

output:
  - type_name: "<type_name>"       # Name of the output struct type
  - fields:                        # List of output fields
      [
        "field1",
        "field2",
        ...
      ]

decodes:
  - instr: "<instruction_name>"    # Instruction mnemonic
    match: "<bit_pattern>"        # Bit pattern (0, 1, or . for don't-care)
    decodes: ["field1", "field2"] # List of fields to set for this instruction
  ...
```

### Pattern Matching

The `match` field uses a bit pattern where:
- `0` - Bit must be 0
- `1` - Bit must be 1
- `.` - Don't care (wildcard)

### Example Entry

```yaml
- instr: "add"
  match: "0000000..........000.....0110011"
  decodes: ["alu", "rs1", "rs2", "rd", "add"]
```

This matches the RISC-V ADD instruction pattern and sets the `alu`, `rs1`, `rs2`, `rd`, and `add` output fields.

## Example: RISC-V RV32IM

The included `tables/rv32im.yaml` file demonstrates a complete decode table for RISC-V RV32IM, including:

- **Base Integer Instructions (RV32I)**: Arithmetic, logical, shift, comparison, branch, jump, load/store
- **Multiply Extension (M)**: Multiply, divide, and remainder operations

The generated decoder supports all standard RV32IM instructions with appropriate decode signals for:
- ALU operations
- Register sources (rs1, rs2)
- Register destinations (rd)
- Immediate values (imm12, imm20, shimm5)
- Load/store unit signals
- Branch and jump control signals
- Multiply/divide unit signals

## Generated Code

### Module Interface

The generated module has the following interface:

```systemverilog
module rv32im_decoder (
    input logic [31:0] i,
    output decode_out_t o
);
```

### Output Structure

The output type is a packed struct with one bit per decode field:

```systemverilog
typedef struct packed {
    logic alu;
    logic rs1;
    logic rs2;
    // ... other fields
} decode_out_t;
```

### Decoder Logic

The decoder uses a `casez` statement to match instruction patterns and set the appropriate output fields. Each instruction pattern is matched against the input, and the corresponding decode fields are set to 1, with all others set to 0.

## Validation

The generator performs automatic validation:
- Ensures all fields referenced in `decodes` entries are defined in the `output.fields` list
- Reports errors for any undefined fields before generating code

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! When adding new instructions or modifying decode tables:
1. Update the YAML table file
2. Regenerate the SystemVerilog code
3. Verify the generated code matches expectations
4. Test with your target instruction set architecture

## Future Work

- [ ] Implement espresso backend for optimized logic synthesis
- [ ] Support for additional instruction set architectures
- [ ] Enhanced pattern matching capabilities
- [ ] Verification test generation
- [ ] Documentation generation from YAML tables

