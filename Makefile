SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

BENDER_VERSION ?= 0.31.0
PYTHON        ?= python3.13

TOOLS_DIR  := $(CURDIR)/bin/.tools
BENDER_DIR := $(TOOLS_DIR)/bender-v$(BENDER_VERSION)
BENDER_BIN := $(BENDER_DIR)/bender
BENDER     := $(TOOLS_DIR)/bender
VENV_PY    := $(CURDIR)/.venv/bin/python

.PHONY: help deps gen flist smoke clean distclean

help:
	@echo "Targets:"
	@echo "  bender    - fetch pinned bender binary into bin/.tools/"
	@echo "  deps      - run bender update + checkout"
	@echo "  gen       - generate RTL artifacts into gen/rtl/"
	@echo "  flist     - generate Bender flist at gen/flist.f"
	@echo "  smoke     - run FuseSoC cocotb+Verilator smoke target"
	@echo "  clean     - remove simulation and generated outputs"
	@echo "  distclean - clean + remove tools and bender dependencies"

# File target — only runs when the binary is missing
$(BENDER_BIN):
	@mkdir -p "$(TOOLS_DIR)"
	@tmp="$$(mktemp -d)"; \
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
	rm -rf "$$tmp"
	@ln -sfn "bender-v$(BENDER_VERSION)/bender" "$(BENDER)"
	@echo "Installed bender $$($(BENDER) --version)"

# Convenience alias
bender: $(BENDER_BIN)

deps: $(BENDER_BIN)
	@"$(BENDER)" update
	@"$(BENDER)" checkout
	@mkdir -p deps
	@for dep in axi apb obi riscv-dbg common_cells tech_cells_generic common_verification; do \
		path="$$("$(BENDER)" path "$$dep" 2>/dev/null || true)"; \
		if [ -n "$$path" ]; then ln -sfn "$$path" "deps/$$dep"; fi; \
	done

gen: deps
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@$(VENV_PY) bin/chassis_gen.py --config cfg/chassis.example.yaml --out gen

flist: gen
	@"$(BENDER)" script flist -t all > gen/flist.f
	@echo "Generated gen/flist.f"

smoke: gen
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --target smoke --tool verilator socratic:socratic:chassis

clean:
	@rm -rf build tb/sim_build tb/results.xml gen deps

distclean: clean
	@rm -rf "$(TOOLS_DIR)" .bender
