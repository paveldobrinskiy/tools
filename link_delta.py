#!/usr/bin/env python3
import json, os, re, subprocess, sys
from pathlib import Path

STATE_FILE = Path.home() / ".link_counters.json"
UNITS = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3}

# ---- Config defaults ----
OPX_PORT_BLOCK = "Port0,2:"
IB_DEVICE = "mlx5_0"
IB_PORT = 1
IB_LID = 20

def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            return {}
    return {}

def save_state(state):
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True))

def to_gib(bytes_val):
    return bytes_val / (1024**3)

def run(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running {' '.join(cmd)}:\n{e.output}", file=sys.stderr)
        sys.exit(1)

def parse_ib_rcv_bytes(text):
    m = re.search(r"PortRcvData:\s*\.{2,}\s*(\d+)", text)
    if not m:
        raise RuntimeError("Could not parse PortRcvData from perfquery output.")
    counts = int(m.group(1))
    return counts * 4  # IB: 1 count = 16 bytes

def parse_opx_rx_bytes(text, port_block):
    start = text.find(port_block)
    if start < 0:
        raise RuntimeError(f"Could not find OPX port block header '{port_block}'.")
    rest = text[start:]
    end = rest.find("\nPort")
    block = rest if end < 0 else rest[:end]
    m = re.search(r"RxWords\s+(\d+)\s*([KMG]?)\b", block)
    if not m:
        raise RuntimeError("Could not parse RxWords from hfi1stats output.")
    val = int(m.group(1))
    suffix = m.group(2) or ""
    words = val * UNITS[suffix]
    return words * 4  # OPX: 1 word = 4 bytes

def print_result(label, current_bytes, prev_bytes):
    if prev_bytes is None or current_bytes < prev_bytes:
        print(f"{label}: current={to_gib(current_bytes):.4f} GiB, delta=N/A")
    else:
        delta = current_bytes - prev_bytes
        print(f"{label}: current={to_gib(current_bytes):.4f} GiB, delta={to_gib(delta):.4f} GiB")

def main():
    state = load_state()

    # --- OPX ---
    opx_out = run(["hfi1stats"])
    opx_bytes = parse_opx_rx_bytes(opx_out, OPX_PORT_BLOCK)
    opx_key = f"opx:{OPX_PORT_BLOCK}"
    opx_prev = state.get(opx_key)
    print_result(f"OPX {OPX_PORT_BLOCK.strip(':')}", opx_bytes, opx_prev)
    state[opx_key] = opx_bytes

    # --- IB ---
    ib_out = run(["perfquery", "-C", IB_DEVICE, "-P", str(IB_PORT), "-x", "-l", str(IB_LID), "-a"])
    ib_bytes = parse_ib_rcv_bytes(ib_out)
    ib_key = f"ib:{IB_DEVICE}:P{IB_PORT}:LID{IB_LID}"
    ib_prev = state.get(ib_key)
    print_result(f"IB {IB_DEVICE} port {IB_PORT} lid {IB_LID}", ib_bytes, ib_prev)
    state[ib_key] = ib_bytes

    save_state(state)

if __name__ == "__main__":
    main()
