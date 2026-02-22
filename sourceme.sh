#!/usr/bin/env bash

set -euo pipefail

PYTHON="${PYTHON:-${PYEXE:-python3.12}}"
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${THIS_DIR}/.venv"
PYREQS_FILE="requirements.txt"
VENV_REQS="${THIS_DIR}/${PYREQS_FILE}"
VENV_NAME="$(basename "${THIS_DIR}")"
export VENV_ACT="${VENV_DIR}/bin/activate"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo " - Note: run 'source ./sourceme.sh' for persistent shell activation"
fi

create_venv() {
  if ! command -v "${PYTHON}" >/dev/null 2>&1; then
    echo " - Python executable '${PYTHON}' not found"
    return 1
  fi
  "${PYTHON}" -m venv --prompt "${VENV_NAME}" "${VENV_DIR}"
  # shellcheck disable=SC1090
  . "${VENV_ACT}"
  python -m pip install --upgrade pip
  pip install wheel
  if [[ -f "${VENV_REQS}" ]]; then
    echo " - Installing packages listed in ${PYREQS_FILE}"
    pip install -r "${VENV_REQS}"
  else
    echo " - ${PYREQS_FILE} not found...skipping"
  fi
}

venv_setup() {
  if [[ -n "${VIRTUAL_ENV:-}" && "${VIRTUAL_ENV}" == "${VENV_DIR}" ]]; then
    echo " - Project virtual environment already active"
    return
  fi

  if [[ ! -d "${VENV_DIR}" ]]; then
    echo " - Python virtual environment NOT found"
    echo "  -> Setting up Python virtual environment"
    create_venv
  else
    if [[ -n "${VIRTUAL_ENV:-}" && "${VIRTUAL_ENV}" != "${VENV_DIR}" ]]; then
      echo " - Another virtual environment is active (${VIRTUAL_ENV})"
      echo "  -> Switching to project virtual environment"
    else
      echo " - Python virtual environment found"
      echo "  -> Activating Python virtual environment"
    fi
    # shellcheck disable=SC1090
    . "${VENV_ACT}"
  fi
}

venv_setup
cd "${THIS_DIR}"
