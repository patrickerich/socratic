module soc_sw_mon #(
  parameter type apb_req_t = logic,
  parameter logic [31:0] SimCtrlAddr = 32'h1000_2000
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic data_req_i,
  input  logic data_we_i,
  input  logic [31:0] data_addr_i,
  input  logic [31:0] data_wdata_i,
  input  apb_req_t uart_apb_req_i,
  output logic sim_print_valid_o,
  output logic [7:0] sim_print_data_o,
  output logic sim_status_valid_o,
  output logic sim_status_pass_o,
  output logic [31:0] sim_status_code_o
);
  localparam logic [31:0] UartThrOffset = 32'h0000_0000;
  localparam logic [31:0] UartLcrOffset = 32'h0000_000c;
  localparam logic [7:0] UartLcrDlabBit = 8'h80;

  logic [7:0] uart_lcr_q;
  logic       sim_ctrl_level_q;
  logic       uart_write_level_q;
  logic       sim_ctrl_level;
  logic       uart_write_level;

  always_comb begin
    sim_ctrl_level = data_req_i && data_we_i && (data_addr_i == SimCtrlAddr);
    uart_write_level = uart_apb_req_i.psel && uart_apb_req_i.penable && uart_apb_req_i.pwrite;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      uart_lcr_q         <= 8'h03;
      sim_ctrl_level_q   <= 1'b0;
      uart_write_level_q <= 1'b0;
      sim_print_valid_o  <= 1'b0;
      sim_print_data_o   <= '0;
      sim_status_valid_o <= 1'b0;
      sim_status_pass_o  <= 1'b0;
      sim_status_code_o  <= '0;
    end else begin
      sim_print_valid_o  <= 1'b0;
      sim_print_data_o   <= '0;
      sim_status_valid_o <= 1'b0;
      sim_status_pass_o  <= 1'b0;
      sim_status_code_o  <= '0;

      if (uart_write_level && !uart_write_level_q) begin
        if (uart_apb_req_i.paddr == UartLcrOffset) begin
          uart_lcr_q <= uart_apb_req_i.pwdata[7:0];
        end else if ((uart_apb_req_i.paddr == UartThrOffset) &&
                     ((uart_lcr_q & UartLcrDlabBit) == 8'h00) &&
                     (uart_apb_req_i.pwdata[7:0] != 8'h0d)) begin
          sim_print_valid_o <= 1'b1;
          sim_print_data_o  <= uart_apb_req_i.pwdata[7:0];
        end
      end

      if (sim_ctrl_level && !sim_ctrl_level_q) begin
        sim_status_valid_o <= 1'b1;
        sim_status_pass_o  <= data_wdata_i[0];
        sim_status_code_o  <= data_wdata_i;
      end

      sim_ctrl_level_q   <= sim_ctrl_level;
      uart_write_level_q <= uart_write_level;
    end
  end
endmodule
