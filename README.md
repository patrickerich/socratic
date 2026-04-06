# socratic

Socratic is a starter chassis for evaluating swappable RISC-V cores and accelerators with an ASIC-aware architecture.

## Project status

This repository is in a **very early state of development**. It currently provides a minimal scaffold, generation flow, and a smoke-testable top-level stub to bootstrap development.

## Scope of this bootstrap

- Keep integration logic in human-authored SystemVerilog modules.
- Use a lightweight Python generator for top-level glue and generated address-map artifacts.
- Start with stable contracts: core/accelerator socket interfaces and shared chassis enums.

## Repository layout

- `rtl/pkg/chassis_pkg.sv` - shared enums and base types.
- `rtl/interfaces/` - core and accelerator socket interface contracts.
- `rtl/pkg/soc_bus_pkg.sv` - centralized PULP bus typedefs (`APB`/`AXI`/`OBI`) used as default typed interfaces.
- `cfg/chassis.example.yaml` - sample platform configuration.
- `bin/chassis_gen.py` - YAML-to-SystemVerilog glue generator.
- `gen/` - output directory for generated artifacts (e.g. `gen/rtl/*.sv`).
- `socratic.core` - FuseSoC core/target definitions.

## Get started

```bash
# 1) Create/use the project virtual environment and install pinned Python deps
source sourceme.sh

# 2) (Optional, when using external HDL deps) bootstrap pinned bender and fetch deps
make bender
make deps
make flist

# 3) Generate RTL artifacts from the example config
make gen

# 4) Run the FuseSoC + Verilator smoke simulation
make smoke
```

For interactive development shells, activate the project environment with:

```bash
source sourceme.sh
```

`source sourceme.sh` also prepends the default Ibex lowRISC toolchain path if it exists:

- default toolchain root: `/opt/lowrisc/lowrisc-toolchain-rv32imcb-x86_64-20250303-1`
- selected via `SOCRATIC_TOOLCHAIN=ibex`
- override the toolchain root with `SOCRATIC_IBEX_TOOLCHAIN=/path/to/toolchain`

## Dependency management

Socratic uses **Bender** for RTL/IP dependency management (preferred over git submodules).

- Single manifest (`Bender.yml`) keeps dependency intent explicit and reviewable.
- Reproducible dependency resolution via Bender lock/checkout workflow.
- Better fit for PULP-style SystemVerilog ecosystems than nested submodule trees.

Typical flow:

```bash
make bender
make deps
make flist
```

Reproducibility notes:

- `Makefile` pins `BENDER_VERSION` and installs that binary into `bin/.tools/`.
- `Makefile` and `sourceme.sh` share the same Python selector (`PYTHON`, default `python3.12`).
- A stable symlink `bin/.tools/bender` is used by `make deps`/`make flist`.
- `make deps` also creates stable local symlinks under `deps/` to checked-out packages in `.bender/`.
- Bender checkouts and caches are local-only (`.bender*/`, `deps/`) and gitignored.

Current limitation to revisit later:

- `socratic.core` still directly references selected `deps/...` source files for some transient Bender-fetched dependencies.
- A more maintainable long-term packaging split between Bender and FuseSoC still needs to be revisited after the current bring-up work is further along.
- For now this direct-reference approach stays in place because it is the most reliable validated flow in this repository.

### Tool versions used during setup/validation

These are currently observed local tool versions used to validate this repository. They are not all pinned by this repo, so recording them here helps reproducibility:

- Verilator: `5.044`
- GNU Make: `4.4.1`
- System Python used by setup: `3.12.12`
- FuseSoC (from venv/requirements): `2.4.5`

Initial external dependencies in `Bender.yml`:

- `pulp-platform/axi`
- `pulp-platform/riscv-dbg`
- `pulp-platform/apb`
- `pulp-platform/apb_uart`
- `pulp-platform/obi`

The standalone UART dependency is intended to be used for FPGA bring-up, rather than reusing the older UART implementation buried inside CVA6-specific FPGA trees.

Current FPGA bring-up direction:

- first reference target: `socratic_ibex` + `riscv-dbg` + `apb_uart`
- board wrappers should stay separate from the generic SoC/chassis RTL
- see [`docs/fpga_ibex_plan.md`](docs/fpga_ibex_plan.md) for the proposed architecture and first implementation plan

