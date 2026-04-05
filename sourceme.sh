#!/usr/bin/env bash
# sourceme.sh — activate the project Python virtual environment
# Usage: source ./sourceme.sh
#        PYTHON=python3.13 source ./sourceme.sh

# Warn if executed directly instead of sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo " - Note: run 'source ./sourceme.sh' for persistent shell activation"
  exit 1
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
_sm_python="${PYTHON:-${PYEXE:-python3.13}}"
_sm_this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_sm_venv_dir="${_sm_this_dir}/.venv"
_sm_venv_act="${_sm_venv_dir}/bin/activate"
_sm_venv_name="$(basename "${_sm_this_dir}")"
_sm_reqs="${_sm_this_dir}/requirements.txt"

export VENV_ACT="${_sm_venv_act}"
export SOCRATIC_TOOLCHAIN="${SOCRATIC_TOOLCHAIN:-ibex}"
export SOCRATIC_IBEX_TOOLCHAIN="${SOCRATIC_IBEX_TOOLCHAIN:-/opt/lowrisc/lowrisc-toolchain-rv32imcb-x86_64-20250303-1}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_sm_info()  { echo " - $*"; }
_sm_arrow() { echo "  -> $*"; }
_sm_error() { echo " - ERROR: $*" >&2; }
_sm_prepend_path_unique() {
  if [[ -n "${PATH:-}" ]]; then
    export PATH="$1:$(sed -r "s,(:$1$)|($1:),,g" <<< "$PATH")"
  else
    export PATH="$1"
  fi
}

_sm_create_venv() {
  if ! command -v "${_sm_python}" >/dev/null 2>&1; then
    _sm_error "Python executable '${_sm_python}' not found"
    return 1
  fi

  _sm_arrow "Creating virtual environment with ${_sm_python}"
  "${_sm_python}" -m venv --prompt "${_sm_venv_name}" "${_sm_venv_dir}" || return 1

  # shellcheck disable=SC1090
  . "${_sm_venv_act}" || return 1

  _sm_arrow "Upgrading pip"
  python -m pip install --upgrade pip --quiet || return 1
  pip install wheel --quiet || return 1

  if [[ -f "${_sm_reqs}" ]]; then
    _sm_arrow "Installing packages from requirements.txt"
    pip install -r "${_sm_reqs}" || return 1
  else
    _sm_arrow "requirements.txt not found, skipping package install"
  fi
}

_sm_activate_venv() {
  # Already in the right venv — nothing to do
  if [[ -n "${VIRTUAL_ENV:-}" && "${VIRTUAL_ENV}" == "${_sm_venv_dir}" ]]; then
    _sm_info "Project virtual environment already active"
    return 0
  fi

  # Warn if switching away from another active venv
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    _sm_info "Switching from active environment: ${VIRTUAL_ENV}"
  fi

  if [[ ! -d "${_sm_venv_dir}" ]]; then
    _sm_info "Virtual environment not found — creating"
    _sm_create_venv || return 1
  else
    _sm_info "Virtual environment found — activating"
    # shellcheck disable=SC1090
    . "${_sm_venv_act}" || return 1
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
_sm_activate_venv || { _sm_error "Failed to activate virtual environment"; return 1; }
cd "${_sm_this_dir}" || return 1

use_ibex() {
  export RISCV="${SOCRATIC_IBEX_TOOLCHAIN}"
  _sm_prepend_path_unique "${RISCV}/bin"
  if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    _sm_info "Ibex RISC-V toolchain active: ${RISCV}"
  else
    _sm_info "Ibex RISC-V toolchain path configured, but riscv32-unknown-elf-gcc was not found under ${RISCV}/bin"
  fi
}

use_toolchain() {
  case "$1" in
    ibex|"")
      use_ibex
      ;;
    *)
      _sm_error "Unknown toolchain '$1'. Available: ibex"
      return 1
      ;;
  esac
}

use_toolchain "${SOCRATIC_TOOLCHAIN}" || return 1

# Clean up helper functions and private variables from the shell namespace
unset -f _sm_create_venv _sm_activate_venv _sm_info _sm_arrow _sm_error _sm_prepend_path_unique use_ibex use_toolchain
unset _sm_python _sm_this_dir _sm_venv_dir _sm_venv_act _sm_venv_name _sm_reqs
