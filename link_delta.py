#!/usr/bin/env python3
#
# CN5000 / OPA100 / OPX / IB / ETH traffic counter
# Pavel Dobrinskiy pdobrinskiy@cornelisnetworks.com
#
# Saves counters to ~/.link_counters.json and prints deltas + avg rates.
#

import json, os, re, subprocess, sys, time
from pathlib import Path

STATE_FILE = Path.home() / ".link_counters.json"
UNITS = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3}
STATE_TS_KEY = "_last_ts"

# ---- Config via env (with defaults) ----
OPX_PORT_BLOCK = os.environ.get("OPX_PORT_BLOCK", "Port0,2:")
IB_DEVICE = os.environ.get("IB_DEVICE", "mlx5_0")
IB_PORT = int(os.environ.get("IB_PORT", "1"))
IB_LID = int(os.environ.get("IB_LID", "20"))
ETH_IFACE = os.environ.get("ETH_IFACE", "eth0")

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

def to_gb_s(bytes_delta, seconds):
    if seconds is None or seconds <= 0:
        return None
    return (bytes_delta / seconds) / (1000**3)  # GB/s (decimal)

def run(cmd):
    return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)

# ---------- Detect CN5000 vs OPA100 ----------
def detect_cn5000():
    try:
        out = run(["opainfo"])
        if "LinkSpeed" in out and "100Gb" in out and "Port0,2" in run(["hfi1stats"]):
            return True
    except Exception:
        pass
    return False

# ---------- OPA / OPX parsing ----------
def parse_opa_ports(text, port_blocks):
    """Return dict {label: (rx_bytes, tx_bytes)} for each port block found."""
    results = {}
    for port_block in port_blocks:
        start = text.find(port_block)
        if start < 0:
            continue
        rest = text[start:]
        end = rest.find("\nPort")
        block = rest if end < 0 else rest[:end]

        rxm = re.search(r"RxWords\s+(\d+)\s*([KMG]?)\b", block)
        txm = re.search(r"TxWords\s+(\d+)\s*([KMG]?)\b", block)

        def words_to_bytes(m):
            if not m:
                return 0
            val = int(m.group(1))
            suf = (m.group(2) or "")
            words = val * UNITS.get(suf, 1)
            return words * 4  # 1 word = 4 bytes

        rx_bytes = words_to_bytes(rxm)
        tx_bytes = words_to_bytes(txm)
        results[port_block.strip(":")] = (rx_bytes, tx_bytes)
    return results

def parse_opx_like_duplex(text, port_blocks):
    for port_block in port_blocks:
        start = text.find(port_block)
        if start < 0:
            continue
        rest = text[start:]
        end = rest.find("\nPort")
        block = rest if end < 0 else rest[:end]
        rxm = re.search(r"RxWords\s+(\d+)\s*([KMG]?)\b", block)
        txm = re.search(r"TxWords\s+(\d+)\s*([KMG]?)\b", block)
        if not rxm and not txm:
            continue
        rx_val = int(rxm.group(1)) if rxm else 0
        rx_suf = (rxm.group(2) if rxm else "") or ""
        tx_val = int(txm.group(1)) if txm else 0
        tx_suf = (txm.group(2) if txm else "") or ""
        rx_words = rx_val * UNITS[rx_suf]
        tx_words = tx_val * UNITS[tx_suf]
        label = port_block.strip(":")
        return label, rx_words * 4, tx_words * 4
    raise RuntimeError(f"Could not find any of {', '.join(port_blocks)} in hfi1stats output.")

# ---------- IB helpers ----------
def try_perfquery(device, port, lid):
    cmd = ["perfquery", "-C", device, "-P", str(port), "-x", "-l", str(lid), "-a"]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except Exception:
        return None

def parse_ib_rcv_bytes(text):
    m = re.search(r"PortRcvData:\s*\.{2,}\s*(\d+)", text)
    if not m:
        raise RuntimeError("Could not parse PortRcvData from perfquery output.")
    counts = int(m.group(1))
    return counts * 4  # matches old script convention

