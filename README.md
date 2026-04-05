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
make py-deps

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

After programming the FPGA, start OpenOCD with:

```bash
openocd -f rtl/platform/fpga/scripts/openocd.cfg
```

Load and run an ELF over JTAG/GDB with:

```bash
rtl/platform/fpga/scripts/load_elf.sh path/to/program.elf
```

The helper script sets the PC to `0x80000000`, which matches the initial BRAM-backed Ibex bring-up target.

## CI

GitHub Actions workflow `.github/workflows/smoke.yml` runs the smoke test on every push to `main` (including merges).
