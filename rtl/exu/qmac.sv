///////////////////////////////////////////////////////////////////////////////
//     Copyright (c) 2025 Siliscale Consulting, LLC
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
//           _____
//          /\    \
//         /::\    \
//        /::::\    \
//       /::::::\    \
//      /:::/\:::\    \
//     /:::/__\:::\    \            Vendor      : Siliscale
//     \:::\   \:::\    \           Version     : 2025.1
//   ___\:::\   \:::\    \          Description : Tiny Vedas - QUAD MAC (SIMD INT8)
//  /\   \:::\   \:::\    \
// /::\   \:::\   \:::\____\
// \:::\   \:::\   \::/    /
//  \:::\   \:::\   \/____/
//   \:::\   \:::\    \
//    \:::\   \:::\____\
//     \:::\  /:::/    /
//      \:::\/:::/    /
//       \::::::/    /
//        \::::/    /
//         \::/    /
//          \/____/
///////////////////////////////////////////////////////////////////////////////
//
// Single-cycle combinational Quad-MAC (SIMD) functional unit.
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

module qmac (

    input logic clk,
    input logic rstn,

    input idu1_out_t qmac_ctrl,

    output logic [XLEN-1:0] instr_tag_out,
    output logic [    31:0] instr_out,

    output logic [XLEN-1:0] qmac_wb_data,
    output logic [     4:0] qmac_wb_rd_addr,
    output logic            qmac_wb_rd_wr_en
);

  /* Unpack the four signed 8-bit lanes from each source operand */
  logic signed [7:0] a0, a1, a2, a3;
  logic signed [7:0] b0, b1, b2, b3;

  assign a0 = qmac_ctrl.rs1_data[7:0];
  assign a1 = qmac_ctrl.rs1_data[15:8];
  assign a2 = qmac_ctrl.rs1_data[23:16];
  assign a3 = qmac_ctrl.rs1_data[31:24];

  assign b0 = qmac_ctrl.rs2_data[7:0];
  assign b1 = qmac_ctrl.rs2_data[15:8];
  assign b2 = qmac_ctrl.rs2_data[23:16];
  assign b3 = qmac_ctrl.rs2_data[31:24];

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
  assign acc = 33'($signed(qmac_ctrl.rs3_data)) + 33'(dot);

  /* Saturation to the signed 32-bit range */
  localparam logic signed [XLEN:0] SAT_MAX = 33'sd2147483647;   //  0x7FFFFFFF
  localparam logic signed [XLEN:0] SAT_MIN = -33'sd2147483648;  // -0x80000000

  logic [XLEN-1:0] qmac_wb_data_i;
  assign qmac_wb_data_i = (acc > SAT_MAX) ? 32'h7FFFFFFF :
                          (acc < SAT_MIN) ? 32'h80000000 :
                          acc[XLEN-1:0];

  logic [4:0] qmac_wb_rd_addr_i;
  logic       qmac_wb_rd_wr_en_i;

  assign qmac_wb_rd_addr_i  = qmac_ctrl.rd_addr;
  assign qmac_wb_rd_wr_en_i = qmac_ctrl.qmac & qmac_ctrl.legal & qmac_ctrl.rd & ~qmac_ctrl.nop;

  /* Single output flop -> write-back at EX+1, identical timing to the ALU */
  register_sync_rstn #(
      .WIDTH($bits({qmac_wb_data_i, qmac_wb_rd_addr_i, qmac_wb_rd_wr_en_i}))
  ) qmac_wb_data_ff (
      .clk (clk),
      .rstn(rstn),
      .din ({qmac_wb_data_i, qmac_wb_rd_addr_i, qmac_wb_rd_wr_en_i}),
      .dout({qmac_wb_data, qmac_wb_rd_addr, qmac_wb_rd_wr_en})
  );

  register_sync_rstn #(
      .WIDTH(XLEN + 32)
  ) instr_tag_ff (
      .clk (clk),
      .rstn(rstn),
      .din ({qmac_ctrl.instr_tag, qmac_ctrl.instr}),
      .dout({instr_tag_out, instr_out})
  );

endmodule
