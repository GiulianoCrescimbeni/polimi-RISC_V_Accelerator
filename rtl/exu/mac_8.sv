///////////////////////////////////////////////////////////////////////////////
//     Copyright (c) 2026 Giuliano Crescimbeni
//
//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at
//
//        http://www.apache.org/licenses/LICENSE-2.0
//
//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
///////////////////////////////////////////////////////////////////////////////
//    Description : Tiny Vedas - mac_8 (SIMD INT8)
//    Author      : Giuliano Crescimbeni - Politecnico di Milano (ACA)
//
//    Original addition to the Tiny-Vedas RV32IM core
//    (base project (c) 2025 Siliscale Consulting, LLC, Apache-2.0).
///////////////////////////////////////////////////////////////////////////////
//
// Single-cycle combinational mac_8 (SIMD) functional unit.
//
//   rd <- sat32( rd + SUM_{i=0..3} rs1[8i+7:8i] * rs2[8i+7:8i] )
//
// The 32-bit source registers are split into four signed 8-bit sub-words; four
// independent 8x8 signed multipliers produce four 16-bit partial products that
// are summed by an adder tree (18-bit) and finally added to the 32-bit signed
// accumulator (rs3_data == old rd, fetched via the Variant-1 third read port).
// The accumulation is computed on 33 bits so a signed 32-bit overflow can be
// detected and the result clamped to 0x7FFFFFFF / 0x80000000.
//
// Like the ALU, the result is registered by a single output flop, so the write-
// back lands one cycle after EX and the unit behaves as a single-cycle op for
// stall/forwarding purposes (it never asserts the multiplier busy/stall logic).
///////////////////////////////////////////////////////////////////////////////

`ifndef GLOBAL_SVH
`include "global.svh"
`endif

`ifndef TYPES_SVH
`include "types.svh"
`endif

module mac_8 (

    input logic clk,
    input logic rstn,

    input idu1_out_t mac_8_ctrl,

    output logic [XLEN-1:0] instr_tag_out,
    output logic [    31:0] instr_out,

    output logic [XLEN-1:0] mac_8_wb_data,
    output logic [     4:0] mac_8_wb_rd_addr,
    output logic            mac_8_wb_rd_wr_en
);

  /* Unpack the four signed 8-bit lanes from each source operand */
  logic signed [7:0] a0, a1, a2, a3;
  logic signed [7:0] b0, b1, b2, b3;

  assign a0 = mac_8_ctrl.rs1_data[7:0];
  assign a1 = mac_8_ctrl.rs1_data[15:8];
  assign a2 = mac_8_ctrl.rs1_data[23:16];
  assign a3 = mac_8_ctrl.rs1_data[31:24];

  assign b0 = mac_8_ctrl.rs2_data[7:0];
  assign b1 = mac_8_ctrl.rs2_data[15:8];
  assign b2 = mac_8_ctrl.rs2_data[23:16];
  assign b3 = mac_8_ctrl.rs2_data[31:24];

  /* Four parallel 8x8 signed multipliers -> four 16-bit partial products */
  logic signed [15:0] p0, p1, p2, p3;

  assign p0 = a0 * b0;
  assign p1 = a1 * b1;
  assign p2 = a2 * b2;
  assign p3 = a3 * b3;

  /* Adder tree: sum of four 16-bit products fits in 18 bits (signed).
     Each product is sign-extended to 18 bits via the width cast. */
  logic signed [17:0] dot;
  assign dot = 18'(p0) + 18'(p1) + 18'(p2) + 18'(p3);

  /* Accumulate onto the 32-bit signed accumulator (rs3_data == old rd).
     Done on 33 bits (sign-extended operands) to expose a signed 32-bit overflow. */
  logic signed [XLEN:0] acc;
  assign acc = 33'($signed(mac_8_ctrl.rs3_data)) + 33'(dot);

  /* Saturation to the signed 32-bit range */
  localparam logic signed [XLEN:0] SAT_MAX = 33'sd2147483647;   //  0x7FFFFFFF
  localparam logic signed [XLEN:0] SAT_MIN = -33'sd2147483648;  // -0x80000000

  logic [XLEN-1:0] mac_8_wb_data_i;
  assign mac_8_wb_data_i = (acc > SAT_MAX) ? 32'h7FFFFFFF :
                          (acc < SAT_MIN) ? 32'h80000000 :
                          acc[XLEN-1:0];

  logic [4:0] mac_8_wb_rd_addr_i;
  logic       mac_8_wb_rd_wr_en_i;

  assign mac_8_wb_rd_addr_i  = mac_8_ctrl.rd_addr;
  assign mac_8_wb_rd_wr_en_i = mac_8_ctrl.mac_8 & mac_8_ctrl.legal & mac_8_ctrl.rd & ~mac_8_ctrl.nop;

  /* Single output flop -> write-back at EX+1, identical timing to the ALU */
  register_sync_rstn #(
      .WIDTH($bits({mac_8_wb_data_i, mac_8_wb_rd_addr_i, mac_8_wb_rd_wr_en_i}))
  ) mac_8_wb_data_ff (
      .clk (clk),
      .rstn(rstn),
      .din ({mac_8_wb_data_i, mac_8_wb_rd_addr_i, mac_8_wb_rd_wr_en_i}),
      .dout({mac_8_wb_data, mac_8_wb_rd_addr, mac_8_wb_rd_wr_en})
  );

  register_sync_rstn #(
      .WIDTH(XLEN + 32)
  ) instr_tag_ff (
      .clk (clk),
      .rstn(rstn),
      .din ({mac_8_ctrl.instr_tag, mac_8_ctrl.instr}),
      .dout({instr_tag_out, instr_out})
  );

endmodule
