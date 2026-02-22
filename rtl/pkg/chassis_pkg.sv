package chassis_pkg;

  typedef enum logic [1:0] {
    MAP_LINEAR,
    MAP_INTERLEAVED,
    MAP_BLOCK_INTERLEAVED,
    MAP_CUSTOM
  } mem_map_mode_e;

  typedef enum logic [1:0] {
    MEM_TECH_BEHAVIORAL,
    MEM_TECH_XILINX_BRAM,
    MEM_TECH_FOUNDRY
  } mem_tech_e;

  typedef enum logic [1:0] {
    IC_AXI_FLAT,
    IC_AXI_HIERARCHICAL,
    IC_OBI_SIMPLE
  } interconnect_e;

endpackage
