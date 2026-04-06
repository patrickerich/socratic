import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


def _get_env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return int(value, 0)

@cocotb.test()
async def run_soc_software(dut):
    timeout_cycles = _get_env_int("SOCRATIC_TIMEOUT_CYCLES", 1000000)

    cocotb.start_soon(Clock(dut.clk_i, 20, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1

    captured = []
    line_buffer = []

    for cycle in range(timeout_cycles):
        await RisingEdge(dut.clk_i)
        if int(dut.sim_print_valid.value):
            char = chr(int(dut.sim_print_data.value) & 0xFF)
            captured.append(char)
            line_buffer.append(char)
            current = "".join(captured)
            if char == "\n":
                dut._log.info("SW: %s", "".join(line_buffer).rstrip("\n"))
                line_buffer.clear()
        else:
            current = "".join(captured)

        if int(dut.sim_status_valid.value):
            status_code = int(dut.sim_status_code.value)
            status_pass = bool(int(dut.sim_status_pass.value))
            if line_buffer:
                dut._log.info("SW: %s", "".join(line_buffer))
                line_buffer.clear()
            if status_pass:
                dut._log.info("SW reported PASS with status 0x%08x", status_code)
                return
            raise AssertionError(
                f"Software reported FAIL with status 0x{status_code:08x}. "
                f"Captured: {current!r}"
            )

    current = "".join(captured)
    if line_buffer:
        dut._log.info("SW: %s", "".join(line_buffer))
    raise AssertionError(
        "Timed out waiting for software to report PASS/FAIL via sim_ctrl. "
        f"Captured: {current!r}"
    )
