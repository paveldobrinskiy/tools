#!/usr/bin/env bash
# Autor: Pavel Dobrinskiy pdobrinskiy@cornelisnetworks.com
# Save hfi1stats to JSON  print filtered, non-zero deltas (desc).
# Default filter: (DcRcvBbl|TxWait|TxFlowStall|Flit)
# for OPA100
# Usage:
#   ./hfi1stats_delta.sh
#   ./hfi1stats_delta.sh --filter '^Port.*\.(TxPkt|RxPkt)$'   # override filter
#   ./hfi1stats_delta.sh --cmd "hfi1stats -v"                 # custom command

set -euo pipefail

HFI_CMD="hfi1stats"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
STATE_DIR="/var/tmp"
STATE_FILE="${STATE_DIR}/hfi1stats_${HOSTNAME_SHORT}.json"

# Default filter (configurable)
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
State file: ${STATE_FILE}
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RAW_OUT="$($HFI_CMD 2>/dev/null || true)"
[[ -z "$RAW_OUT" ]] && { echo "Error: no output from command: $HFI_CMD" >&2; exit 1; }
NOW_TS="$(date -Iseconds)"

# Parse to "section.key|valueToken" lines (handles multi-word names & K/M/G)
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

# Load previous snapshot if present
PREV_TS=""
if [[ -s "$STATE_FILE" ]]; then
  PREV_TS="$(sed -n 's/.*"timestamp"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$STATE_FILE" | head -n1 || true)"
  in_data=0
  while IFS= read -r line; do
    [[ "$line" =~ \"data\"[[:space:]]*:\ *\{ ]] && { in_data=1; continue; }
    [[ $in_data -eq 1 && "$line" =~ \} ]] && { in_data=0; continue; }
    if [[ $in_data -eq 1 && "$line" =~ \"(.*)\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
      k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"; prev["$k"]="$v"
    fi
  done < "$STATE_FILE"
fi

# Print timestamps and filtered non-zero deltas
if [[ -n "$PREV_TS" ]]; then
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
  echo "No previous state found. Creating initial snapshot."
  echo "Current run: $NOW_TS"
  echo
fi

# Save current snapshot as JSON
mkdir -p "$STATE_DIR"
{
  echo "{"
  echo "  \"timestamp\": \"${NOW_TS}\","
  echo "  \"data\": {"
  first=1
  for key in "${!curr[@]}"; do
    esc="${key//\\/\\\\}"; esc="${esc//\"/\\\"}"
    val="${curr[$key]}"
    if [[ $first -eq 1 ]]; then
      printf '    "%s": %s\n' "$esc" "$val"; first=0
    else
      printf '    ,"%s": %s\n' "$esc" "$val"
    fi
  done
  echo "  }"
  echo "}"
} > "$STATE_FILE"

echo "State saved to: $STATE_FILE"
