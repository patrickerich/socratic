#ifndef SOCRATIC_UART_H_
#define SOCRATIC_UART_H_

#include <stdint.h>

#define UART0_BASE 0x10000000u

void uart_init(uint32_t uart_base, uint32_t core_clk_hz, uint32_t baud);
void uart_putc(uint32_t uart_base, char c);
void uart_puts(uint32_t uart_base, const char *str);

#endif
