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
- `pulp-platform/obi`

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
