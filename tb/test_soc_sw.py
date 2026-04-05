import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


def _get_env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return int(value, 0)


def _decode_expected() -> str:
    expected = os.getenv("SOCRATIC_EXPECT", "")
    return expected.encode("utf-8").decode("unicode_escape")


@cocotb.test()
async def run_soc_software(dut):
    expected = _decode_expected()
    timeout_cycles = _get_env_int("SOCRATIC_TIMEOUT_CYCLES", 50000)
    min_chars = _get_env_int("SOCRATIC_MIN_CHARS", 1 if expected == "" else len(expected))

    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1

    captured = []
    last_reported = 0

    for cycle in range(timeout_cycles):
        await RisingEdge(dut.clk_i)
        if int(dut.sim_print_valid.value):
            char = chr(int(dut.sim_print_data.value) & 0xFF)
            captured.append(char)
            current = "".join(captured)
            if len(current) > last_reported:
                last_reported = len(current)
                dut._log.info("SW: %r", current)
            if expected and expected in current:
                return

    current = "".join(captured)
    if expected:
        raise AssertionError(
            f"Timed out waiting for expected output {expected!r}. Captured: {current!r}"
        )
    if len(current) < min_chars:
        raise AssertionError(
            f"Timed out waiting for software output. Captured: {current!r}"
        )
