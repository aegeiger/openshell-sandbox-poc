#!/usr/bin/env bash
# setup.sh -- Deploy everything needed for the dual-protection PoC
#
# Prerequisites:
#   - oc CLI logged in with cluster-admin privileges
#   - helm v3 installed
#   - openshell CLI installed (for sandbox creation)
#   - Kata Containers already installed (see infra/README.md)
#   - Container images built and pushed to REGISTRY
#   - REGISTRY env var set (e.g. quay.io/yourorg)
#
# Usage:
#   export REGISTRY=quay.io/yourorg
#   ./demo/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="openshell-poc"

# --- Helpers ---

info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
fatal() { echo "ERROR: $*" >&2; exit 1; }

PF_PID=""
cleanup() {
    if [ -n "${PF_PID}" ] && kill -0 "${PF_PID}" 2>/dev/null; then
        info "Stopping port-forward (PID ${PF_PID})..."
        kill "${PF_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- Preflight checks ---

info "Running preflight checks..."

command -v oc       >/dev/null || fatal "oc CLI not found"
command -v helm     >/dev/null || fatal "helm not found"
command -v openshell >/dev/null || warn "openshell CLI not found -- sandbox creation will fail"
oc whoami >/dev/null 2>&1     || fatal "Not logged in to OpenShift (run oc login first)"

if [ -z "${REGISTRY:-}" ]; then
    fatal "REGISTRY env var not set. Export it before running this script."
fi

for img in openshell-poc-agent-sandbox openshell-poc-attacker-listener; do
    info "Expecting image: ${REGISTRY}/${img}:latest"
done

# --- 1. Namespace ---

info "Creating namespace ${NAMESPACE}..."
oc apply -f "${REPO_ROOT}/deploy/namespace.yaml"

# --- 2. Agent Sandbox CRDs ---

info "Installing Agent Sandbox controller and CRDs..."
oc apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/latest/download/manifest.yaml

# --- 3. SCC ---

info "Creating openshell-kata SCC..."
oc apply -f "${REPO_ROOT}/deploy/openshell-scc.yaml"

info "Granting openshell-kata SCC to gateway and sandbox service accounts..."
oc patch scc openshell-kata \
    --type=json \
    -p="[
      {\"op\":\"add\",\"path\":\"/users/-\",\"value\":\"system:serviceaccount:${NAMESPACE}:openshell\"},
      {\"op\":\"add\",\"path\":\"/users/-\",\"value\":\"system:serviceaccount:${NAMESPACE}:openshell-sandbox\"}
    ]" 2>/dev/null || warn "SCC patch failed -- users may already be present"

# --- 4. OpenShell gateway ---

info "Installing OpenShell gateway via Helm..."
if helm status openshell -n "${NAMESPACE}" >/dev/null 2>&1; then
    info "OpenShell already installed, upgrading..."
    helm upgrade openshell oci://ghcr.io/nvidia/openshell/helm-chart \
        -n "${NAMESPACE}" \
        -f "${REPO_ROOT}/deploy/openshell-helm-values.yaml" \
        --set server.sandboxImage="${REGISTRY}/openshell-poc-agent-sandbox:latest"
else
    helm install openshell oci://ghcr.io/nvidia/openshell/helm-chart \
        -n "${NAMESPACE}" \
        -f "${REPO_ROOT}/deploy/openshell-helm-values.yaml" \
        --set server.sandboxImage="${REGISTRY}/openshell-poc-agent-sandbox:latest"
fi

# --- 5. JWT signing keys ---
# With pkiInitJob disabled, we must generate JWT keys BEFORE the
# gateway starts. Use the locally installed openshell-gateway binary.

info "Generating JWT signing keys..."
if ! oc get secret openshell-jwt-keys -n "${NAMESPACE}" >/dev/null 2>&1; then
    JWT_DIR=$(mktemp -d)
    openshell-gateway generate-certs --output-dir "${JWT_DIR}" \
        || fatal "Failed to generate JWT keys. Is openshell-gateway installed?"
    oc create secret generic openshell-jwt-keys -n "${NAMESPACE}" \
        --from-file=signing.pem="${JWT_DIR}/jwt/signing.pem" \
        --from-file=public.pem="${JWT_DIR}/jwt/public.pem" \
        --from-file=kid="${JWT_DIR}/jwt/kid"
    rm -rf "${JWT_DIR}"
    info "JWT keys secret created."
else
    info "JWT keys secret already exists, skipping."
fi

# --- 6. Wait for gateway ---

info "Waiting for OpenShell gateway to be ready..."
oc -n "${NAMESPACE}" rollout status statefulset/openshell --timeout=120s \
    || warn "Gateway not ready yet"

# --- 7. Patch Kata initramfs for veth module ---
# OpenShell needs the veth kernel module inside Kata VMs.
# The default Kata initramfs doesn't include it.

info "Patching Kata initramfs for veth module..."
oc apply -f "${REPO_ROOT}/infra/kata-veth-patch-job.yaml"

info "Waiting for veth patch to complete on all nodes..."
sleep 10
for pod in $(oc get pods -n openshift-sandboxed-containers-operator \
    -l app=kata-veth-patch -o name 2>/dev/null); do
    oc wait --for=condition=Ready "${pod}" \
        -n openshift-sandboxed-containers-operator \
        --timeout=120s 2>/dev/null || warn "veth patch pod not ready: ${pod}"
done

# Show patch results
for pod in $(oc get pods -n openshift-sandboxed-containers-operator \
    -l app=kata-veth-patch -o name 2>/dev/null); do
    NODE=$(oc get "${pod}" -n openshift-sandboxed-containers-operator \
        -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    LOG=$(oc logs -n openshift-sandboxed-containers-operator "${pod}" 2>/dev/null | tail -2)
    info "  ${NODE}: ${LOG}"
done

# Clean up patch DaemonSet (it's a one-shot job)
oc delete -f "${REPO_ROOT}/infra/kata-veth-patch-job.yaml" --ignore-not-found 2>/dev/null || true

# --- 8. ConfigMaps ---

info "Creating ConfigMaps..."
oc create configmap malicious-patch -n "${NAMESPACE}" \
    --from-file=malicious.patch="${REPO_ROOT}/attacks/attack1-prompt-injection/malicious.patch" \
    --from-file=task-prompt.txt="${REPO_ROOT}/attacks/attack1-prompt-injection/task-prompt.txt" \
    --dry-run=client -o yaml | oc apply -f -

# --- 9. Secrets ---

info "Creating API keys secret..."
if ! oc get secret opencode-api-keys -n "${NAMESPACE}" >/dev/null 2>&1; then
    oc create secret generic opencode-api-keys -n "${NAMESPACE}" \
        --from-literal=OPENAI_API_KEY="dummy-key-for-local-vllm"
    info "Created opencode-api-keys secret with dummy key."
else
    info "Secret opencode-api-keys already exists, skipping."
fi

# --- 10. Attacker listener ---

info "Deploying attacker listener..."
sed "s|REGISTRY|${REGISTRY}|g" "${REPO_ROOT}/deploy/attacker-listener.yaml" \
    | oc apply -f -

info "Waiting for attacker listener..."
oc wait --for=condition=Available deployment/attacker-listener \
    -n "${NAMESPACE}" --timeout=60s || warn "Listener not ready yet"

# --- 11. Port-forward to gateway ---
# The openshell CLI connects to the gateway via the registered endpoint.
# Since NodePort may not be reachable, use port-forward.

info "Starting port-forward to OpenShell gateway..."
oc port-forward -n "${NAMESPACE}" svc/openshell 18080:8080 > /tmp/openshell-pf.log 2>&1 &
PF_PID=$!
sleep 4

if ! kill -0 "${PF_PID}" 2>/dev/null; then
    fatal "Port-forward failed to start. Check /tmp/openshell-pf.log"
fi
info "Port-forward running (PID ${PF_PID})"

# Register the gateway if not already pointing at our port-forward
CURRENT_GW=$(openshell gateway list 2>/dev/null | grep '^\*' | awk '{print $3}' || true)
if [ "${CURRENT_GW}" != "http://127.0.0.1:18080" ]; then
    info "Registering gateway at http://127.0.0.1:18080..."
    openshell gateway remove openshift-poc 2>/dev/null || true
    openshell gateway add http://127.0.0.1:18080 --name openshift-poc
fi

# --- 12. Agent pods ---

info "Deploying agent pods..."

# Pod 1: kata-only -- raw pod, no OpenShell, just Kata runtime
info "  Creating opencode-kata-only (raw pod, Kata runtime)..."
sed "s|REGISTRY|${REGISTRY}|g" "${REPO_ROOT}/deploy/pod-kata-only.yaml" \
    | oc apply -f -

# Pod 2: openshell-only -- created via OpenShell gateway (no Kata)
# The gateway applies its supervisor, policy proxy, etc.
# defaultRuntimeClassName is empty, so this gets the default runtime (runc)
# --no-tty and "-- sleep infinity" prevent interactive shell
info "  Creating opencode-openshell-only (OpenShell sandbox, default runtime)..."
openshell sandbox create \
    --name opencode-openshell-only \
    --policy "${REPO_ROOT}/deploy/openshell-policy.yaml" \
    --no-tty \
    -- sleep infinity \
    || warn "openshell sandbox create failed for openshell-only"

# Pod 3: dual -- created via OpenShell gateway with Kata runtime
# Use --driver-config-json to explicitly request the kata RuntimeClass
info "  Creating opencode-dual (OpenShell sandbox + Kata runtime)..."
openshell sandbox create \
    --name opencode-dual \
    --policy "${REPO_ROOT}/deploy/openshell-policy.yaml" \
    --driver-config-json '{"kubernetes":{"pod":{"runtime_class_name":"kata"}}}' \
    --no-tty \
    -- sleep infinity \
    || warn "openshell sandbox create failed for dual"

# --- 13. Wait for pods ---

info "Waiting for agent pods to be ready..."
for pod in opencode-kata-only opencode-openshell-only opencode-dual; do
    oc wait --for=condition=Ready "pod/${pod}" \
        -n "${NAMESPACE}" --timeout=180s || warn "${pod} not ready"
done

# --- Done ---

echo ""
info "========================================="
info " Setup complete!"
info "========================================="
echo ""
info "Namespace:         ${NAMESPACE}"
info "OpenShell gateway: $(oc get pod -n ${NAMESPACE} -l app.kubernetes.io/name=openshell -o name 2>/dev/null || echo 'not found')"
info "Attacker listener: attacker-listener.${NAMESPACE}.svc:9999"
echo ""
info "Agent pods:"
oc get pods -n "${NAMESPACE}" -l app=opencode -o wide 2>/dev/null || true
echo ""
info "OpenShell sandboxes:"
openshell sandbox list 2>/dev/null || true
echo ""
info "Next step: ./demo/run-demo.sh"
