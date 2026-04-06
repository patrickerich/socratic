#ifndef SOCRATIC_SIM_CTRL_H_
#define SOCRATIC_SIM_CTRL_H_

#include <stdint.h>

#define SOCRATIC_SIM_PASS 0x00000001u
#define SOCRATIC_SIM_FAIL 0x00000000u

void sim_ctrl_write(uint32_t code);
void sim_ctrl_pass(void);
void sim_ctrl_fail(uint32_t code);

#endif