Generated files:

- `gen/rtl/addr_map_pkg.sv`
- `gen/rtl/soc_top_gen.sv`

Hand-authored starter integration:

- `rtl/top/soc_top.sv` - minimal top using typed/parametrizable APB/AXI/OBI request/response structs.
- `tb/smoke_dut.sv` - test harness wrapper for cocotb signal driving.
- `tb/test_smoke.py` - cocotb smoke test module used by FuseSoC (`cocotb_module` target flow).

FuseSoC + cocotb + Verilator smoke run:

```bash
make smoke
```

Generic software simulation run:

```bash
make sim-sw SW_APP=hello_world
```

Example self-check run:

```bash
make sim-sw SW_APP=self_check
```

Alternative pass/fail control:

- use `SIM_TIMEOUT_CYCLES=<n>` to relax or tighten the cycle budget

This uses:

- one generic HDL harness: `tb/ibex_soc_dut.sv`
- one generic cocotb runner: `tb/test_soc_sw.py`
- runtime-selected software images via `SW_APP`
- a generic software-visible sim-control MMIO register for PASS/FAIL reporting

## FPGA bring-up

An initial FPGA-oriented Ibex path is now scaffolded under `rtl/platform/fpga/`.

Current reference target:

- core: `socratic_ibex`
- debug: `riscv-dbg` over external JTAG (`dmi_jtag` + `dm_top`)
- console: `apb_uart`
- board: AXKU5

Generate the FPGA file list:

```bash
make fpga-flist
```

Build the AXKU5 bitstream with Vivado:

```bash
make fpga-bit
```

Software for FPGA bring-up now follows a shared CMake-based bare-metal layout:

- CMake project under `sw/c/`
- shared linker script in `sw/common/link.ld`
- shared startup code in `sw/c/common/crt0.S`
- app-specific directories such as `sw/c/hello_world/`
- test-style apps such as `sw/c/self_check/`

Build the first bare-metal firmware image with:

```bash
make fw-hello
```

This generates:

- `sw/build/hello_world/cmake/hello_world/hello_world`
- `sw/build/hello_world/hello_world.bin`
- `sw/build/hello_world/hello_world.dis`
- `sw/build/hello_world/bank_0.hex` ... `sw/build/hello_world/bank_3.hex`

The `bank_N.hex` files are generated for the current full-interleaving memory layout:

- one 32-bit word per hex line
- bank select = `word_index % NumBanks`

The example is linked for the current FPGA bring-up map:

- boot address: `0x80000000`
- UART base: `0x10000000`
- UART clock assumption: `50 MHz`
- UART baud: `115200`

For simulation, the banked memory subsystem can preload those files by either:

- passing `+MEM_PATH=/abs/path/to/sw/build/hello_world`
- or setting the `soc_top`/`soc_mem_ss` `MemInitPath` parameter

The generic `make sim-sw` target automatically:

- rebuilds the selected app
- passes `+MEM_PATH=<sw/build/<app>>`
- monitors real UART traffic and `sim_ctrl` writes from the TB harness
- treats software PASS/FAIL writes to `sim_ctrl` as the completion signal

For reusable software tests, use the common sim-control helpers in:

- `sw/c/common/sim_ctrl.h`
- `sw/c/common/sim_ctrl.c`

The intended pattern for generic C tests is:

- print debug text with `printf()` if useful
- call `sim_ctrl_pass()` on success
- call `sim_ctrl_fail(<code>)` on failure

The simulation-specific observation lives in the testbench, not in `soc_top`:

- `soc_top` contains only hardware-facing UART/debug/memory integration
- `tb/soc_sw_mon.sv` observes internal software-visible traffic for cocotb
- `tb/test_soc_sw.py` line-buffers UART text and watches the final `sim_ctrl` store

After programming the FPGA, start OpenOCD with:

```bash
openocd -f rtl/platform/fpga/scripts/openocd.cfg
```

Load and run an ELF over JTAG/GDB with:

```bash
make load-hello
```

Run the same image in batch mode with:

```bash
make run-hello
```

The helper scripts set the PC to `0x80000000`, which matches the initial BRAM-backed Ibex bring-up target.

## CI

GitHub Actions workflow `.github/workflows/smoke.yml` runs the smoke test on every push to `main` (including merges).
