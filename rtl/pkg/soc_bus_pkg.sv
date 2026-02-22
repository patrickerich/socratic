`include "axi/typedef.svh"
`include "apb/typedef.svh"
`include "obi/typedef.svh"

package soc_bus_pkg;
  localparam int unsigned AxiAddrWidth = 48;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned AxiIdWidth   = 4;
  localparam int unsigned ApbAddrWidth = 32;
  localparam int unsigned ApbDataWidth = 32;
  localparam int unsigned ApbStrbWidth = ApbDataWidth / 8;

  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiIdWidth-1:0]   axi_id_t;
  typedef logic [AxiDataWidth/8-1:0] axi_strb_t;
  typedef logic [0:0] axi_user_t;

  `AXI_TYPEDEF_ALL(soc_axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

  `OBI_TYPEDEF_MINIMAL_A_OPTIONAL(soc_obi_a_optional_t)
  `OBI_TYPEDEF_A_CHAN_T(soc_obi_a_chan_t, AxiAddrWidth, AxiDataWidth, AxiIdWidth, soc_obi_a_optional_t)
  `OBI_TYPEDEF_DEFAULT_REQ_T(soc_obi_req_t, soc_obi_a_chan_t)
  `OBI_TYPEDEF_MINIMAL_R_OPTIONAL(soc_obi_r_optional_t)
  `OBI_TYPEDEF_R_CHAN_T(soc_obi_r_chan_t, AxiDataWidth, AxiIdWidth, soc_obi_r_optional_t)
  `OBI_TYPEDEF_RSP_T(soc_obi_rsp_t, soc_obi_r_chan_t)

  typedef logic [ApbAddrWidth-1:0] apb_addr_t;
  typedef logic [ApbDataWidth-1:0] apb_data_t;
  typedef logic [ApbStrbWidth-1:0] apb_strb_t;
  `APB_TYPEDEF_ALL(soc_apb, apb_addr_t, apb_data_t, apb_strb_t)
endpackage
