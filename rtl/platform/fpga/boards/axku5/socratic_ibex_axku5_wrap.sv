module socratic_ibex_axku5_wrap (
  input  logic       sys_clk_p,
  input  logic       sys_clk_n,
  input  logic       sys_rst_n,
  output logic [3:0] led,
  output logic       uart_tx,
  input  logic       uart_rx,
  input  logic       jtag_tck,
  input  logic       jtag_tms,
  input  logic       jtag_trst_n,
  input  logic       jtag_tdi,
  output logic       jtag_tdo
);
  import dm::*;

  logic clk_in_200;
  logic clk_in_200_buf;
  logic core_clk_raw;
  logic core_clk;
  logic pll_clkfb;
  logic pll_locked;
  logic pll_locked_r;
  logic rst_ni_raw;
  logic core_rst_ni;

  logic dmactive;
  logic debug_req;
  logic ndmreset;
  logic dmi_rst_n;

  dm::dmi_req_t  dmi_req;
  dm::dmi_resp_t dmi_resp;
  logic dmi_req_valid;
  logic dmi_req_ready;
  logic dmi_resp_valid;
  logic dmi_resp_ready;

  logic dm_device_req;
  logic dm_device_we;
  logic [31:0] dm_device_addr;
  logic [3:0]  dm_device_be;
  logic [31:0] dm_device_wdata;
  logic [31:0] dm_device_rdata;

  logic sba_req;
  logic sba_we;
  logic [31:0] sba_addr;
  logic [3:0]  sba_be;
  logic [31:0] sba_wdata;
  logic sba_gnt;
  logic sba_r_valid;
  logic sba_r_err;
  logic [31:0] sba_r_rdata;

  logic uart_irq;
  logic alert_minor;
  logic alert_major_internal;
  logic alert_major_bus;
  logic core_sleep;
  logic jtag_tck_buf;

  localparam dm::hartinfo_t HartInfo = '{
    zero1:      '0,
    nscratch:   4'd2,
    zero0:      '0,
    dataaccess: 1'b1,
    datasize:   dm::DataCount,
    dataaddr:   dm::DataAddr
  };

  IBUFDS i_sys_clk_ibufds (
    .I (sys_clk_p),
    .IB(sys_clk_n),
    .O (clk_in_200)
  );

  BUFG i_sys_clk_bufg (
    .I(clk_in_200),
    .O(clk_in_200_buf)
  );

  PLLE2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT(5),
    .CLKIN1_PERIOD(5.0),
    .CLKOUT0_DIVIDE(20),
    .DIVCLK_DIVIDE(1),
    .STARTUP_WAIT("FALSE")
  ) i_pll (
    .CLKOUT0(core_clk_raw),
    .CLKOUT1(),
    .CLKOUT2(),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKFBOUT(pll_clkfb),
    .LOCKED(pll_locked),
    .CLKIN1(clk_in_200_buf),
    .PWRDWN(1'b0),
    .RST(1'b0),
    .CLKFBIN(pll_clkfb)
  );

  BUFG i_core_clk_bufg (
    .I(core_clk_raw),
    .O(core_clk)
  );

  always_ff @(posedge core_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      pll_locked_r <= 1'b0;
      rst_ni_raw   <= 1'b0;
      core_rst_ni  <= 1'b0;
    end else begin
      pll_locked_r <= pll_locked;
      rst_ni_raw   <= pll_locked_r;
      core_rst_ni  <= pll_locked_r & ~ndmreset;
    end
  end

  BUFGCE i_jtag_tck_bufg (
    .I (jtag_tck),
    .CE(1'b1),
    .O (jtag_tck_buf)
  );

  dmi_jtag #(
    .IdcodeValue(32'h0000_0001)
  ) i_dmi_jtag (
    .clk_i            (core_clk),
    .rst_ni           (rst_ni_raw),
    .testmode_i       (1'b0),
    .dmi_rst_no       (dmi_rst_n),
    .dmi_req_o        (dmi_req),
    .dmi_req_valid_o  (dmi_req_valid),
    .dmi_req_ready_i  (dmi_req_ready),
    .dmi_resp_i       (dmi_resp),
    .dmi_resp_ready_o (dmi_resp_ready),
    .dmi_resp_valid_i (dmi_resp_valid),
    .tck_i            (jtag_tck_buf),
    .tms_i            (jtag_tms),
    .trst_ni          (jtag_trst_n),
    .td_i             (jtag_tdi),
    .td_o             (jtag_tdo),
    .tdo_oe_o         ()
  );

  dm_top #(
    .NrHarts        (1),
    .BusWidth       (32),
    .DmBaseAddress  (32'h0000_0000),
    .SelectableHarts(1'b1)
  ) i_dm_top (
    .clk_i               (core_clk),
    .rst_ni              (rst_ni_raw),
    .next_dm_addr_i      ('0),
    .testmode_i          (1'b0),
    .ndmreset_o          (ndmreset),
    .ndmreset_ack_i      (ndmreset),
    .dmactive_o          (dmactive),
    .debug_req_o         ({debug_req}),
    .unavailable_i       ('0),
    .hartinfo_i          ({HartInfo}),
    .slave_req_i         (dm_device_req),
    .slave_we_i          (dm_device_we),
    .slave_addr_i        (dm_device_addr),
    .slave_be_i          (dm_device_be),
    .slave_wdata_i       (dm_device_wdata),
    .slave_rdata_o       (dm_device_rdata),
    .master_req_o        (sba_req),
    .master_add_o        (sba_addr),
    .master_we_o         (sba_we),
    .master_wdata_o      (sba_wdata),
    .master_be_o         (sba_be),
    .master_gnt_i        (sba_gnt),
    .master_r_valid_i    (sba_r_valid),
    .master_r_err_i      (sba_r_err),
    .master_r_other_err_i(1'b0),
    .master_r_rdata_i    (sba_r_rdata),
    .dmi_rst_ni          (dmi_rst_n),
    .dmi_req_valid_i     (dmi_req_valid),
    .dmi_req_ready_o     (dmi_req_ready),
    .dmi_req_i           (dmi_req),
    .dmi_resp_valid_o    (dmi_resp_valid),
    .dmi_resp_ready_i    (dmi_resp_ready),
    .dmi_resp_o          (dmi_resp)
  );

  soc_fpga i_soc_fpga (
    .clk_i                  (core_clk),
    .rst_ni                 (rst_ni_raw),
    .core_rst_ni_i          (core_rst_ni),
    .debug_req_i            (debug_req),
    .uart_rx_i              (uart_rx),
    .uart_tx_o              (uart_tx),
    .uart_irq_o             (uart_irq),
    .dm_device_req_o        (dm_device_req),
    .dm_device_we_o         (dm_device_we),
    .dm_device_addr_o       (dm_device_addr),
    .dm_device_be_o         (dm_device_be),
    .dm_device_wdata_o      (dm_device_wdata),
    .dm_device_rdata_i      (dm_device_rdata),
    .sba_req_i              (sba_req),
    .sba_we_i               (sba_we),
    .sba_addr_i             (sba_addr),
    .sba_be_i               (sba_be),
    .sba_wdata_i            (sba_wdata),
    .sba_gnt_o              (sba_gnt),
    .sba_r_valid_o          (sba_r_valid),
    .sba_r_err_o            (sba_r_err),
    .sba_r_rdata_o          (sba_r_rdata),
    .alert_minor_o          (alert_minor),
    .alert_major_internal_o (alert_major_internal),
    .alert_major_bus_o      (alert_major_bus),
    .core_sleep_o           (core_sleep)
  );

  assign led[0] = pll_locked;
  assign led[1] = core_rst_ni;
  assign led[2] = dmactive;
  assign led[3] = debug_req;
endmodule
