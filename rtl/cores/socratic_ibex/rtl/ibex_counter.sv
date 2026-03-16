// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module ibex_counter #(
  parameter int CounterWidth = 32,
  // When set `counter_val_upd_o` provides an incremented version of the counter value, otherwise
  // the output is hard-wired to 0. This is required to allow Xilinx DSP inference to work
  // correctly. When `ProvideValUpd` is set no DSPs are inferred.
  parameter bit ProvideValUpd = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        counter_inc_i,
  input  logic        counterh_we_i,
  input  logic        counter_we_i,
  input  logic [31:0] counter_val_i,
  output logic [63:0] counter_val_o,
  output logic [63:0] counter_val_upd_o
);

  logic [63:0]             counter;
  logic [CounterWidth-1:0] counter_upd;
  logic [63:0]             counter_load;
  logic                    we;
  logic [CounterWidth-1:0] counter_d;

  // Increment
  assign counter_upd = counter[CounterWidth-1:0] + {{CounterWidth - 1{1'b0}}, 1'b1};

  // Update
  always_comb begin
    // Write
    we = counter_we_i | counterh_we_i;
    counter_load[63:32] = counter[63:32];
    counter_load[31:0]  = counter_val_i;
    if (counterh_we_i) begin
      counter_load[63:32] = counter_val_i;
      counter_load[31:0]  = counter[31:0];
    end

    // Next value logic
    if (we) begin
      counter_d = counter_load[CounterWidth-1:0];
    end else if (counter_inc_i) begin
      counter_d = counter_upd[CounterWidth-1:0];
    end else begin
      counter_d = counter[CounterWidth-1:0];
    end
  end

  // On Xilinx FPGAs, 48-bit DSPs are available that can be used for the
  // counter. Use localparam bit so the generate conditional is type-safe.
  // The use_dsp attribute is placed directly on the declaration in each
  // generate branch so the synthesiser receives a literal string value.
  localparam bit use_dsp_en = (CounterWidth < 49);

`ifdef FPGA_XILINX
  logic [CounterWidth-1:0] counter_q;
  if (use_dsp_en) begin : g_cnt_dsp
    (* use_dsp = "yes" *) logic [CounterWidth-1:0] counter_q_impl;
    // Use sync. reset for DSP.
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        counter_q_impl <= '0;
      end else begin
        counter_q_impl <= counter_d;
      end
    end
    assign counter_q = counter_q_impl;
  end else begin : g_cnt_no_dsp
    (* use_dsp = "no" *) logic [CounterWidth-1:0] counter_q_impl;
    // Use async. reset for flop.
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        counter_q_impl <= '0;
      end else begin
        counter_q_impl <= counter_d;
      end
    end
    assign counter_q = counter_q_impl;
  end
`else
  logic [CounterWidth-1:0] counter_q;
  // Use async. reset for flop.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      counter_q <= '0;
    end else begin
      counter_q <= counter_d;
    end
  end
`endif


  if (CounterWidth < 64) begin : g_counter_narrow
    logic [63:CounterWidth] unused_counter_load;

    assign counter[CounterWidth-1:0]           = counter_q;
    assign counter[63:CounterWidth]            = '0;

    if (ProvideValUpd) begin : g_counter_val_upd_o
      assign counter_val_upd_o[CounterWidth-1:0] = counter_upd;
    end else begin : g_no_counter_val_upd_o
      assign counter_val_upd_o[CounterWidth-1:0] = '0;
    end
    assign counter_val_upd_o[63:CounterWidth]  = '0;
    assign unused_counter_load                 = counter_load[63:CounterWidth];
  end else begin : g_counter_full
    assign counter           = counter_q;

    if (ProvideValUpd) begin : g_counter_val_upd_o
      assign counter_val_upd_o = counter_upd;
    end else begin : g_no_counter_val_upd_o
      assign counter_val_upd_o = '0;
    end
  end

  assign counter_val_o = counter;

endmodule
