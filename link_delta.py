#!/usr/bin/env python3

# OPA, OPX, ETH, IB traffic counter
# by default it looks for MLX5
# Pavel Dobrinskiy pdobrinskiy@cornelisnetworks.com
# OPX_PORT_BLOCK, IB_DEVICE, IB_LID, ETH_IFACE could be set from env variables
# not testted in mixed OPA100, CN5000
# v3 cn5000 or opa100 compatible
#example
#[root@opahsx174 ~]# python link_delta.py 
#OPA100 Port0,1 RX: current=0.0109 GiB, delta=0.0000 GiB
#OPA100 Port0,1 TX: current=0.2391 GiB, delta=0.0000 GiB
#OPA100 Port1,1 RX: current=0.0050 GiB, delta=0.0000 GiB
#OPA100 Port1,1 TX: current=0.0127 GiB, delta=0.0000 GiB
#IB: mlx5_0 port 1 not available; skipping IB (ibwarn: [400340] mad_rpc_open_port: can't open UMAD port (mlx5_0:1)).
#ETH eth0 RX: current=20.0840 GiB, delta=2.1044 GiB
#ETH eth0 TX: current=1.1474 GiB, delta=0.0834 GiB
#
# data is saved to ~/.link_counters.json
#or
#[root@cn5kGenoa163 ~]# python3 link_delta.py
#CN5000-100Gb Port0,2 RX: current=648.5699 GiB, delta=0.1608 GiB
#CN5000-100Gb Port0,2 TX: current=1754.3684 GiB, delta=322.5247 GiB
#ETH eth0 RX: current=0.3428 GiB, delta=0.0000 GiB
#ETH eth0 TX: current=0.0296 GiB, delta=0.0000 GiB

import json, os, re, subprocess, sys
from pathlib import Path

STATE_FILE = Path.home() / ".link_counters.json"
UNITS = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3}

# ---- Config via env (with defaults) ----
OPX_PORT_BLOCK = os.environ.get("OPX_PORT_BLOCK", "Port0,2:")
IB_DEVICE = os.environ.get("IB_DEVICE", "mlx5_0")
try:
    IB_PORT = int(os.environ.get("IB_PORT", "1"))
except ValueError:
    IB_PORT = 1
try:
    IB_LID = int(os.environ.get("IB_LID", "20"))
except ValueError:
    IB_LID = 20
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

def run(cmd):
    """Run a command, return stdout text. On failure, raise CalledProcessError."""
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        # bubble up so caller can decide to skip gracefully
        raise

# ---------- OPX / OPA100 parsing ----------
def parse_opx_rx_bytes(text, port_block):
    """Legacy OPX: parse RxWords within a specific PortX,Y: block; return bytes."""
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
    return words * 4  # 1 word = 4 bytes

def parse_opx_like(text, port_blocks):
    """Try a list of hfi1stats block headers and return (label, bytes)."""
    for port_block in port_blocks:
        start = text.find(port_block)
        if start < 0:
            continue
        rest = text[start:]
        end = rest.find("\nPort")
        block = rest if end < 0 else rest[:end]
        m = re.search(r"RxWords\s+(\d+)\s*([KMG]?)\b", block)
        if not m:
            continue
        val = int(m.group(1))
        suffix = m.group(2) or ""
        words = val * UNITS[suffix]
        label = port_block.strip(":")
        return label, words * 4  # words are 4 bytes
    raise RuntimeError(f"Could not find any of {', '.join(port_blocks)} in hfi1stats output.")

# ---------- IB helpers ----------


def parse_opa_ports(text, port_blocks):
    # Return dict {label: (rx_bytes, tx_bytes)} for each port block found.
    # Parses RxWords/TxWords with optional K/M/G suffixes and converts to bytes
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
    # Try a list of hfi1stats block headers and return (label, rx_bytes, tx_bytes).
    # Parses RxWords and TxWords (with optional K/M/G suffix, base 1024)
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
        # Default to 0 if one of them is missing
        rx_val = int(rxm.group(1)) if rxm else 0
        rx_suf = (rxm.group(2) if rxm else "") or ""
        tx_val = int(txm.group(1)) if txm else 0
        tx_suf = (txm.group(2) if txm else "") or ""
        rx_words = rx_val * UNITS[rx_suf]
        tx_words = tx_val * UNITS[tx_suf]
        label = port_block.strip(":")
        return label, rx_words * 4, tx_words * 4
    raise RuntimeError(f"Could not find any of {', '.join(port_blocks)} in hfi1stats output.")

def try_perfquery(device, port, lid):
    """Return output string from perfquery or None if unavailable/not permitted."""
    cmd = ["perfquery", "-C", device, "-P", str(port), "-x", "-l", str(lid), "-a"]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except FileNotFoundError:
        print("IB: perfquery not installed; skipping IB.", file=sys.stderr)
        return None
    except subprocess.CalledProcessError as e:
        # Noisy warnings are common on non-mlx systems; suppress full text and just note skip
        first_line = (e.output or "").splitlines()[0] if e.output else str(e)
        print(f"IB: {device} port {port} not available; skipping IB ({first_line}).", file=sys.stderr)
        return None

