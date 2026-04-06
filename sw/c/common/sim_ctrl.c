#include <stdint.h>

#include "sim_ctrl.h"

static inline void mmio_write32(uint32_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

void sim_ctrl_write(uint32_t code) {
  extern volatile uint32_t sim_ctrl;
  sim_ctrl = code;
}

void sim_ctrl_pass(void) { sim_ctrl_write(SOCRATIC_SIM_PASS); }

void sim_ctrl_fail(uint32_t code) { sim_ctrl_write(code & ~SOCRATIC_SIM_PASS); }
