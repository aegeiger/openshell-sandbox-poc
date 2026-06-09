#!/usr/bin/env bash
# verify-kernel.sh -- Check whether cluster nodes are vulnerable to CVE-2026-31431
#
# The fix for CVE-2026-31431 is kernel commit a664bf3d603d, which was
# merged to mainline on April 1, 2026. Any kernel built before that
# date is likely vulnerable.
#
# This script checks each worker node's kernel version and build date.
#
# Usage: ./verify-kernel.sh
# Requires: oc CLI logged in with cluster-admin privileges

set -euo pipefail

echo "=== CVE-2026-31431 Kernel Vulnerability Check ==="
echo ""
echo "Fix commit: a664bf3d603dc3bdcf9ae47cc21e0daec706d7a5"
echo "Fix date:   April 1, 2026 (mainline)"
echo ""

WORKERS=$(oc get nodes -l node-role.kubernetes.io/worker -o name)

if [ -z "$WORKERS" ]; then
    echo "ERROR: No worker nodes found."
    exit 1
fi

VULN_COUNT=0
PATCHED_COUNT=0

for NODE in $WORKERS; do
    NODE_NAME=$(echo "$NODE" | sed 's|node/||')
    echo "--- Checking $NODE_NAME ---"

    # Get kernel version
    KERNEL=$(oc get node "$NODE_NAME" -o jsonpath='{.status.nodeInfo.kernelVersion}')
    echo "  Kernel: $KERNEL"

    # Get OS image
    OS=$(oc get node "$NODE_NAME" -o jsonpath='{.status.nodeInfo.osImage}')
    echo "  OS:     $OS"

    # Check kernel changelog for the CVE fix
    echo -n "  CVE-2026-31431 patch: "
    CHANGELOG=$(oc debug "node/$NODE_NAME" --quiet -- \
        chroot /host rpm -q --changelog "kernel-${KERNEL}" 2>/dev/null \
        | grep -c "CVE-2026-31431" || true)

    if [ "$CHANGELOG" -gt 0 ]; then
        echo "PATCHED (found in changelog)"
        PATCHED_COUNT=$((PATCHED_COUNT + 1))
    else
        # Also check build date as a heuristic
        BUILD_DATE=$(oc debug "node/$NODE_NAME" --quiet -- \
            chroot /host rpm -qi "kernel-${KERNEL}" 2>/dev/null \
            | grep "Build Date" | sed 's/Build Date  : //' || echo "unknown")
        echo "LIKELY VULNERABLE (not in changelog, built: $BUILD_DATE)"
        VULN_COUNT=$((VULN_COUNT + 1))
    fi

    # Check if algif_aead is builtin or module
    echo -n "  algif_aead: "
    MODINFO=$(oc debug "node/$NODE_NAME" --quiet -- \
        chroot /host modinfo algif_aead 2>/dev/null \
        | grep "^filename:" || echo "not found")
    if echo "$MODINFO" | grep -q "(builtin)"; then
        echo "BUILTIN (cannot be unloaded as mitigation)"
    elif echo "$MODINFO" | grep -q ".ko"; then
        echo "MODULE (can potentially rmmod as mitigation)"
    else
        echo "NOT FOUND"
    fi
    echo ""
done

echo "=== Summary ==="
echo "  Vulnerable:  $VULN_COUNT node(s)"
echo "  Patched:     $PATCHED_COUNT node(s)"
echo ""

if [ "$VULN_COUNT" -gt 0 ]; then
    echo "RESULT: Cluster has vulnerable nodes. Demo can proceed."
    exit 0
else
    echo "RESULT: All nodes appear patched. The container escape demo"
    echo "        will not work. Consider using an older OCP version."
    exit 1
fi
