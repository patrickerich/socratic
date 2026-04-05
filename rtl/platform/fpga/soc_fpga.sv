module soc_fpga #(
  parameter logic [31:0] DebugBaseAddr = 32'h0000_0000,
  parameter logic [31:0] UartBaseAddr  = 32'h1000_0000,
  parameter logic [31:0] RamBaseAddr   = 32'h8000_0000,
  parameter int unsigned RamWords      = 131072,
  parameter string       MemInitFile   = ""
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        core_rst_ni_i,
  input  logic        debug_req_i,

  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  output logic        uart_irq_o,

  output logic        dm_device_req_o,
  output logic        dm_device_we_o,
  output logic [31:0] dm_device_addr_o,
  output logic [3:0]  dm_device_be_o,
  output logic [31:0] dm_device_wdata_o,
  input  logic [31:0] dm_device_rdata_i,

  input  logic        sba_req_i,
  input  logic        sba_we_i,
  input  logic [31:0] sba_addr_i,
  input  logic [3:0]  sba_be_i,
  input  logic [31:0] sba_wdata_i,
  output logic        sba_gnt_o,
  output logic        sba_r_valid_o,
  output logic        sba_r_err_o,
  output logic [31:0] sba_r_rdata_o,

  output logic        alert_minor_o,
  output logic        alert_major_internal_o,
  output logic        alert_major_bus_o,
  output logic        core_sleep_o
);
  import soc_bus_pkg::*;

  localparam logic [31:0] DebugSize = 32'h0000_1000;
  localparam logic [31:0] UartSize  = 32'h0000_1000;
  localparam logic [31:0] RamSize   = RamWords * 4;
  localparam logic [31:0] DmHaltAddr = DebugBaseAddr + 32'h0000_0800;
  localparam logic [31:0] DmExceptionAddr = DebugBaseAddr + 32'h0000_0810;

  typedef enum logic [1:0] {
    SrcInstr,
    SrcData,
    SrcSba
  } src_sel_e;

  typedef enum logic [1:0] {
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

  logic        instr_req;
  logic        instr_gnt;
  logic        instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic        instr_err;

  logic        data_req;
  logic        data_gnt;
  logic        data_rvalid;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_addr;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;
  logic        data_err;

  bus_state_e state_q;
  src_sel_e   active_src_q;
  tgt_sel_e   active_tgt_q;
  logic [31:0] active_addr_q;
  logic [31:0] active_wdata_q;
  logic [3:0]  active_be_q;
  logic        active_we_q;

  logic        uart_selected_d;
  soc_apb_req_t  uart_apb_req;
  soc_apb_resp_t uart_apb_rsp;

  logic [31:0] ram [0:RamWords-1];

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

  function automatic logic [31:0] ram_word_read(input logic [31:0] addr);
    logic [$clog2(RamWords)-1:0] word_idx;
    word_idx = (addr - RamBaseAddr)[$clog2(RamWords)+1:2];
    return ram[word_idx];
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

  socratic_ibex_socket_adapter #(
    .BootAddr(RamBaseAddr),
    .HartId(32'h0),
    .DmBaseAddr(DebugBaseAddr),
    .DmHaltAddr(DmHaltAddr),
    .DmExceptionAddr(DmExceptionAddr)
  ) i_ibex_adapter (
    .clk_i                  (clk_i),
    .rst_ni                 (core_rst_ni_i),
    .debug_req_i            (debug_req_i),
    .irq_software_i         (1'b0),
    .irq_timer_i            (1'b0),
    .irq_external_i         (uart_irq_o),
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

  apb_uart_wrap #(
    .apb_req_t(soc_apb_req_t),
    .apb_rsp_t(soc_apb_resp_t)
  ) i_uart (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .apb_req_i (uart_apb_req),
    .apb_rsp_o (uart_apb_rsp),
    .intr_o    (uart_irq_o),
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
    data_gnt = 1'b0;
    sba_gnt_o = 1'b0;

    if (state_q == BusIdle) begin
      if (sba_req_i) begin
        sba_gnt_o = 1'b1;
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

    dm_device_req_o   = 1'b0;
    dm_device_we_o    = active_we_q;
    dm_device_addr_o  = active_addr_q - DebugBaseAddr;
    dm_device_be_o    = active_be_q;
    dm_device_wdata_o = active_wdata_q;

    if (state_q == BusUartSetup) begin
      uart_apb_req.psel = 1'b1;
    end else if (state_q == BusUartAccess) begin
      uart_apb_req.psel    = 1'b1;
      uart_apb_req.penable = 1'b1;
    end

    if (state_q == BusResp && active_tgt_q == TgtDebug) begin
      dm_device_req_o = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= BusIdle;
      active_src_q    <= SrcInstr;
      active_tgt_q    <= TgtInvalid;
      active_addr_q   <= '0;
      active_wdata_q  <= '0;
      active_be_q     <= '0;
      active_we_q     <= 1'b0;
      instr_rvalid    <= 1'b0;
      instr_rdata     <= '0;
      instr_err       <= 1'b0;
      data_rvalid     <= 1'b0;
      data_rdata      <= '0;
      data_err        <= 1'b0;
      sba_r_valid_o   <= 1'b0;
      sba_r_rdata_o   <= '0;
      sba_r_err_o     <= 1'b0;
    end else begin
      instr_rvalid  <= 1'b0;
      data_rvalid   <= 1'b0;
      sba_r_valid_o <= 1'b0;
      instr_err     <= 1'b0;
      data_err      <= 1'b0;
      sba_r_err_o   <= 1'b0;

      unique case (state_q)
        BusIdle: begin
          if (sba_req_i) begin
            active_src_q   <= SrcSba;
            active_tgt_q   <= decode_target(sba_addr_i);
            active_addr_q  <= sba_addr_i;
            active_wdata_q <= sba_wdata_i;
            active_be_q    <= sba_be_i;
            active_we_q    <= sba_we_i;
            if (decode_target(sba_addr_i) == TgtUart) begin
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
              word_idx = (active_addr_q - RamBaseAddr)[$clog2(RamWords)+1:2];
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
              resp_data = dm_device_rdata_i;
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
              sba_r_valid_o <= 1'b1;
              sba_r_rdata_o <= resp_data;
              sba_r_err_o   <= resp_err;
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
                sba_r_valid_o <= 1'b1;
                sba_r_rdata_o <= uart_apb_rsp.prdata;
                sba_r_err_o   <= uart_apb_rsp.pslverr;
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
endmodule
