#!/usr/bin/env bash
# Shared utility functions for the demo

NAMESPACE="openshell-poc"
LISTENER_SVC="attacker-listener.${NAMESPACE}.svc:9999"
CONTAINER="agent"

# Pods with OpenShell protection -- these use `openshell sandbox exec`
# to ensure commands run inside the supervised sandbox (network namespace
# with policy proxy). Using `oc exec` bypasses the proxy.
OPENSHELL_PODS="opencode-openshell-only opencode-dual"

# Execute a command in a pod, choosing the right exec method.
# OpenShell-protected pods use `openshell sandbox exec` (goes through
# the supervisor/proxy). Non-OpenShell pods use `oc exec` directly.
#
# Use this for Attack 1 (network exfiltration) where we need the
# command to run inside the sandbox's network namespace so the
# policy proxy can intercept and block unauthorized egress.
pod_exec() {
    local pod="$1"
    shift

    if echo "${OPENSHELL_PODS}" | grep -qw "${pod}"; then
        # OpenShell-protected pod: exec through the supervisor
        openshell sandbox exec -n "${pod}" --no-tty --timeout 30 -- "$@" 2>&1
    else
        # Raw pod: exec directly via oc
        oc exec -n "${NAMESPACE}" "${pod}" -c "${CONTAINER}" -- "$@" 2>&1
    fi
}

# Launch a short-lived verification pod on a specific node from the
# same image, run a command, capture output, then delete the pod.
# Used to verify whether page-cache corruption escaped the container.
verify_pod_exec() {
    local node="$1"
    local image="$2"
    shift 2
    local vname="verify-escape-$$-${RANDOM}"

    # Create the pod on the specific node, overriding the entrypoint
    oc run "${vname}" -n "${NAMESPACE}" \
        --image="${image}" \
        --restart=Never \
        --command \
        --overrides="{\"spec\":{\"nodeName\":\"${node}\"}}" \
        -- "$@" >/dev/null 2>&1

    # Wait for it to complete (it runs the command and exits)
    local i=0
    while [ $i -lt 30 ]; do
        PHASE=$(oc get pod "${vname}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        if [ "${PHASE}" = "Succeeded" ] || [ "${PHASE}" = "Failed" ]; then
            break
        fi
        sleep 2
        i=$((i + 1))
    done

    # Capture output
    oc logs -n "${NAMESPACE}" "${vname}" 2>/dev/null

    # Clean up
    oc delete pod "${vname}" -n "${NAMESPACE}" \
        --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

# Drop the host's page cache on a node. This clears any page-cache
# corruption from previous exploit runs so each test starts clean.
drop_page_cache() {
    local node="$1"
    oc debug "node/${node}" --quiet -- \
        chroot /host sh -c 'echo 3 > /proc/sys/vm/drop_caches' \
        >/dev/null 2>&1 || true
}

# Get the node a pod is running on
pod_node() {
    local pod="$1"
    oc get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.nodeName}' 2>/dev/null
}

# Get the image used by a pod's agent container
pod_image() {
    local pod="$1"
    oc get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.containers[?(@.name=="agent")].image}' 2>/dev/null
}

# Get the attacker listener pod name
listener_pod() {
    oc get pod -n "${NAMESPACE}" -l app=attacker-listener \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Get current attacker listener log line count (for detecting new entries)
listener_log_count() {
    oc logs -n "${NAMESPACE}" "$(listener_pod)" 2>/dev/null | wc -l
}

# Get attacker listener logs since a given line count
listener_logs_since() {
    local since_line="$1"
    oc logs -n "${NAMESPACE}" "$(listener_pod)" 2>/dev/null | tail -n +"$((since_line + 1))"
}

# Check if a pod is ready
pod_ready() {
    local pod="$1"
    local status
    status=$(oc get pod "${pod}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "${status}" = "Running" ]
}

# Print a pause for dramatic effect in demos
pause() {
    local secs="${1:-2}"
    sleep "${secs}"
}
