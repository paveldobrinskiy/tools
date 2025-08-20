#!/usr/bin/env bash

# Author: pdobrinskiy@cornelisnetworks.com v1
# Print stats from all opacaptures found in folder
# One-shot Linux network statistics collector (works on a copied filesystem snapshot)
# Usage: ./netstats_scan.sh /path/to/root-folder-containing-sys
# It will recurse, find */sys/class/net, and print stats for each interface found.
# example
: '
pdobrinskiy_cornelis@COR-CHE-LT-456 tools % ./netstats_scan.sh ../../Documents/60006823
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 adm RX=0.007TB TX=0.082TB RX_pkts=27868836 TX_pkts=57824992 AvgRxPkt=266B AvgTxPkt=1417B rx_errs=0 tx_errs=0 rx_drop=3355228 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 eno2 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 ens802f0 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 ens802f1 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 ens802f2 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 ens802f3 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 ib0 RX=0.000TB TX=0.000TB RX_pkts=4745208 TX_pkts=15222 AvgRxPkt=56B AvgTxPkt=69B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-bfm1/20250819-opacapture-bfm1/tmp/capture1914591 lo RX=0.000TB TX=0.000TB RX_pkts=6 TX_pkts=6 AvgRxPkt=89B AvgTxPkt=89B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 enp0s20f0u1u6 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ens4f0 RX=0.065TB TX=0.040TB RX_pkts=404759352 TX_pkts=178098973 AvgRxPkt=160B AvgTxPkt=225B rx_errs=0 tx_errs=0 rx_drop=952173 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ens4f1 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ens4f2 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ens4f3 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ib0 RX=3271.373TB TX=1584.109TB RX_pkts=1618693885518 TX_pkts=912047351907 AvgRxPkt=2020B AvgTxPkt=1736B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ib1 RX=704.636TB TX=0.004TB RX_pkts=401697672119 TX_pkts=74049647 AvgRxPkt=1754B AvgTxPkt=60B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=1073
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 ib2 RX=875.300TB TX=3206.624TB RX_pkts=510583546205 TX_pkts=1618734016413 AvgRxPkt=1714B AvgTxPkt=1980B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=13091
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 lo RX=0.000TB TX=0.000TB RX_pkts=555303 TX_pkts=555303 AvgRxPkt=356B AvgTxPkt=356B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
20250819-opacapture-blnet1/20250819-opacapture-blnet1/tmp/capture2646905 usr RX=0.035TB TX=0.038TB RX_pkts=284700923 TX_pkts=173384498 AvgRxPkt=121B AvgTxPkt=219B rx_errs=0 tx_errs=0 rx_drop=76741 tx_drop=0
opacapture_bcn1311/20250819-opacapture-bcn1311/tmp/capture492343 eno1 RX=0.003TB TX=0.000TB RX_pkts=6450121 TX_pkts=932026 AvgRxPkt=486B AvgTxPkt=167B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
opacapture_bcn1311/20250819-opacapture-bcn1311/tmp/capture492343 ib0 RX=0.278TB TX=3.059TB RX_pkts=198335467 TX_pkts=1510371880 AvgRxPkt=1401B AvgTxPkt=2025B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
opacapture_bcn1311/20250819-opacapture-bcn1311/tmp/capture492343 lo RX=0.001TB TX=0.001TB RX_pkts=702947 TX_pkts=702947 AvgRxPkt=1632B AvgTxPkt=1632B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
opacapture_bcn1311/20250819-opacapture-bcn1311/tmp/capture492343 usr RX=0.000TB TX=0.000TB RX_pkts=4566063 TX_pkts=418658 AvgRxPkt=77B AvgTxPkt=283B rx_errs=0 tx_errs=0 rx_drop=3759 tx_drop=0
pdobrinskiy_cornelis@COR-CHE-LT-456 tools % 
'

set -euo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  echo "Usage: $0 /path/to/root-folder"
  exit 1
fi

if [[ ! -d "$ROOT" ]]; then
  echo "Error: '$ROOT' is not a directory"
  exit 1
fi


# Find all sys/class/net directories within the provided root
mapfile -t NET_DIRS < <(find "$ROOT" -type d -path '*/sys/class/net' 2>/dev/null | sort)

if [[ ${#NET_DIRS[@]} -eq 0 ]]; then
  echo "No 'sys/class/net' directories found under: $ROOT"
  exit 0
fi

# Helper: read a stat file or echo 0 if missing/non-numeric
read_stat() {
  local path="$1"
  if [[ -f "$path" ]]; then
    local v
    v="$(tr -d '[:space:]' < "$path" 2>/dev/null || true)"
    [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 0
  else
    echo 0
  fi
}

for NETDIR in "${NET_DIRS[@]}"; do
  for IFACE_DIR in "$NETDIR"/*; do
    [[ -d "$IFACE_DIR/statistics" ]] || continue
    IFACE_NAME="$(basename "$IFACE_DIR")"

    RX_BYTES="$(read_stat "$IFACE_DIR/statistics/rx_bytes")"
    TX_BYTES="$(read_stat "$IFACE_DIR/statistics/tx_bytes")"
    RX_PKTS="$(read_stat "$IFACE_DIR/statistics/rx_packets")"
    TX_PKTS="$(read_stat "$IFACE_DIR/statistics/tx_packets")"
    RX_ERRS="$(read_stat "$IFACE_DIR/statistics/rx_errors")"
    TX_ERRS="$(read_stat "$IFACE_DIR/statistics/tx_errors")"
    RX_DROP="$(read_stat "$IFACE_DIR/statistics/rx_dropped")"
    TX_DROP="$(read_stat "$IFACE_DIR/statistics/tx_dropped")"

    RX_TB="$(awk -v b="$RX_BYTES" 'BEGIN{printf "%.3f", (b/1e12)}')"
    TX_TB="$(awk -v b="$TX_BYTES" 'BEGIN{printf "%.3f", (b/1e12)}')"

    if (( RX_PKTS > 0 )); then
      AVG_RX=$(( RX_BYTES / RX_PKTS ))
    else
      AVG_RX=0
    fi
    if (( TX_PKTS > 0 )); then
      AVG_TX=$(( TX_BYTES / TX_PKTS ))
    else
      AVG_TX=0
    fi
    REL_PATH="${NETDIR#$ROOT/}"
    REL_PATH="${REL_PATH%/sys/class/net}"
    echo "$REL_PATH $IFACE_NAME RX=${RX_TB}TB TX=${TX_TB}TB RX_pkts=$RX_PKTS TX_pkts=$TX_PKTS AvgRxPkt=${AVG_RX}B AvgTxPkt=${AVG_TX}B rx_errs=$RX_ERRS tx_errs=$TX_ERRS rx_drop=$RX_DROP tx_drop=$TX_DROP"
  done
done