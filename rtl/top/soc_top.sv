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
  parameter logic [31:0] RamBaseAddr = 32'h8000_0000,
  parameter int unsigned RamWords = 131072,
  parameter string MemInitFile = "",
  parameter string MemInitPath = ""
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
  import mem_ss_pkg::*;

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
    localparam logic [31:0] RamSize = RamWords * 4;
    localparam logic [31:0] DmHaltAddr = DebugBaseAddr + 32'h0000_0800;
    localparam logic [31:0] DmExceptionAddr = DebugBaseAddr + 32'h0000_0810;
    localparam int unsigned MemInitPorts = 3;
    localparam int unsigned MemTagWidth = (MemInitPorts > 1) ? $clog2(MemInitPorts) : 1;
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

    logic          instr_mem_req;
    logic          data_mem_req;
    logic          sba_mem_req;
    logic          instr_nonram_req;
    logic          data_nonram_req;
    logic          sba_nonram_req;

    logic [MemInitPorts-1:0]                      mem_init_req;
    logic [MemInitPorts-1:0]                      mem_init_we;
    logic [MemInitPorts-1:0][31:0]                mem_init_addr;
    logic [MemInitPorts-1:0][31:0]                mem_init_wdata;
    logic [MemInitPorts-1:0][3:0]                 mem_init_be;
    logic [MemInitPorts-1:0][MemTagWidth-1:0]     mem_init_tag;
    logic [MemInitPorts-1:0]                      mem_init_gnt;
    logic [MemInitPorts-1:0]                      mem_init_rvalid;
    logic [MemInitPorts-1:0][31:0]                mem_init_rdata;
    logic [MemInitPorts-1:0]                      mem_init_err;
    logic [MemInitPorts-1:0][MemTagWidth-1:0]     mem_init_rtag;

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
    function automatic tgt_sel_e decode_target(input logic [31:0] addr);
      if ((addr - DebugBaseAddr) < DebugSize) begin
        return TgtDebug;
      end
      if ((addr - UartBaseAddr) < UartSize) begin
        return TgtUart;
      end
      if ((addr - RamBaseAddr) < RamSize) begin
        return TgtRam;
      end
      return TgtInvalid;
    endfunction

    assign core_rst_ni = rst_ni & ~ndmreset;
    assign instr_mem_req = instr_req && (decode_target(instr_addr) == TgtRam);
    assign data_mem_req  = data_req  && (decode_target(data_addr) == TgtRam);
    assign sba_mem_req   = sba_req   && (decode_target(sba_addr) == TgtRam);

    assign instr_nonram_req = instr_req && !instr_mem_req;
    assign data_nonram_req  = data_req  && !data_mem_req;
    assign sba_nonram_req   = sba_req   && !sba_mem_req;

    assign mem_init_req[0]   = instr_mem_req;
    assign mem_init_we[0]    = 1'b0;
    assign mem_init_addr[0]  = instr_addr;
    assign mem_init_wdata[0] = '0;
    assign mem_init_be[0]    = 4'hF;
    assign mem_init_tag[0]   = MemTagWidth'(0);

    assign mem_init_req[1]   = data_mem_req;
    assign mem_init_we[1]    = data_we;
    assign mem_init_addr[1]  = data_addr;
    assign mem_init_wdata[1] = data_wdata;
    assign mem_init_be[1]    = data_be;
    assign mem_init_tag[1]   = MemTagWidth'(1);

    assign mem_init_req[2]   = sba_mem_req;
    assign mem_init_we[2]    = sba_we;
    assign mem_init_addr[2]  = sba_addr;
    assign mem_init_wdata[2] = sba_wdata;
    assign mem_init_be[2]    = sba_be;
    assign mem_init_tag[2]   = MemTagWidth'(2);

    soc_mem_ss #(
      .AddrWidth(32),
      .DataWidth(32),
      .NumInitPorts(MemInitPorts),
      .InitTagWidth(MemTagWidth),
      .NumBanks(4),
      .NumWordsPerBank(RamWords / 4),
      .BaseAddr(RamBaseAddr),
      .AddressShift(2),
      .MemInitPath((MemInitPath != "") ? MemInitPath : MemInitFile),
      .MemImpl(MemImplModel)
    ) i_mem_ss (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .init_req_i(mem_init_req),
      .init_we_i(mem_init_we),
      .init_addr_i(mem_init_addr),
      .init_wdata_i(mem_init_wdata),
      .init_be_i(mem_init_be),
      .init_tag_i(mem_init_tag),
      .init_gnt_o(mem_init_gnt),
      .init_rvalid_o(mem_init_rvalid),
      .init_rdata_o(mem_init_rdata),
      .init_err_o(mem_init_err),
      .init_rtag_o(mem_init_rtag)
    );

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
      instr_gnt = mem_init_gnt[0];
      data_gnt  = mem_init_gnt[1];
      sba_gnt   = mem_init_gnt[2];

      if (state_q == BusIdle) begin
        if (sba_nonram_req) begin
          sba_gnt = 1'b1;
        end else if (data_nonram_req) begin
          data_gnt = 1'b1;
        end else if (instr_nonram_req) begin
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

        if (mem_init_rvalid[0]) begin
          instr_rvalid <= 1'b1;
          instr_rdata  <= mem_init_rdata[0];
          instr_err    <= mem_init_err[0];
        end

        if (mem_init_rvalid[1]) begin
          data_rvalid <= 1'b1;
          data_rdata  <= mem_init_rdata[1];
          data_err    <= mem_init_err[1];
        end

        if (mem_init_rvalid[2]) begin
          sba_r_valid <= 1'b1;
          sba_r_rdata <= mem_init_rdata[2];
          sba_r_err   <= mem_init_err[2];
        end

        unique case (state_q)
          BusIdle: begin
            if (sba_nonram_req) begin
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
            end else if (data_nonram_req) begin
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
            end else if (instr_nonram_req) begin
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

            resp_data = '0;
            resp_err  = 1'b0;

            unique case (active_tgt_q)
              TgtDebug: begin
                resp_data = dm_device_rdata;
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
