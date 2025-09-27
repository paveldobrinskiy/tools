#!/usr/bin/env bash
# Author: Pavel Dobrinskiy
# Purpose: Save hfi1stats to a single CSV history file and print filtered, non-zero deltas (desc).
# Default filter: (DcRcvBbl|TxWait|TxFlowStall|Flit)
# Usage:
#   ./hfi1stats_delta.sh
#   ./hfi1stats_delta.sh --filter '^Port.*\.(TxPkt|RxPkt)$'
#   ./hfi1stats_delta_.sh --cmd "hfi1stats -v"

set -euo pipefail

HFI_CMD="hfi1stats"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
STATE_DIR="/var/tmp"
HIST_FILE="${STATE_DIR}/hfi1stats_${HOSTNAME_SHORT}.csv"

DEFAULT_FILTER='(DcRcvBbl|TxWait|TxFlowStall|Flit)'
FILTER_REGEX="$DEFAULT_FILTER"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) FILTER_REGEX="$2"; shift 2 ;;
    -c|--cmd) HFI_CMD="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--filter "<regex>"] [-c|--cmd "<hfi1stats command>"]
  --filter "<regex>"  Only show keys matching this regex (default: $DEFAULT_FILTER)
  -c, --cmd "<cmd>"   Command to run instead of 'hfi1stats'
History file: ${HIST_FILE}
EOF
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RAW_OUT="$($HFI_CMD 2>/dev/null || true)"
[[ -z "$RAW_OUT" ]] && { echo "Error: no output from command: $HFI_CMD" >&2; exit 1; }
NOW_TS="$(date -Iseconds)"

# Parse to "section.key|valueToken"
PARSED_LINES="$(
  awk '
    function trim(s){ sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    BEGIN{section=""; name=""}
    {
      n=split($0, t, /[[:space:]]+/);
      for(i=1;i<=n;i++){
        tok=t[i];
        if (tok ~ /:$/ && tok !~ /^[0-9]/) { section=substr(tok,1,length(tok)-1); name=""; continue }
        if (tok ~ /^[0-9]+[KMG]?$/) {
          key=trim(name);
          if (key!="") {
            full=(section!=""?section"."key:key);
            print full "|" tok;
          }
          name="";
        } else {
          name=(name==""?tok:name" "tok);
        }
      }
    }
  ' <<< "$RAW_OUT"
)"

normalize() {
  local tok="$1"
  if [[ "$tok" =~ ^([0-9]+)([KMG]?)$ ]]; then
    local n="${BASH_REMATCH[1]}"; local s="${BASH_REMATCH[2]}"
    case "$s" in
      K) echo "$(( n * 1000 ))" ;;
      M) echo "$(( n * 1000000 ))" ;;
      G) echo "$(( n * 1000000000 ))" ;;
      "") echo "$n" ;;
      *) echo 0 ;;
    esac
  else
    echo 0
  fi
}

declare -A curr prev
# shellcheck disable=SC2162
while IFS="|" read k v; do
  [[ -z "${k:-}" || -z "${v:-}" ]] && continue
  curr["$k"]="$(normalize "$v")"
done <<< "$PARSED_LINES"

mkdir -p "$STATE_DIR"
# Initialize history file with header if new
if [[ ! -s "$HIST_FILE" ]]; then
  echo "timestamp,key,value" > "$HIST_FILE"
fi

# Find the previous timestamp (from the last data row)
PREV_TS="$(tail -n +2 "$HIST_FILE" | tail -n 1 | cut -d, -f1 || true)"

# Load previous snapshot map (only rows with PREV_TS)
if [[ -n "${PREV_TS}" ]]; then
  while IFS=, read -r ts key val; do
    [[ "$ts" != "$PREV_TS" ]] && continue
    prev["$key"]="$val"
  done < "$HIST_FILE"
fi

# Print deltas
if [[ -n "${PREV_TS}" ]]; then
  echo "Previous run: $PREV_TS"
  echo "Current  run: $NOW_TS"
  echo
  echo -e "Per-key deltas (current - previous), filtered by /$FILTER_REGEX/, non-zero only:\n"

  TMP_OUT="$(mktemp)"
  {
    for k in "${!curr[@]}"; do
      [[ -z "${prev[$k]:-}" ]] && continue
      [[ "$k" =~ $FILTER_REGEX ]] || continue
      delta=$(( curr[$k] - prev[$k] ))
      [[ "$delta" -ne 0 ]] && printf "%s\t%d\n" "$k" "$delta"
    done
  } > "$TMP_OUT"

  if [[ -s "$TMP_OUT" ]]; then
    LC_ALL=C sort -k2,2nr "$TMP_OUT" | awk -F'\t' '{printf "%-40s %15d\n",$1,$2}'
  else
    echo "(no matching counters changed)"
  fi
  rm -f "$TMP_OUT"
  echo
else
  echo "No previous snapshot in history. Creating initial entry."
  echo "Current run: $NOW_TS"
  echo
fi

# Append current snapshot to history CSV (one row per key)
# Keys should not contain commas; if they might, replace commas.
for key in "${!curr[@]}"; do
  clean_key="${key//,/;}"
  echo "${NOW_TS},${clean_key},${curr[$key]}" >> "$HIST_FILE"
done

echo "Appended snapshot to history: $HIST_FILE"