#!/usr/bin/env bash
# fm.check.sh
# Usage: ./fm.check.sh /path/to/opafm.log

set -euo pipefail

LOGFILE="${1:-/dev/stdin}"

grep -F "PmPrintFailPort: Unable to Get(PortStatus)" "$LOGFILE" \
| sed -E 's/.*Unable to Get\(PortStatus\) ([^ ]+).*/\1/' \
| sort \
| uniq -c \
| sort -nr