# ---------- ETH helpers ----------
def get_eth_bytes(iface="eth0"):
    base = Path(f"/sys/class/net/{iface}/statistics")
    rx = int((base / "rx_bytes").read_text().strip())
    tx = int((base / "tx_bytes").read_text().strip())
    return rx, tx

# ---------- Printing ----------
def print_result(label, current_bytes, prev_bytes, dt_seconds):
    if prev_bytes is None or current_bytes < prev_bytes:
        # First run or counter wrap/reset
        print(f"{label}: current={to_gib(current_bytes):.4f} GiB, delta=N/A, avg=N/A")
    else:
        delta = current_bytes - prev_bytes
        rate = to_gb_s(delta, dt_seconds)
        rate_str = f"{rate:.3f} GB/s" if rate is not None else "N/A"
        print(f"{label}: current={to_gib(current_bytes):.4f} GiB, "
              f"delta={to_gib(delta):.4f} GiB, avg={rate_str}")

# ---------- MAIN ----------
def main():
    state = load_state()

    now = time.time()
    last_ts = state.get(STATE_TS_KEY)
    dt_seconds = (now - last_ts) if isinstance(last_ts, (int, float)) else None

    is_cn5000 = detect_cn5000()

    # --- OPX / OPA / CN5000 ---
    try:
        opx_out = run(["hfi1stats"])
        if is_cn5000:
            ports = parse_opa_ports(opx_out, ["Port0,2:"])
            flavor = "CN5000-100Gb"
        else:
            ports = parse_opa_ports(opx_out, ["Port0,1:", "Port1,1:"])
            flavor = "OPA100"
            if not ports:
                label, rx_bytes, tx_bytes = parse_opx_like_duplex(opx_out, [OPX_PORT_BLOCK])
                ports = {label: (rx_bytes, tx_bytes)}
                flavor = "OPX"

        for label, (rx_bytes, tx_bytes) in ports.items():
            if rx_bytes == 0 and tx_bytes == 0:
                continue
            rx_key = f"{flavor}:{label}:rx"
            tx_key = f"{flavor}:{label}:tx"
            print_result(f"{flavor} {label} RX", rx_bytes, state.get(rx_key), dt_seconds)
            print_result(f"{flavor} {label} TX", tx_bytes, state.get(tx_key), dt_seconds)
            state[rx_key] = rx_bytes
            state[tx_key] = tx_bytes

    except FileNotFoundError:
        print("hfi1stats not found; skipping.", file=sys.stderr)
    except Exception as e:
        print(f"OPX/OPA100/CN5000: {e}", file=sys.stderr)

    # --- IB ---
    ib_out = try_perfquery(IB_DEVICE, IB_PORT, IB_LID)
    if ib_out:
        try:
            ib_bytes = parse_ib_rcv_bytes(ib_out)
            ib_key = f"ib:{IB_DEVICE}:P{IB_PORT}:LID{IB_LID}"
            print_result(f"IB {IB_DEVICE} port {IB_PORT} lid {IB_LID}",
                         ib_bytes, state.get(ib_key), dt_seconds)
            state[ib_key] = ib_bytes
        except Exception as e:
            print(f"IB parse error: {e}", file=sys.stderr)

    # --- ETH ---
    try:
        eth_rx, eth_tx = get_eth_bytes(ETH_IFACE)
        eth_rx_key = f"eth:{ETH_IFACE}:rx"
        eth_tx_key = f"eth:{ETH_IFACE}:tx"
        print_result(f"ETH {ETH_IFACE} RX", eth_rx, state.get(eth_rx_key), dt_seconds)
        print_result(f"ETH {ETH_IFACE} TX", eth_tx, state.get(eth_tx_key), dt_seconds)
        state[eth_rx_key] = eth_rx
        state[eth_tx_key] = eth_tx
    except Exception as e:
        print(f"ETH {ETH_IFACE}: {e}", file=sys.stderr)

    # Save timestamp for next run and updated counters
    state[STATE_TS_KEY] = now
    save_state(state)

if __name__ == "__main__":
    main()