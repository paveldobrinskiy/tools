#!/usr/bin/env bash


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
mapfile -t NET_DIRS < <(find "$ROOT" -type f -name 'hfi1stats' 2>/dev/null | sort)

if [[ ${#NET_DIRS[@]} -eq 0 ]]; then
  echo "No 'hfi1stats' files found under: $ROOT"
  exit 0
fi

for HFI1STATS  in "${NET_DIRS[@]}"; do
    DIRB="${HFI1STATS%/hfi1stats}"
    echo "$DIRB"
    HOSTN="$(awk '{print $4; exit}' "$DIRB"/../../var/log/messages)"
    echo "$HFI1STATS - $HOSTN"
done
