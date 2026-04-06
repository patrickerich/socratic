module ibex_soc_dut;
  import soc_bus_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic sim_print_valid;
  logic [7:0] sim_print_data;
  logic sim_status_valid;
  logic sim_status_pass;
  logic [31:0] sim_status_code;

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
    .EnablePlatform(1'b1)
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
    .alert_minor_o(),
    .alert_major_internal_o(),
    .alert_major_bus_o(),
    .core_sleep_o()
  );

  soc_sw_mon #(
    .apb_req_t(soc_apb_req_t)
  ) i_soc_sw_mon (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .data_req_i(i_soc_top.gen_platform.data_req),
    .data_we_i(i_soc_top.gen_platform.data_we),
    .data_addr_i(i_soc_top.gen_platform.data_addr),
    .data_wdata_i(i_soc_top.gen_platform.data_wdata),
    .uart_apb_req_i(i_soc_top.gen_platform.uart_apb_req),
    .sim_print_valid_o(sim_print_valid),
    .sim_print_data_o(sim_print_data),
    .sim_status_valid_o(sim_status_valid),
    .sim_status_pass_o(sim_status_pass),
    .sim_status_code_o(sim_status_code)
  );
endmodule
