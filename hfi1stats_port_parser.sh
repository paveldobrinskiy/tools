#!/usr/bin/env bash
# hfi1stats_port_parser_internal.sh
# Author: pdobrinskiy@cornelisnetworks.com v1
# hfi1stats_parser.sh
# Parse hfi1stats output into CSV

# Parse hfi1stats output, split per port into CSVs, filter by an internal dictionary of substrings.
# Requirements: bash 4+
#
# Usage:
#   ./hfi1stats_port_parser_internal.sh <hfi1stats_file_or_-> <out_dir>
#
# Configure your internal "dictionary" below:
#   - Add/remove substrings in PATTERNS to keep metrics whose names contain them.
#   - If PATTERNS is empty, all metrics are kept.
#
#
set -euo pipefail

# ------------------ USER CONFIGURABLE DICTIONARY ------------------
# Substrings to match in metric names. Example: (Wait Drop Err)
PATTERNS=(ErrorIntr Tx_Errs Rcv_Errs H/W_Errs EgrBufFull EgrHdrFull RcvHdrOvrX RcvOverflow TxFlowStall RxWait TxWait TxFlit RxFlit PktDrop TxDropped TxPktVL RxPktVL TxWord RxWord)
# Case-insensitive match? 1=yes, 0=no
CASE_INS=1
# ------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <opacapture dir> <out_dir>" >&2
  exit 1
fi

INPUT="$1"
OUTDIR="$2"

BASE_DIR="${INPUT%/tmp/*}"

# Append var/log/messages
MSG_PATH="$BASE_DIR/var/log/messages"

echo "$MSG_PATH"

mkdir -p "$OUTDIR"

# Track if header was written per port
declare -A HEADER_WRITTEN=()

# Convert value with K/M/G/T/P suffix to integer
convert_value() {
  local num="$1" unit="$2"
  case "$unit" in
    K) printf '%s\n' $(( num * 1000 )) ;;
    M) printf '%s\n' $(( num * 1000000 )) ;;
    G) printf '%s\n' $(( num * 1000000000 )) ;;
    T) printf '%s\n' $(( num * 1000000000000 )) ;;
    P) printf '%s\n' $(( num * 1000000000000000 )) ;;
    *) printf '%s\n' "$num" ;;
  esac
}

# Check if metric matches any pattern (if patterns provided)
matches_patterns() {
  local metric="$1"
  # If no patterns specified, always match
  if [[ ${#PATTERNS[@]} -eq 0 ]]; then
    return 0
  fi
  local m_chk="$metric"
  if [[ $CASE_INS -eq 1 ]]; then
    m_chk="${m_chk,,}"
  fi
  for pat in "${PATTERNS[@]}"; do
    [[ -z "$pat" ]] && continue
    local p_chk="$pat"
    if [[ $CASE_INS -eq 1 ]]; then
      p_chk="${p_chk,,}"
    fi
    if [[ "$m_chk" == *"$p_chk"* ]]; then
      return 0
    fi
  done
  return 1
}
mapfile -t NET_DIRS < <(find "$INPUT" -type f -name 'hfi1stats' 2>/dev/null | sort)

if [[ ${#NET_DIRS[@]} -eq 0 ]]; then
  echo "No 'hfi1stats' files found under: $ROOT"
  exit 0
fi

echo "Dictionary: ${PATTERNS[*]:-<empty (match all)>} (CASE_INS=$CASE_INS)"
echo "metric,value,host,port" > "$OUTDIR/hfi1stats.csv"

for HFI1STATS  in "${NET_DIRS[@]}"; do
       DIRB="${HFI1STATS%/hfi1stats}"
       echo "$DIRB"
       HOSTN="$(awk '{print $4; exit}' "$DIRB"/../../var/log/messages)"
       mkdir -p "$OUTDIR/$HOSTN"
       echo "Processing $HFI1STATS...."

	exec 3<"$HFI1STATS"

	current_port="global"

	while IFS= read -r line <&3; do
	  # Normalize tabs to spaces
	  line="${line//$'\t'/ }"
	  # Detect port header lines (common forms)
	  if [[ "$line" =~ ^[[:space:]]*Port[[:space:]]*([0-9]+) ]]; then
	    current_port="port${BASH_REMATCH[1]}"
	    continue
	  fi
	  if [[ "$line" =~ ^[[:space:]]*HFI[[:space:]]*([0-9]+) ]]; then
	    current_port="hfi${BASH_REMATCH[1]}"
	    continue
	  fi
	  # Extract tokens: metric then value
	  read -r metric val _ <<< "$line"
	  # Validate tokens
	  if [[ "$metric" =~ ^[A-Za-z0-9_.:/-]+$ ]] && [[ "$val" =~ ^([0-9]+)([KMGTP]?)$ ]]; then
	    num="${BASH_REMATCH[1]}"
	    unit="${BASH_REMATCH[2]}"
	    # Filter by patterns (if provided)
	    if ! matches_patterns "$metric"; then
	      continue
	    fi
	    value="$(convert_value "$num" "$unit")"
	    unit_scale="${unit:-none}"
	    outfile="$OUTDIR/$HOSTN/hfi1stats.csv"
	    # Write header once per file
	    if [[ -z "${HEADER_WRITTEN[$outfile]+x}" ]]; then
	      echo "metric,value,host,port" > "$outfile"
	      HEADER_WRITTEN[$outfile]=1
	    fi
	    echo "$metric,$value,$HOSTN,${current_port}" >> "$outfile"
	    echo "$metric,$value,$HOSTN,${current_port}" >> "$OUTDIR/hfi1stats.csv"
	  fi
	done

	echo "Wrote per-port CSVs to: $OUTDIR/$HOSTN"
done	
