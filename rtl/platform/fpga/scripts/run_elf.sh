#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 path/to/program.elf [timeout_seconds]" 1>&2
  exit 1
fi

ELF="$1"
TIMEOUT="${2:-5}"

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

TMPFILE=$(mktemp /tmp/socratic_gdb.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" << EOF
target extended-remote localhost:3333
monitor reset halt
load
set \$pc = 0x80000000
continue
EOF

timeout --foreground --signal=INT "${TIMEOUT}" "$GDB_CMD" "$ELF" -batch -x "$TMPFILE" || {
  exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    echo "Timeout reached after ${TIMEOUT}s"
    exit 0
  fi
  exit "$exit_code"
}
