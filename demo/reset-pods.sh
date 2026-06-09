#!/usr/bin/env bash
# reset-pods.sh -- Delete and recreate just the agent pods/sandboxes
#
# Unlike teardown.sh + setup.sh, this does NOT touch the OpenShell
# gateway, Helm release, Kata operator, veth patch, SCC, JWT keys,
# or attacker listener. It only recreates the three agent pods so
# they have fresh filesystems (clean /opt/marker.txt, uncorrupted
# /usr/bin/su, etc.)
#
# Prerequisites:
#   - OpenShell gateway running (setup.sh already completed)
#   - Port-forward running in another terminal:
#     oc port-forward -n openshell-poc svc/openshell 18080:8080
#   - REGISTRY env var set
#
# Usage:
#   export REGISTRY=quay.io/yourorg
#   ./demo/reset-pods.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="openshell-poc"

info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
fatal() { echo "ERROR: $*" >&2; exit 1; }

if [ -z "${REGISTRY:-}" ]; then
    fatal "REGISTRY env var not set."
fi

# --- Delete existing agent pods/sandboxes ---

info "Deleting OpenShell sandboxes..."
for sandbox in opencode-openshell-only opencode-dual; do
    oc delete sandbox "${sandbox}" -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
done

info "Deleting kata-only pod..."
oc delete pod opencode-kata-only -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true

info "Waiting for pods to terminate..."
sleep 5

# --- Recreate ---

info "Creating opencode-kata-only (raw pod, Kata runtime)..."
sed "s|REGISTRY|${REGISTRY}|g" "${REPO_ROOT}/deploy/pod-kata-only.yaml" \
    | oc apply -f -

info "Creating opencode-openshell-only (OpenShell sandbox, default runtime)..."
openshell sandbox create \
    --name opencode-openshell-only \
    --policy "${REPO_ROOT}/deploy/openshell-policy.yaml" \
    --no-tty \
    -- sleep infinity &
OS_PID=$!
sleep 5

info "Creating opencode-dual (OpenShell sandbox + Kata runtime)..."
openshell sandbox create \
    --name opencode-dual \
    --policy "${REPO_ROOT}/deploy/openshell-policy.yaml" \
    --driver-config-json '{"kubernetes":{"pod":{"runtime_class_name":"kata"}}}' \
    --no-tty \
    -- sleep infinity &
DUAL_PID=$!
sleep 5

# Kill the backgrounded CLI processes (sandbox pods keep running)
kill "${OS_PID}" 2>/dev/null || true
kill "${DUAL_PID}" 2>/dev/null || true
wait "${OS_PID}" 2>/dev/null || true
wait "${DUAL_PID}" 2>/dev/null || true

# --- Wait ---

info "Waiting for pods to be ready..."
for pod in opencode-kata-only opencode-openshell-only opencode-dual; do
    oc wait --for=condition=Ready "pod/${pod}" \
        -n "${NAMESPACE}" --timeout=180s || warn "${pod} not ready"
done

info "All pods:"
oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/part-of=openshell-sandbox-poc -o wide 2>/dev/null || true
oc get pods -n "${NAMESPACE}" | grep opencode || true

echo ""
info "Pods reset. Run ./demo/run-demo.sh"
