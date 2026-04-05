# Ibex FPGA Bring-Up Plan

This repository should grow towards a layered FPGA flow where core selection, board selection, and SoC composition remain orthogonal.

## Initial Goal

Bring up a first FPGA target with:

- `socratic_ibex` as the CPU core
- `riscv-dbg` for external JTAG debug via OpenOCD/GDB
- `apb_uart` for a functional UART console
- one board target as the initial reference platform

The intended user experience is:

1. select a core
2. select a board
3. build a bitstream
4. load software over debug or preinitialize memory
5. use both UART and JTAG debug during bring-up

## Recommended Architecture

Use three layers.

### 1. Generic chassis / SoC layer

Keep `rtl/top/soc_top.sv` board-agnostic.

This layer should eventually own:

- address map
- core socket
- accelerator socket
- interconnect selection
- memory/peripheral decode

It should not contain:

- FPGA primitives
- board clocks and resets
- board pins
- vendor-specific clocking or IO logic

### 2. FPGA-oriented SoC assembly

Add a separate FPGA integration layer, for example:

- `rtl/platform/fpga/soc_fpga.sv`

This layer should instantiate:

- the selected core adapter
- block RAM / simple memory system
- `apb_uart`
- debug window and SBA plumbing for `riscv-dbg`
- simple bring-up status signals

This is the right place for a first minimal SoC that is practical on FPGA even before the fully generic chassis is complete.

### 3. Board wrappers

Add one wrapper per board, for example:

- `rtl/platform/fpga/boards/<board>/<board>_wrap.sv`
- `rtl/platform/fpga/boards/<board>/<board>.xdc`
- `rtl/platform/fpga/boards/<board>/build_<board>.tcl`

Board wrappers should own:

- input clock buffers
- PLL/MMCM/clock dividers
- reset synchronization
- LED/UART/JTAG pins
- any board-specific constraints

They should instantiate the generic FPGA SoC assembly, not the core directly.

## Core Integration Strategy

Do not wire Ibex directly into a board wrapper.

Instead add a core adapter layer, for example:

- `rtl/cores/socratic_ibex/socratic_ibex_socket_adapter.sv`

This adapter should translate from the generic `core_socket_if` contract to the concrete Ibex port set exposed by `rtl/cores/socratic_ibex/rtl/socratic_ibex_wrapper.sv`.

Minimum adapter responsibilities:

- reset / clock hookup
- boot address and hart ID
- interrupt mapping
- debug request
- instruction and data bus translation

## First FPGA Milestone

The first practical target should be "single-hart Ibex bring-up with UART and JTAG debug".

### Required blocks

- Ibex core wrapper
- core adapter
- simple memory map
- BRAM-backed main memory
- APB UART peripheral
- `riscv-dbg` debug transport and debug module
- board wrapper

### Minimum memory map

Suggested first map:

- ROM or boot region at reset vector
- RAM / BRAM for program and data
- UART APB window
- debug APB or debug memory window

Exact addresses can remain configurable, but they should be stable enough for OpenOCD/GDB scripts and bare-metal examples.

## Debug Strategy

Follow the split used successfully in the reference Ara FPGA flow:

- external JTAG transport via `dmi_jtag`
- `dm_top` from `riscv-dbg`
- one debug request line into the core
- SBA access into the SoC address space
- optional debug memory window if needed by the selected debug topology

This repo already depends on `riscv-dbg`, so the debug path should be based on that package rather than inventing a new one.

## UART Strategy

Use the standalone `pulp-platform/apb_uart` dependency.

Reasons:

- it is already packaged for Bender
- it is independent of CVA6-specific FPGA trees
- it matches the APB-centric bring-up style needed here

`apb_uart` pulls in these extra dependencies through its own Bender manifest:

- `apb`
- `obi`
- `obi_peripherals`
- `register_interface`

## Proposed Repository Layout

Suggested additions:

- `rtl/platform/fpga/`
- `rtl/platform/fpga/soc_fpga.sv`
- `rtl/platform/fpga/debug/`
- `rtl/platform/fpga/boards/axku5/`
- `rtl/platform/fpga/scripts/openocd.cfg`
- `rtl/platform/fpga/scripts/load_elf.sh`
- `rtl/platform/fpga/scripts/run_elf.sh`

Possible future additions:

- `cfg/boards/<board>.yaml`
- `cfg/cores/<core>.yaml`
- generator support for selecting board/core combinations

## Build Flow Recommendation

Keep the current simulation flow intact, and add a separate FPGA flow.

Suggested Make targets:

- `make fpga-flist BOARD=<board> CORE=<core>`
- `make fpga-bit BOARD=<board> CORE=<core>`
- `make openocd BOARD=<board>`
- `make load-elf ELF=<path>`

The Tcl build scripts should consume a generated flist and a board-local XDC, similar to the structure used in the reference Ara flow.

## Immediate Next Implementation Steps

1. Add the standalone UART dependency path and verify checkout/symlink behavior.
2. Create the FPGA directory structure.
3. Add an initial board wrapper for one board.
4. Add an Ibex socket adapter.
5. Add a minimal FPGA SoC assembly with BRAM, UART, and debug.
6. Add OpenOCD/GDB helper scripts parameterized for this repo.
7. Add one tiny bare-metal test that prints over UART and can also be loaded via GDB.
