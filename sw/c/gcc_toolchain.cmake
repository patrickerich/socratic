set(LINKER_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/../common/link.ld")

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_C_COMPILER riscv32-unknown-elf-gcc)
set(CMAKE_ASM_COMPILER riscv32-unknown-elf-gcc)
set(CMAKE_OBJCOPY riscv32-unknown-elf-objcopy)
set(CMAKE_OBJDUMP riscv32-unknown-elf-objdump)

# lowRISC precompiled Ibex toolchain accepts rv32imc directly
set(CMAKE_C_FLAGS_INIT   "-march=rv32imc -mabi=ilp32 -mcmodel=medany -Wall -fvisibility=hidden -ffreestanding")
set(CMAKE_ASM_FLAGS_INIT "-march=rv32imc -mabi=ilp32 -mcmodel=medany")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-nostartfiles -nostdlib -Wl,--gc-sections -T \"${LINKER_SCRIPT}\" -lgcc")
