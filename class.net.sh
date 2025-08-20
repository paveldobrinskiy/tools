#!/bin/bash

# Author: pdobrinskiy@cornelisnetworks.com v1
# One-shot Linux network statistics collector
# Usage: ./netsotats_linux.sh /path/to/sys/class/net
# print statistic in TBytes
# sample output

: '
pdobrinskiy_cornelis@COR-CHE-LT-456 class % ./class.net.sh ./net
enp0s20f0u1u6 RX=0TB TX=0TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
ens4f0 RX=.065TB TX=.040TB RX_pkts=404759352 TX_pkts=178098973 AvgRxPkt=160B AvgTxPkt=225B rx_errs=0 tx_errs=0 rx_drop=952173 tx_drop=0
ens4f1 RX=0TB TX=0TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
ens4f2 RX=0TB TX=0TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
ens4f3 RX=0TB TX=0TB RX_pkts=0 TX_pkts=0 AvgRxPkt=0B AvgTxPkt=0B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
ib0 RX=3271.373TB TX=1584.108TB RX_pkts=1618693885518 TX_pkts=912047351907 AvgRxPkt=2020B AvgTxPkt=1736B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
ib1 RX=704.636TB TX=.004TB RX_pkts=401697672119 TX_pkts=74049647 AvgRxPkt=1754B AvgTxPkt=60B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=1073
ib2 RX=875.300TB TX=3206.624TB RX_pkts=510583546205 TX_pkts=1618734016413 AvgRxPkt=1714B AvgTxPkt=1980B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=13091
lo RX=0TB TX=0TB RX_pkts=555303 TX_pkts=555303 AvgRxPkt=356B AvgTxPkt=356B rx_errs=0 tx_errs=0 rx_drop=0 tx_drop=0
usr RX=.034TB TX=.038TB RX_pkts=284700923 TX_pkts=173384498 AvgRxPkt=121B AvgTxPkt=219B rx_errs=0 tx_errs=0 rx_drop=76741 tx_drop=0
'


OUTDIR=$1
INTERVAL=${2:-5}   # default = 5 seconds

if [ -z "$OUTDIR" ]; then
    echo "Usage: $0 /path/to/output_folder [interval_seconds]"
    exit 1
fi

mkdir -p "$OUTDIR"

to_tb() {
    # Convert bytes to terabytes (TB, base 10: 1 TB = 10^12 bytes)
    echo "scale=3; $1/1000000000000" | bc
}

while true; do
    TS=$(date +"%Y-%m-%d %H:%M:%S")
    for IFACE in /sys/class/net/*; do
        IF=$(basename "$IFACE")

        # skip loopback
        if [ "$IF" = "lo" ]; then
            continue
        fi

        RX_BYTES=$(cat $IFACE/statistics/rx_bytes)
        TX_BYTES=$(cat $IFACE/statistics/tx_bytes)
        RX_PKTS=$(cat $IFACE/statistics/rx_packets)
        TX_PKTS=$(cat $IFACE/statistics/tx_packets)
        RX_ERRS=$(cat $IFACE/statistics/rx_errors)
        TX_ERRS=$(cat $IFACE/statistics/tx_errors)
        RX_DROP=$(cat $IFACE/statistics/rx_dropped)
        TX_DROP=$(cat $IFACE/statistics/tx_dropped)
        RX_CRC=$(cat $IFACE/statistics/rx_crc_errors)

        RX_TB=$(to_tb $RX_BYTES)
        TX_TB=$(to_tb $TX_BYTES)

        if [ "$RX_PKTS" -gt 0 ]; then
            AVG_RX=$(echo "scale=1; $RX_BYTES/$RX_PKTS" | bc)
        else
            AVG_RX=0
        fi
        if [ "$TX_PKTS" -gt 0 ]; then
            AVG_TX=$(echo "scale=1; $TX_BYTES/$TX_PKTS" | bc)
        else
            AVG_TX=0
        fi

        echo "$TS $IF RX=${RX_TB}TB TX=${TX_TB}TB RX_pkts=$RX_PKTS TX_pkts=$TX_PKTS AvgRxPkt=${AVG_RX}B AvgTxPkt=${AVG_TX}B rx_errs=$RX_ERRS tx_errs=$TX_ERRS rx_drop=$RX_DROP tx_drop=$TX_DROP rx_crc=$RX_CRC" \
            >> "$OUTDIR/${IF}.log"
    done
    sleep $INTERVAL
done