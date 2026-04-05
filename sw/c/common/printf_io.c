#include <stdint.h>

#include "printf.h"
#include "uart.h"

void _putchar(char character) {
#ifdef UART_OUTPUT
  if (character == '\n') {
    uart_putc(UART0_BASE, '\r');
  }
  uart_putc(UART0_BASE, character);
#else
  extern volatile uint32_t fake_uart;
  fake_uart = (uint32_t)(uint8_t)character;
#endif
}