def parse_ib_rcv_bytes(text):
    """Parse PortRcvData counts (16B units) and return bytes."""
    m = re.search(r"PortRcvData:\s*\.{2,}\s*(\d+)", text)
    if not m:
        raise RuntimeError("Could not parse PortRcvData from perfquery output.")
    counts = int(m.group(1))
    return counts * 4  # counts are 4 DWORDs = 16 bytes; multiply by 4 to get bytes? (match prior script)
    # NOTE: Original script used *4. If you want exact 16B units, change to counts * 16.

# ---------- ETH helpers ----------
def get_eth_bytes(iface="eth0"):
    """Return (rx_bytes, tx_bytes) from sysfs for a given interface."""
    base = Path(f"/sys/class/net/{iface}/statistics")
    try:
        rx = int((base / "rx_bytes").read_text().strip())
        tx = int((base / "tx_bytes").read_text().strip())
    except FileNotFoundError:
        raise RuntimeError(f"Could not read statistics for interface '{iface}'.")
    return rx, tx

# ---------- Printing ----------
def print_result(label, current_bytes, prev_bytes):
    if prev_bytes is None or current_bytes < prev_bytes:
        print(f"{label}: current={to_gib(current_bytes):.4f} GiB, delta=N/A")
    else:
        delta = current_bytes - prev_bytes
        print(f"{label}: current={to_gib(current_bytes):.4f} GiB, delta={to_gib(delta):.4f} GiB")

def main():
    state = load_state()

    # --- OPX / OPA100 (report Port0,1 and Port1,1 separately if present) ---
    try:
        opx_out = run(["hfi1stats"])
        # Prefer explicit OPA100 ports; if not found, fall back to configured OPX block
        ports = parse_opa_ports(opx_out, ["Port0,1:", "Port1,1:"])
        if not ports:
            # legacy OPX fallback: single block, RX-only or duplex if available
            try:
                label, rx_bytes, tx_bytes = parse_opx_like_duplex(opx_out, [OPX_PORT_BLOCK])
                ports = {label: (rx_bytes, tx_bytes)}
            except Exception:
                # last resort: rx only
                label, rx_bytes = OPX_PORT_BLOCK.strip(":"), parse_opx_rx_bytes(opx_out, OPX_PORT_BLOCK)
                ports = {label: (rx_bytes, 0)}
        for label, (rx_bytes, tx_bytes) in ports.items():
            # Label as OPA100 if matching the usual PortX,1 pattern; else OPX
            flavor = "OPA100" if label in ("Port0,1", "Port1,1") else "OPX"
            rx_key = f"opx:{flavor}:{label}:rx"
            tx_key = f"opx:{flavor}:{label}:tx"
            print_result(f"{flavor} {label} RX", rx_bytes, state.get(rx_key))
            print_result(f"{flavor} {label} TX", tx_bytes, state.get(tx_key))
            state[rx_key] = rx_bytes
            state[tx_key] = tx_bytes
    except FileNotFoundError:
        print("OPX/OPA100: hfi1stats not found; skipping.", file=sys.stderr)
    except Exception as e:
        print(f"OPX/OPA100: {e}", file=sys.stderr)
    # --- IB (graceful skip if unavailable) ---
    ib_out = try_perfquery(IB_DEVICE, IB_PORT, IB_LID)
    if ib_out:
        try:
            ib_bytes = parse_ib_rcv_bytes(ib_out)
            ib_key = f"ib:{IB_DEVICE}:P{IB_PORT}:LID{IB_LID}"
            ib_prev = state.get(ib_key)
            print_result(f"IB {IB_DEVICE} port {IB_PORT} lid {IB_LID}", ib_bytes, ib_prev)
            state[ib_key] = ib_bytes
        except Exception as e:
            print(f"IB parse error: {e}", file=sys.stderr)

    # --- ETH (RX and TX) ---
    try:
        eth_rx, eth_tx = get_eth_bytes(ETH_IFACE)
        eth_rx_key = f"eth:{ETH_IFACE}:rx"
        eth_tx_key = f"eth:{ETH_IFACE}:tx"
        print_result(f"ETH {ETH_IFACE} RX", eth_rx, state.get(eth_rx_key))
        print_result(f"ETH {ETH_IFACE} TX", eth_tx, state.get(eth_tx_key))
        state[eth_rx_key] = eth_rx
        state[eth_tx_key] = eth_tx
    except Exception as e:
        print(f"ETH {ETH_IFACE}: {e}", file=sys.stderr)

    save_state(state)

if __name__ == "__main__":
    main()
