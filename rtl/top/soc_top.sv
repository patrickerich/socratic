module soc_top #(
  parameter int N_IRQ = 64,
  parameter type apb_req_t = soc_bus_pkg::soc_apb_req_t,
  parameter type apb_rsp_t = soc_bus_pkg::soc_apb_resp_t,
  parameter type axi_req_t = soc_bus_pkg::soc_axi_req_t,
  parameter type axi_rsp_t = soc_bus_pkg::soc_axi_resp_t,
  parameter type obi_req_t = soc_bus_pkg::soc_obi_req_t,
  parameter type obi_rsp_t = soc_bus_pkg::soc_obi_rsp_t,
  parameter bit EnablePlatform = 1'b0,
  parameter logic [31:0] DebugBaseAddr = 32'h0000_0000,
  parameter logic [31:0] UartBaseAddr = 32'h1000_0000,
  parameter logic [31:0] FakeUartBaseAddr = 32'h1000_1000,
  parameter logic [31:0] RamBaseAddr = 32'h8000_0000,
  parameter int unsigned RamWords = 131072,
  parameter bit EnableFakeUart = 1'b1,
  parameter string MemInitFile = ""
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  apb_req_t apb_req_i,
  output apb_rsp_t apb_rsp_o,
  input  logic uart_rx_i,
  output logic uart_tx_o,
  input  logic jtag_tck_i,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  output logic dmactive_o,
  output logic debug_req_o,
  output logic alert_minor_o,
  output logic alert_major_internal_o,
  output logic alert_major_bus_o,
  output logic core_sleep_o
);
  import addr_map_pkg::*;
  import soc_bus_pkg::*;
  import dm::*;

  if (!EnablePlatform) begin : gen_stub
    logic [31:0] accel_cfg_reg_q;
    logic [31:0] debug_status_q;
    logic        apb_hit_uart;
    logic        apb_hit_debug;
    logic        apb_access;
    apb_rsp_t    apb_rsp;

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
          apb_rsp.prdata = debug_status_q;
        end else begin
          apb_rsp.pslverr = 1'b1;
        end
      end
    end

    assign apb_rsp_o                = apb_rsp;
    assign uart_tx_o                = 1'b1;
    assign jtag_tdo_o               = 1'b0;
    assign dmactive_o               = 1'b0;
    assign debug_req_o              = 1'b0;
    assign alert_minor_o            = 1'b0;
    assign alert_major_internal_o   = 1'b0;
    assign alert_major_bus_o        = 1'b0;
    assign core_sleep_o             = 1'b0;
  end else begin : gen_platform
    localparam logic [31:0] DebugSize = 32'h0000_1000;
    localparam logic [31:0] UartSize = 32'h0000_1000;
    localparam logic [31:0] FakeUartSize = 32'h0000_0004;
    localparam logic [31:0] RamSize = RamWords * 4;
    localparam logic [31:0] DmHaltAddr = DebugBaseAddr + 32'h0000_0800;
    localparam logic [31:0] DmExceptionAddr = DebugBaseAddr + 32'h0000_0810;
    localparam dm::hartinfo_t HartInfo = '{
      zero1:      '0,
      nscratch:   4'd2,
      zero0:      '0,
      dataaccess: 1'b1,
      datasize:   dm::DataCount,
      dataaddr:   dm::DataAddr
    };

    typedef enum logic [1:0] {
      SrcInstr,
      SrcData,
      SrcSba
    } src_sel_e;

    typedef enum logic [2:0] {
      TgtRam,
      TgtUart,
      TgtFakeUart,
      TgtDebug,
      TgtInvalid
    } tgt_sel_e;

    typedef enum logic [1:0] {
      BusIdle,
      BusResp,
      BusUartSetup,
      BusUartAccess
    } bus_state_e;

    logic ndmreset;
    logic core_rst_ni;
    logic dmi_rst_n;

    dm::dmi_req_t  dmi_req;
    dm::dmi_resp_t dmi_resp;
    logic          dmi_req_valid;
    logic          dmi_req_ready;
    logic          dmi_resp_valid;
    logic          dmi_resp_ready;

    logic          dm_device_req;
    logic          dm_device_we;
    logic [31:0]   dm_device_addr;
    logic [3:0]    dm_device_be;
    logic [31:0]   dm_device_wdata;
    logic [31:0]   dm_device_rdata;

    logic          sba_req;
    logic          sba_we;
    logic [31:0]   sba_addr;
    logic [3:0]    sba_be;
    logic [31:0]   sba_wdata;
    logic          sba_gnt;
    logic          sba_r_valid;
    logic          sba_r_err;
    logic [31:0]   sba_r_rdata;

    logic          instr_req;
    logic          instr_gnt;
    logic          instr_rvalid;
    logic [31:0]   instr_addr;
    logic [31:0]   instr_rdata;
    logic          instr_err;

    logic          data_req;
    logic          data_gnt;
    logic          data_rvalid;
    logic          data_we;
    logic [3:0]    data_be;
    logic [31:0]   data_addr;
    logic [31:0]   data_wdata;
    logic [31:0]   data_rdata;
    logic          data_err;

    bus_state_e    state_q;
    src_sel_e      active_src_q;
    tgt_sel_e      active_tgt_q;
    logic [31:0]   active_addr_q;
    logic [31:0]   active_wdata_q;
    logic [3:0]    active_be_q;
    logic          active_we_q;

    soc_apb_req_t  uart_apb_req;
    soc_apb_resp_t uart_apb_rsp;
    apb_rsp_t      apb_rsp;
    logic [31:0]   ram [0:RamWords-1];

    function automatic tgt_sel_e decode_target(input logic [31:0] addr);
      if ((addr - DebugBaseAddr) < DebugSize) begin
        return TgtDebug;
      end
      if (EnableFakeUart && ((addr - FakeUartBaseAddr) < FakeUartSize)) begin
        return TgtFakeUart;
      end
      if ((addr - UartBaseAddr) < UartSize) begin
        return TgtUart;
      end
      if ((addr - RamBaseAddr) < RamSize) begin
        return TgtRam;
      end
      return TgtInvalid;
    endfunction

    integer init_i;
    initial begin
      for (init_i = 0; init_i < RamWords; init_i++) begin
        ram[init_i] = '0;
      end
      if (MemInitFile != "") begin
        $readmemh(MemInitFile, ram);
      end
    end

    assign core_rst_ni = rst_ni & ~ndmreset;

    dmi_jtag #(
      .IdcodeValue(32'h0000_0001)
    ) i_dmi_jtag (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .testmode_i       (1'b0),
      .dmi_rst_no       (dmi_rst_n),
      .dmi_req_o        (dmi_req),
      .dmi_req_valid_o  (dmi_req_valid),
      .dmi_req_ready_i  (dmi_req_ready),
      .dmi_resp_i       (dmi_resp),
      .dmi_resp_ready_o (dmi_resp_ready),
      .dmi_resp_valid_i (dmi_resp_valid),
      .tck_i            (jtag_tck_i),
      .tms_i            (jtag_tms_i),
      .trst_ni          (jtag_trst_ni),
      .td_i             (jtag_tdi_i),
      .td_o             (jtag_tdo_o),
      .tdo_oe_o         ()
    );

    dm_top #(
      .NrHarts         (1),
      .BusWidth        (32),
      .DmBaseAddress   (DebugBaseAddr),
      .SelectableHarts (1'b1)
    ) i_dm_top (
      .clk_i                (clk_i),
      .rst_ni               (rst_ni),
      .next_dm_addr_i       ('0),
      .testmode_i           (1'b0),
      .ndmreset_o           (ndmreset),
      .ndmreset_ack_i       (ndmreset),
      .dmactive_o           (dmactive_o),
      .debug_req_o          ({debug_req_o}),
      .unavailable_i        ('0),
      .hartinfo_i           ({HartInfo}),
      .slave_req_i          (dm_device_req),
      .slave_we_i           (dm_device_we),
      .slave_addr_i         (dm_device_addr),
      .slave_be_i           (dm_device_be),
      .slave_wdata_i        (dm_device_wdata),
      .slave_rdata_o        (dm_device_rdata),
      .master_req_o         (sba_req),
      .master_add_o         (sba_addr),
      .master_we_o          (sba_we),
      .master_wdata_o       (sba_wdata),
      .master_be_o          (sba_be),
      .master_gnt_i         (sba_gnt),
      .master_r_valid_i     (sba_r_valid),
      .master_r_err_i       (sba_r_err),
      .master_r_other_err_i (1'b0),
      .master_r_rdata_i     (sba_r_rdata),
      .dmi_rst_ni           (dmi_rst_n),
      .dmi_req_valid_i      (dmi_req_valid),
      .dmi_req_ready_o      (dmi_req_ready),
      .dmi_req_i            (dmi_req),
      .dmi_resp_valid_o     (dmi_resp_valid),
      .dmi_resp_ready_i     (dmi_resp_ready),
      .dmi_resp_o           (dmi_resp)
    );

    socratic_ibex_socket_adapter #(
      .BootAddr        (RamBaseAddr),
      .HartId          (32'h0),
      .DmBaseAddr      (DebugBaseAddr),
      .DmHaltAddr      (DmHaltAddr),
      .DmExceptionAddr (DmExceptionAddr)
    ) i_ibex_adapter (
      .clk_i                  (clk_i),
      .rst_ni                 (core_rst_ni),
      .debug_req_i            (debug_req_o),
      .irq_software_i         (1'b0),
      .irq_timer_i            (1'b0),
      .irq_external_i         (uart_irq),
      .irq_fast_i             ('0),
      .irq_nm_i               (1'b0),
      .instr_req_o            (instr_req),
      .instr_gnt_i            (instr_gnt),
      .instr_rvalid_i         (instr_rvalid),
      .instr_addr_o           (instr_addr),
      .instr_rdata_i          (instr_rdata),
      .instr_err_i            (instr_err),
      .data_req_o             (data_req),
      .data_gnt_i             (data_gnt),
      .data_rvalid_i          (data_rvalid),
      .data_we_o              (data_we),
      .data_be_o              (data_be),
      .data_addr_o            (data_addr),
      .data_wdata_o           (data_wdata),
      .data_rdata_i           (data_rdata),
      .data_err_i             (data_err),
      .alert_minor_o          (alert_minor_o),
      .alert_major_internal_o (alert_major_internal_o),
      .alert_major_bus_o      (alert_major_bus_o),
      .core_sleep_o           (core_sleep_o)
    );

    logic uart_irq;
    apb_uart_wrap #(
      .apb_req_t(soc_apb_req_t),
      .apb_rsp_t(soc_apb_resp_t)
    ) i_uart (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .apb_req_i (uart_apb_req),
      .apb_rsp_o (uart_apb_rsp),
      .intr_o    (uart_irq),
      .out1_no   (),
      .out2_no   (),
      .rts_no    (),
      .dtr_no    (),
      .cts_ni    (1'b0),
      .dsr_ni    (1'b0),
      .dcd_ni    (1'b0),
      .rin_ni    (1'b0),
      .sin_i     (uart_rx_i),
      .sout_o    (uart_tx_o)
    );

    always_comb begin
      instr_gnt = 1'b0;
      data_gnt  = 1'b0;
      sba_gnt   = 1'b0;

      if (state_q == BusIdle) begin
        if (sba_req) begin
          sba_gnt = 1'b1;
        end else if (data_req) begin
          data_gnt = 1'b1;
        end else if (instr_req) begin
          instr_gnt = 1'b1;
        end
      end
    end

    always_comb begin
      uart_apb_req = '{
        paddr:   active_addr_q - UartBaseAddr,
        pprot:   '0,
        psel:    1'b0,
        penable: 1'b0,
        pwrite:  active_we_q,
        pwdata:  active_wdata_q,
        pstrb:   active_be_q
      };

      dm_device_req   = 1'b0;
      dm_device_we    = active_we_q;
      dm_device_addr  = active_addr_q - DebugBaseAddr;
      dm_device_be    = active_be_q;
      dm_device_wdata = active_wdata_q;

      if (state_q == BusUartSetup) begin
        uart_apb_req.psel = 1'b1;
      end else if (state_q == BusUartAccess) begin
        uart_apb_req.psel    = 1'b1;
        uart_apb_req.penable = 1'b1;
      end

      if (state_q == BusResp && active_tgt_q == TgtDebug) begin
        dm_device_req = 1'b1;
      end

      apb_rsp = '{default: '0};
      apb_rsp.pready = 1'b1;
      if (apb_req_i.psel && apb_req_i.penable) begin
        apb_rsp.pslverr = 1'b1;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        state_q       <= BusIdle;
        active_src_q  <= SrcInstr;
        active_tgt_q  <= TgtInvalid;
        active_addr_q <= '0;
        active_wdata_q <= '0;
        active_be_q   <= '0;
        active_we_q   <= 1'b0;
        instr_rvalid  <= 1'b0;
        instr_rdata   <= '0;
        instr_err     <= 1'b0;
        data_rvalid   <= 1'b0;
        data_rdata    <= '0;
        data_err      <= 1'b0;
        sba_r_valid   <= 1'b0;
        sba_r_rdata   <= '0;
        sba_r_err     <= 1'b0;
      end else begin
        instr_rvalid <= 1'b0;
        data_rvalid  <= 1'b0;
        sba_r_valid  <= 1'b0;
        instr_err    <= 1'b0;
        data_err     <= 1'b0;
        sba_r_err    <= 1'b0;

        unique case (state_q)
          BusIdle: begin
            if (sba_req) begin
              active_src_q   <= SrcSba;
              active_tgt_q   <= decode_target(sba_addr);
              active_addr_q  <= sba_addr;
              active_wdata_q <= sba_wdata;
              active_be_q    <= sba_be;
              active_we_q    <= sba_we;
              if (decode_target(sba_addr) == TgtUart) begin
                state_q <= BusUartSetup;
              end else begin
                state_q <= BusResp;
              end
            end else if (data_req) begin
              active_src_q   <= SrcData;
              active_tgt_q   <= decode_target(data_addr);
              active_addr_q  <= data_addr;
              active_wdata_q <= data_wdata;
              active_be_q    <= data_be;
              active_we_q    <= data_we;
              if (decode_target(data_addr) == TgtUart) begin
                state_q <= BusUartSetup;
              end else begin
                state_q <= BusResp;
              end
            end else if (instr_req) begin
              active_src_q   <= SrcInstr;
              active_tgt_q   <= decode_target(instr_addr);
              active_addr_q  <= instr_addr;
              active_wdata_q <= '0;
              active_be_q    <= 4'hF;
              active_we_q    <= 1'b0;
              if (decode_target(instr_addr) == TgtUart) begin
                state_q <= BusUartSetup;
              end else begin
                state_q <= BusResp;
              end
            end
          end

          BusResp: begin
            logic [31:0] resp_data;
            logic        resp_err;
            logic [$clog2(RamWords)-1:0] word_idx;

            resp_data = '0;
            resp_err  = 1'b0;

            unique case (active_tgt_q)
              TgtRam: begin
                word_idx = (active_addr_q - RamBaseAddr) >> 2;
                if (active_we_q) begin
                  for (int b = 0; b < 4; b++) begin
                    if (active_be_q[b]) begin
                      ram[word_idx][8*b +: 8] <= active_wdata_q[8*b +: 8];
                    end
                  end
                end
                resp_data = ram[word_idx];
              end

              TgtDebug: begin
                resp_data = dm_device_rdata;
              end

              TgtFakeUart: begin
`ifndef SYNTHESIS
                if (active_we_q && active_be_q[0]) begin
                  $write("%c", active_wdata_q[7:0]);
                end
`endif
                resp_data = 32'h0;
              end

              default: begin
                resp_err = 1'b1;
              end
            endcase

            unique case (active_src_q)
              SrcInstr: begin
                instr_rvalid <= 1'b1;
                instr_rdata  <= resp_data;
                instr_err    <= resp_err;
              end

              SrcData: begin
                data_rvalid <= 1'b1;
                data_rdata  <= resp_data;
                data_err    <= resp_err;
              end

              SrcSba: begin
                sba_r_valid <= 1'b1;
                sba_r_rdata <= resp_data;
                sba_r_err   <= resp_err;
              end
            endcase

            state_q <= BusIdle;
          end

          BusUartSetup: begin
            state_q <= BusUartAccess;
          end

          BusUartAccess: begin
            if (uart_apb_rsp.pready) begin
              unique case (active_src_q)
                SrcInstr: begin
                  instr_rvalid <= 1'b1;
                  instr_rdata  <= uart_apb_rsp.prdata;
                  instr_err    <= uart_apb_rsp.pslverr;
                end

                SrcData: begin
                  data_rvalid <= 1'b1;
                  data_rdata  <= uart_apb_rsp.prdata;
                  data_err    <= uart_apb_rsp.pslverr;
                end

                SrcSba: begin
                  sba_r_valid <= 1'b1;
                  sba_r_rdata <= uart_apb_rsp.prdata;
                  sba_r_err   <= uart_apb_rsp.pslverr;
                end
              endcase
              state_q <= BusIdle;
            end
          end

          default: begin
            state_q <= BusIdle;
          end
        endcase
      end
    end

    assign apb_rsp_o = apb_rsp;
  end
endmodule
