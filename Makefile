SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

BENDER_VERSION ?= 0.28.1
PYTHON ?= python3.12

TOOLS_DIR := $(CURDIR)/bin/.tools
BENDER_DIR := $(TOOLS_DIR)/bender-v$(BENDER_VERSION)
BENDER_BIN := $(BENDER_DIR)/bender
BENDER := $(TOOLS_DIR)/bender

VENV_PY := $(CURDIR)/.venv/bin/python
VENV_PIP := $(CURDIR)/.venv/bin/pip

.PHONY: help venv py-deps gen smoke bender deps flist clean

help:
	@echo "Targets:"
	@echo "  venv      - create/activate local python environment via sourceme.sh"
	@echo "  py-deps   - install pinned python requirements"
	@echo "  bender    - fetch pinned bender binary into bin/.tools/"
	@echo "  deps      - run bender update + checkout"
	@echo "  gen       - generate RTL artifacts into gen/rtl/"
	@echo "  flist     - generate Bender flist at gen/flist.f"
	@echo "  smoke     - run FuseSoC cocotb+Verilator smoke target"
	@echo "  clean     - remove local simulation outputs"

$(VENV_PY):
	@PYTHON="$(PYTHON)" source ./sourceme.sh >/dev/null

venv: $(VENV_PY)

py-deps: venv
	@$(VENV_PIP) install -r requirements.txt

bender:
	@mkdir -p "$(TOOLS_DIR)"
	@if [ -x "$(BENDER_BIN)" ]; then \
		ln -sfn "bender-v$(BENDER_VERSION)/bender" "$(BENDER)"; \
		echo "Using pinned bender v$(BENDER_VERSION): $(BENDER_BIN)"; \
		"$(BENDER)" --version; \
	else \
		tmp="$$(mktemp -d)"; \
		api="https://api.github.com/repos/pulp-platform/bender/releases/tags/v$(BENDER_VERSION)"; \
		os="$$(uname -s | tr '[:upper:]' '[:lower:]')"; \
		arch="$$(uname -m | tr '[:upper:]' '[:lower:]')"; \
		case "$$arch" in \
			x86_64|amd64) arch="x86_64" ;; \
			aarch64|arm64) arch="aarch64" ;; \
			*) echo "Unsupported architecture: $$arch"; rm -rf "$$tmp"; exit 1 ;; \
		esac; \
		url="$$( $(PYTHON) -c 'import json,sys,urllib.request; api,osn,arch=sys.argv[1:]; rel=json.load(urllib.request.urlopen(api)); assets=rel.get("assets", []); print(next((a.get("browser_download_url", "") for a in assets if osn in a.get("name", "").lower() and arch in a.get("name", "").lower() and a.get("name", "").lower().endswith((".tar.gz", ".tgz"))), ""))' "$$api" "$$os" "$$arch")"; \
		if [ -z "$$url" ]; then \
			echo "No matching prebuilt bender asset found for $$os/$$arch (v$(BENDER_VERSION))."; \
			echo "Install bender manually and place it at $(BENDER_BIN)."; \
			rm -rf "$$tmp"; \
			exit 1; \
		fi; \
		echo "Downloading $$url"; \
		curl -fsSL "$$url" -o "$$tmp/bender.tgz"; \
		mkdir -p "$$tmp/unpack" "$(BENDER_DIR)"; \
		tar -xzf "$$tmp/bender.tgz" -C "$$tmp/unpack"; \
		bin_path="$$(find "$$tmp/unpack" -type f -name bender | head -n1)"; \
		if [ -z "$$bin_path" ]; then \
			echo "Bender binary not found in downloaded archive."; \
			rm -rf "$$tmp"; \
			exit 1; \
		fi; \
		install -m 755 "$$bin_path" "$(BENDER_BIN)"; \
		ln -sfn "bender-v$(BENDER_VERSION)/bender" "$(BENDER)"; \
		rm -rf "$$tmp"; \
		"$(BENDER)" --version; \
	fi

deps: bender
	@"$(BENDER)" update
	@"$(BENDER)" checkout
	@mkdir -p deps
	@for dep in axi apb obi riscv-dbg common_cells tech_cells_generic common_verification; do \
		path="$$("$(BENDER)" path "$$dep" 2>/dev/null || true)"; \
		if [ -n "$$path" ]; then ln -sfn "$$path" "deps/$$dep"; fi; \
	done

gen: venv
	@$(VENV_PY) bin/chassis_gen.py --config cfg/chassis.example.yaml --out gen

flist: deps gen
	@"$(BENDER)" script flist -t all > gen/flist.f
	@echo "Generated gen/flist.f"

smoke: deps gen
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --target smoke --tool verilator socratic:socratic:chassis

clean:
	@rm -rf build tb/sim_build tb/results.xml
