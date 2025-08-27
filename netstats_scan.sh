#!/usr/bin/env bash

# Author: pdobrinskiy@cornelisnetworks.com v1
# Print stats from all opacaptures found in folder
# One-shot Linux network statistics collector (works on a copied filesystem snapshot)
# Usage: ./netstats_scan.sh /path/to/root-folder-containing-sys
# It will recurse, find */sys/class/net, and print stats for each interface found.
# example
: '
2025-08-25-opacapture-blnet4/tmp/capture2490689 ens4f1 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ens4f2 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ens4f3 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ib0(mlx5_0) RX=733.703TB TX=559.210TB RX_pkts=364900416481 TX_pkts=319341941192 AvgRxPkt=2010B AvgTxPkt=1751B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ib1(hfi1_0) RX=306.103TB TX=0.001TB RX_pkts=175733034532 TX_pkts=24254448 AvgRxPkt=1741B AvgTxPkt=60B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=1495
2025-08-25-opacapture-blnet4/tmp/capture2490689 ib2(hfi1_1) RX=251.653TB TX=719.110TB RX_pkts=143691312929 TX_pkts=364949688485 AvgRxPkt=1751B AvgTxPkt=1970B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=13032
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

     # Try to detect underlying infiniband device name
     DEV_NAME=""
     IB_DEV_PATH="$IFACE_DIR/device/infiniband"
     if [[ -d "$IB_DEV_PATH" ]]; then
       # usually only one subdir like mlx5_0 or hfi1_0
       DEV_NAME="$(ls "$IB_DEV_PATH" 2>/dev/null | head -n1 || true)"
     fi

     IFACE_LABEL="$IFACE_NAME"
     if [[ -n "$DEV_NAME" ]]; then
       IFACE_LABEL="$IFACE_NAME($DEV_NAME)"
     fi

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
    echo "$REL_PATH $IFACE_LABEL RX=${RX_TB}TB TX=${TX_TB}TB RX_pkts=$RX_PKTS TX_pkts=$TX_PKTS AvgRxPkt=${AVG_RX}B AvgTxPkt=${AVG_TX}B rx_errs=$RX_ERRS tx_errs=$TX_ERRS rx_drop=$RX_DROP tx_drop=$TX_DROP"
    #echo "$REL_PATH $IFACE_NAME RX=${RX_TB}TB TX=${TX_TB}TB RX_pkts=$RX_PKTS TX_pkts=$TX_PKTS AvgRxPkt=${AVG_RX}B AvgTxPkt=${AVG_TX}B rx_errs=$RX_ERRS tx_errs=$TX_ERRS rx_drop=$RX_DROP tx_drop=$TX_DROP"
  done
done
