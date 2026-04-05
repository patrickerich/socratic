#include "printf.h"
#include "uart.h"

int main(void) {
  uart_init(UART0_BASE, 50000000u, 115200u);
  printf("=== Socratic Ibex FPGA Demo ===\n");
  printf("UART base: 0x%08x\n", UART0_BASE);
  printf("Clock: %u Hz, baud: %u\n", 50000000u, 115200u);
  printf("UART and JTAG debug path are alive.\n");

  while (1) {
    __asm__ volatile("wfi");
  }

  return 0;
}
