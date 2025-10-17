#!/bin/sh
# check_iommu_pt.sh
# Usage:
#   ./check_iommu_pt.sh                # auto-detect nodes via sinfo
#   ./check_iommu_pt.sh 'd[001-100]'   # use explicit Slurm nodelist
#
# Requires: passwordless SSH as root to all nodes.
# Optional: Slurm commands (sinfo/scontrol) to expand nodelists.

set -eu

# --- Resolve node list ---
if [ "${1-}" ]; then
    # If a bracketed list is provided, expand it with scontrol if available
    if command -v scontrol >/dev/null 2>&1; then
        NODES=$(scontrol show hostnames "$1")
    else
        echo "ERROR: scontrol not found. Provide whitespace-separated hostnames instead of bracket syntax." >&2
        exit 1
    fi
elif command -v sinfo >/dev/null 2>&1; then
    # Pull all nodes known to Slurm
    NODES=$(sinfo -h -N -o %N | sort -u)
else
    echo "ERROR: No node list provided and sinfo not available." >&2
    echo "Usage: $0 'd[001-100]'   (requires scontrol)  OR edit script to hardcode nodes." >&2
    exit 1
fi

# --- SSH options (non-interactive, fast fail) ---
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5"

OK_LIST=""
NOT_PT_LIST=""
UNREACHABLE_LIST=""

# --- Optional simple concurrency control ---
MAX_JOBS=20
jobs_running() { jobs | wc -l | awk '{print $1}'; }

# temp files for collecting results safely
TMPDIR="${TMPDIR:-/tmp}"
OK_FILE="$TMPDIR/iommu_ok.$$"
NP_FILE="$TMPDIR/iommu_notpt.$$"
UR_FILE="$TMPDIR/iommu_unreach.$$"
: >"$OK_FILE"; : >"$NP_FILE"; : >"$UR_FILE"

check_node() {
    node="$1"

    # Run the check remotely
    # Return codes:
    #  0: Passthrough line found
    #  1: dmesg accessible but no passthrough line
    #  255 or ssh failure: unreachable
    out=""
    if ! out=$(ssh $SSH_OPTS "root@$node" \
        "dmesg | grep -i -e iommu -e dmar | grep -q 'Default domain type: Passthrough'"); then

        rc=$?
        if [ $rc -eq 255 ]; then
            echo "$node" >>"$UR_FILE"
            printf "%-12s : UNREACHABLE\n" "$node"
        else
            # Could be no match, or dmesg permission; try journalctl as a fallback
            if ssh $SSH_OPTS "root@$node" \
                "journalctl -k --no-pager 2>/dev/null | grep -i 'Default domain type:' | grep -q 'Passthrough'"; then
                echo "$node" >>"$OK_FILE"
                printf "%-12s : PT\n" "$node"
            else
                echo "$node" >>"$NP_FILE"
                printf "%-12s : NOT_PT\n" "$node"
            fi
        fi
    else
        echo "$node" >>"$OK_FILE"
        printf "%-12s : PT\n" "$node"
    fi
}

echo "Checking IOMMU passthrough (iommu=pt) on nodes..."
echo

for n in $NODES; do
    # Throttle background jobs
    while [ "$(jobs_running)" -ge "$MAX_JOBS" ]; do
        sleep 0.1
    done
    check_node "$n" &
done

wait

# --- Gather results ---
[ -s "$OK_FILE" ] && OK_LIST=$(tr '\n' ' ' <"$OK_FILE")
[ -s "$NP_FILE" ] && NOT_PT_LIST=$(tr '\n' ' ' <"$NP_FILE")
[ -s "$UR_FILE" ] && UNREACHABLE_LIST=$(tr '\n' ' ' <"$UR_FILE")

OK_CNT=$(wc -w <<EOF
$OK_LIST
EOF
)
NP_CNT=$(wc -w <<EOF
$NOT_PT_LIST
EOF
)
UR_CNT=$(wc -w <<EOF
$UNREACHABLE_LIST
EOF
)

TOTAL=$(echo "$NODES" | wc -w | awk '{print $1}')

echo
echo "================== Summary =================="
echo "Total nodes checked : $TOTAL"
echo "PT (Passthrough)    : ${OK_CNT:-0}"
echo "NOT_PT              : ${NP_CNT:-0}"
echo "UNREACHABLE         : ${UR_CNT:-0}"
echo "============================================="
[ -n "$NOT_PT_LIST" ] && { echo "NOT_PT nodes:"; echo "  $NOT_PT_LIST"; }
[ -n "$UNREACHABLE_LIST" ] && { echo "UNREACHABLE nodes:"; echo "  $UNREACHABLE_LIST"; }

# cleanup
rm -f "$OK_FILE" "$NP_FILE" "$UR_FILE"