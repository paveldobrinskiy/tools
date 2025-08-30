#!/usr/bin/env bash

# Author: pdobrinskiy@cornelisnetworks.com v1
# hfi1stats_parser.sh
# Parse hfi1stats output into CSV
# example
: '
2025-08-25-opacapture-blnet4/tmp/capture2490689 ens4f1 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ens4f2 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ens4f3 RX=0.000TB TX=0.000TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ib0(mlx5_0) RX=733.703TB TX=559.210TB RX_pkts=364900416481 TX_pkts=319341941192 AvgRxPkt=2010B AvgTxPkt=1751B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
2025-08-25-opacapture-blnet4/tmp/capture2490689 ib1(hfi1_0) RX=306.103TB TX=0.001TB RX_pkts=175733034532 TX_pkts=24254448 AvgRxPkt=1741B AvgTxPkt=60B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=1495
2025-08-25-opacapture-blnet4/tmp/capture2490689 ib2(hfi1_1) RX=251.653TB TX=719.110TB RX_pkts=143691312929 TX_pkts=364949688485 AvgRxPkt=1751B AvgTxPkt=1970B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=13032
'

INPUT="$1"
OUTPUT="${2:-hfi1stats_parsed.csv}"

if [[ -z "$INPUT" ]]; then
    echo "Usage: $0 <hfi1stats_file> [output.csv]"
    exit 1
fi

# CSV header
echo "metric,value,value_raw,unit_scale" > "$OUTPUT"

# Function to convert suffix into multiplier
convert_value() {
    local num="$1"
    local unit="$2"
    case "$unit" in
        K) echo $(( num * 1000 )) ;;
        M) echo $(( num * 1000000 )) ;;
        G) echo $(( num * 1000000000 )) ;;
        T) echo $(( num * 1000000000000 )) ;;
        P) echo $(( num * 1000000000000000 )) ;;
        *) echo "$num" ;;
    esac
}

# Read line by line
while read -r metric numunit; do
    # match lines like "MetricName   12345K"
    if [[ "$metric" =~ ^[A-Za-z0-9_.:/-]+$ ]] && [[ "$numunit" =~ ^([0-9]+)([KMGTP]?)$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        value=$(convert_value "$num" "$unit")
        unit_scale="${unit:-none}"
        echo "$metric,$value,${num}${unit},$unit_scale" >> "$OUTPUT"
    fi
done < "$INPUT"

echo "Written CSV: $OUTPUT"
