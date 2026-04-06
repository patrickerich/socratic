#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 path/to/program.elf [additional GDB -ex commands...]" 1>&2
  exit 1
fi

ELF="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
REPO_GDB="$REPO_ROOT/install/riscv-gcc/bin/riscv64-unknown-elf-gdb"

if [ -n "${GDB:-}" ]; then
  GDB_CMD="$GDB"
elif [ -x "$REPO_GDB" ]; then
  GDB_CMD="$REPO_GDB"
elif [ -n "${RISCV:-}" ] && [ -x "${RISCV}/bin/riscv-none-elf-gdb" ]; then
  GDB_CMD="${RISCV}/bin/riscv-none-elf-gdb"
else
  GDB_CMD="riscv64-unknown-elf-gdb"
fi

exec "$GDB_CMD" "$ELF" \
  -ex "target extended-remote localhost:3333" \
  -ex "monitor reset halt" \
  -ex "load" \
  -ex "set \$pc = 0x80000000" \
  -ex "continue" \
  "$@"
