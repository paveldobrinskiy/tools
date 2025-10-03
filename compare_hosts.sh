#!/usr/bin/env bash
# Compare OS, CPU, FW (/root/updateAgent -V), hfi1.conf, and ONLY selected package families
# Usage: ./compare_hosts.sh host1 host2
# Requires: passwordless SSH to both hosts

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <host1> <host2>"
  exit 1
fi

HOST1="$1"
HOST2="$2"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Package name prefixes to include (regex anchored at start)
PKG_RE='^(opa|opx|cna|cn5000|hfi)'

echo "🔍 Collecting data from $HOST1 and $HOST2 ..."

# --- OS release ---
ssh "$HOST1" "grep -h ^PRETTY_NAME /etc/*release || cat /etc/*release" > "$TMPDIR/os1.txt"
ssh "$HOST2" "grep -h ^PRETTY_NAME /etc/*release || cat /etc/*release" > "$TMPDIR/os2.txt"

# --- CPU model ---
ssh "$HOST1" "lscpu | grep -F 'Model name' || cat /proc/cpuinfo | grep -m1 -F 'model name' || echo 'N/A'" > "$TMPDIR/cpu1.txt"
ssh "$HOST2" "lscpu | grep -F 'Model name' || cat /proc/cpuinfo | grep -m1 -F 'model name' || echo 'N/A'" > "$TMPDIR/cpu2.txt"

# --- Firmware version ---
ssh "$HOST1" "/root/updateAgent -V 2>/dev/null || echo 'N/A'" > "$TMPDIR/fw1.txt"
ssh "$HOST2" "/root/updateAgent -V 2>/dev/null || echo 'N/A'" > "$TMPDIR/fw2.txt"

# --- hfi1.conf ---
ssh "$HOST1" "cat /etc/modprobe.d/hfi1.conf 2>/dev/null || echo 'missing'" > "$TMPDIR/conf1.txt"
ssh "$HOST2" "cat /etc/modprobe.d/hfi1.conf 2>/dev/null || echo 'missing'" > "$TMPDIR/conf2.txt"

# --- Packages (filtered) ---
# For RPM distros: output lines like name-version-release.arch
# For dpkg systems: output lines like name-version
PKG_CMD_RPM='rpm -qa --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort'
PKG_CMD_DPKG='dpkg-query -W -f="${Package}-${Version}\n" | sort'

ssh "$HOST1" "if command -v rpm >/dev/null; then $PKG_CMD_RPM; elif command -v dpkg-query >/dev/null; then $PKG_CMD_DPKG; fi" \
  | awk -v IGNORECASE=1 -v re="$PKG_RE" 'match($0, re)==1' > "$TMPDIR/pkgs1.txt"

ssh "$HOST2" "if command -v rpm >/dev/null; then $PKG_CMD_RPM; elif command -v dpkg-query >/dev/null; then $PKG_CMD_DPKG; fi" \
  | awk -v IGNORECASE=1 -v re="$PKG_RE" 'match($0, re)==1' > "$TMPDIR/pkgs2.txt"

# --- Print results ---
echo
echo "===== OS Version ====="
paste <(echo "$HOST1:"; cat "$TMPDIR/os1.txt") <(echo "$HOST2:"; cat "$TMPDIR/os2.txt")

echo
echo "===== CPU Model ====="
paste <(echo "$HOST1:"; cat "$TMPDIR/cpu1.txt") <(echo "$HOST2:"; cat "$TMPDIR/cpu2.txt")

echo
echo "===== Firmware Version (updateAgent -V) ====="
paste <(echo "$HOST1:"; cat "$TMPDIR/fw1.txt") <(echo "$HOST2:"; cat "$TMPDIR/fw2.txt")

echo
echo "===== /etc/modprobe.d/hfi1.conf (diff) ====="
diff -u "$TMPDIR/conf1.txt" "$TMPDIR/conf2.txt" || true

echo
echo "===== Selected Package Differences (only: opa|opx|cna|cn5000|hfi) ====="
# comm needs sorted inputs (already sorted), shows lines unique to each
comm -3 "$TMPDIR/pkgs1.txt" "$TMPDIR/pkgs2.txt" | awk -v h1="$HOST1" -v h2="$HOST2" '
BEGIN {
  printf "%-75s | %-75s\n", h1, h2
  for (i=0;i<153;i++) printf "-"; printf "\n"
}
{
  if (substr($0,1,1)=="\t") {
    printf "%-75s | %-75s\n", "", substr($0,2)
  } else {
    printf "%-75s | %-75s\n", $0, ""
  }
}
'