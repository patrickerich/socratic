module ibex_soc_dut;
  import soc_bus_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic sim_print_valid;
  logic [7:0] sim_print_data;

  soc_apb_req_t apb_req;
  soc_apb_resp_t apb_rsp;

  assign apb_req = '0;

  soc_top #(
    .apb_req_t(soc_apb_req_t),
    .apb_rsp_t(soc_apb_resp_t),
    .axi_req_t(soc_axi_req_t),
    .axi_rsp_t(soc_axi_resp_t),
    .obi_req_t(soc_obi_req_t),
    .obi_rsp_t(soc_obi_rsp_t),
    .EnablePlatform(1'b1),
    .EnableFakeUart(1'b1)
  ) i_soc_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .apb_req_i(apb_req),
    .apb_rsp_o(apb_rsp),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .jtag_tck_i(1'b0),
    .jtag_tms_i(1'b0),
    .jtag_trst_ni(1'b0),
    .jtag_tdi_i(1'b0),
    .jtag_tdo_o(),
    .dmactive_o(),
    .debug_req_o(),
    .sim_print_valid_o(sim_print_valid),
    .sim_print_data_o(sim_print_data),
    .alert_minor_o(),
    .alert_major_internal_o(),
    .alert_major_bus_o(),
    .core_sleep_o()
  );
endmodule
