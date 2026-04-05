APP ?= hello_world
BUILD_DIR ?= build
CMAKE_BUILD_DIR := $(BUILD_DIR)/$(APP)/cmake
ELF := $(CMAKE_BUILD_DIR)/$(APP)/$(APP)
BIN := $(BUILD_DIR)/$(APP)/$(APP).bin
DIS := $(BUILD_DIR)/$(APP)/$(APP).dis
UART_OUTPUT ?= 1
SW_CMAKE_ARGS :=

ifeq ($(UART_OUTPUT),0)
SW_CMAKE_ARGS += -DUART_OUTPUT=OFF
else
SW_CMAKE_ARGS += -DUART_OUTPUT=ON
endif

.PHONY: all clean $(APP) list-apps

all: $(APP)

$(APP): $(BIN) $(DIS)

toolchain-check:
	@command -v riscv32-unknown-elf-gcc >/dev/null 2>&1 || { \
		echo "Error: riscv32-unknown-elf-gcc not found in PATH."; \
		echo "Source ./sourceme.sh or prepend the Ibex toolchain manually."; \
		exit 1; \
	}
	@command -v riscv32-unknown-elf-objcopy >/dev/null 2>&1 || { \
		echo "Error: riscv32-unknown-elf-objcopy not found in PATH."; \
		echo "Source ./sourceme.sh or prepend the Ibex toolchain manually."; \
		exit 1; \
	}
	@command -v riscv32-unknown-elf-objdump >/dev/null 2>&1 || { \
		echo "Error: riscv32-unknown-elf-objdump not found in PATH."; \
		echo "Source ./sourceme.sh or prepend the Ibex toolchain manually."; \
		exit 1; \
	}

$(BIN) $(DIS): $(ELF)
	@mkdir -p $(BUILD_DIR)/$(APP)
	@riscv32-unknown-elf-objcopy -O binary "$(ELF)" "$(BIN)"
	@riscv32-unknown-elf-objdump -d "$(ELF)" > "$(DIS)"

$(ELF): toolchain-check
	@mkdir -p "$(CMAKE_BUILD_DIR)"
	@cd c && cmake -B "../$(CMAKE_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release $(SW_CMAKE_ARGS) .
	@cmake --build "$(CMAKE_BUILD_DIR)" --target "$(APP)"

list-apps:
	@find c -mindepth 1 -maxdepth 1 -type d ! -name common -printf '%f\n' | sort

clean:
	rm -rf "$(BUILD_DIR)"
