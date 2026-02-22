module soc_top #(
  parameter int N_IRQ = 64,
  parameter type apb_req_t = soc_bus_pkg::soc_apb_req_t,
  parameter type apb_rsp_t = soc_bus_pkg::soc_apb_resp_t,
  parameter type axi_req_t = soc_bus_pkg::soc_axi_req_t,
  parameter type axi_rsp_t = soc_bus_pkg::soc_axi_resp_t,
  parameter type obi_req_t = soc_bus_pkg::soc_obi_req_t,
  parameter type obi_rsp_t = soc_bus_pkg::soc_obi_rsp_t
) (
  input  logic    clk_i,
  input  logic    rst_ni,
  input  apb_req_t apb_req_i,
  output apb_rsp_t apb_rsp_o
);
  import addr_map_pkg::*;

  core_socket_if #(
    .N_IRQ(N_IRQ),
    .instr_axi_req_t(axi_req_t),
    .instr_axi_rsp_t(axi_rsp_t),
    .data_axi_req_t(axi_req_t),
    .data_axi_rsp_t(axi_rsp_t),
    .obi_req_t(obi_req_t),
    .obi_rsp_t(obi_rsp_t),
    .hartinfo_t(dm::hartinfo_t)
  ) core_socket ();

  accel_socket_if #(
    .mem_axi_req_t(axi_req_t),
    .mem_axi_rsp_t(axi_rsp_t),
    .csr_apb_req_t(apb_req_t),
    .csr_apb_rsp_t(apb_rsp_t)
  ) accel_socket ();

  logic [31:0] accel_cfg_reg_q;
  logic [31:0] debug_status_q;
  logic        apb_hit_uart;
  logic        apb_hit_debug;
  logic        apb_access;
  apb_rsp_t    apb_rsp;

  assign core_socket.clk   = clk_i;
  assign core_socket.rst_n = rst_ni;
  assign core_socket.irq   = '0;
  assign core_socket.debug_req = 1'b0;
  assign core_socket.hart_info = '0;
  assign core_socket.power_en  = 1'b1;
  assign core_socket.isolate   = 1'b0;
  assign core_socket.retain    = 1'b0;
  assign core_socket.clk_en    = 1'b1;
  assign core_socket.instr_req = '0;
  assign core_socket.data_req  = '0;
  assign core_socket.obi_req   = '0;

  assign accel_socket.clk   = clk_i;
  assign accel_socket.rst_n = rst_ni;
  assign accel_socket.irq_o = 1'b0;
  assign accel_socket.power_en = 1'b1;
  assign accel_socket.isolate  = 1'b0;
  assign accel_socket.retain   = 1'b0;
  assign accel_socket.clk_en   = 1'b1;
  assign accel_socket.mem_req  = '0;
  assign accel_socket.csr_req  = apb_req_i;
  assign accel_socket.csr_rsp  = apb_rsp;

  assign apb_hit_uart  = (apb_req_i.paddr - UART0_BASE) < UART0_SIZE;
  assign apb_hit_debug = (apb_req_i.paddr - DEBUG0_BASE) < DEBUG0_SIZE;
  assign apb_access    = apb_req_i.psel && apb_req_i.penable;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      accel_cfg_reg_q <= '0;
      debug_status_q  <= 32'hD6B0_0001;
    end else if (apb_access && apb_req_i.pwrite && apb_hit_uart) begin
      accel_cfg_reg_q <= apb_req_i.pwdata;
    end
  end

  always_comb begin
    apb_rsp = '{default: '0};
    apb_rsp.pready = 1'b1;

    if (apb_access && !apb_req_i.pwrite) begin
      if (apb_hit_uart) begin
        apb_rsp.prdata = accel_cfg_reg_q;
      end else if (apb_hit_debug) begin
        // Placeholder hook for riscv-dbg integration.
        apb_rsp.prdata = debug_status_q;
      end else begin
        apb_rsp.pslverr = 1'b1;
      end
    end
  end

  assign apb_rsp_o = apb_rsp;
endmodule
