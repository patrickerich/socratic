# AXKU5 constraints for the Socratic Ibex FPGA wrapper.

create_clock -period 5.000 -name sys_clk_pin [get_ports sys_clk_p]
set_property PACKAGE_PIN K22 [get_ports sys_clk_p]
set_property PACKAGE_PIN K23 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports sys_clk_p]
set_property IOSTANDARD LVDS [get_ports sys_clk_n]

set_property PACKAGE_PIN J14 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]
set_property PULLTYPE PULLUP [get_ports sys_rst_n]

set_property PACKAGE_PIN J12 [get_ports {led[0]}]
set_property PACKAGE_PIN H14 [get_ports {led[1]}]
set_property PACKAGE_PIN F13 [get_ports {led[2]}]
set_property PACKAGE_PIN H12 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_property PACKAGE_PIN AD15 [get_ports uart_tx]
set_property PACKAGE_PIN AE15 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN A13 [get_ports jtag_tck]
set_property PACKAGE_PIN G12 [get_ports jtag_tms]
set_property PACKAGE_PIN E13 [get_ports jtag_tdi]
set_property PACKAGE_PIN D14 [get_ports jtag_tdo]
set_property PACKAGE_PIN C12 [get_ports jtag_trst_n]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_tck jtag_tms jtag_trst_n jtag_tdi jtag_tdo}]
set_property PULLTYPE PULLUP [get_ports {jtag_tms jtag_trst_n}]

set_max_delay -to   [get_ports {jtag_tdo}] 20
set_max_delay -from [get_ports {jtag_tms}] 20
set_max_delay -from [get_ports {jtag_tdi}] 20
set_max_delay -from [get_ports {jtag_trst_n}] 20
set_false_path -from [get_ports {jtag_trst_n}]

set_property CLOCK_BUFFER_TYPE NONE [get_ports jtag_tck]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets jtag_tck_IBUF_inst/O]
