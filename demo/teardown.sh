#!/usr/bin/env bash
# teardown.sh -- Remove all PoC resources from the cluster
#
# Usage: ./demo/teardown.sh

set -euo pipefail

NAMESPACE="openshell-poc"

info()  { echo "==> $*"; }

info "Tearing down dual-protection PoC..."

# Delete OpenShell sandboxes
info "Deleting OpenShell sandboxes..."
for sandbox in opencode-openshell-only opencode-dual; do
    openshell sandbox delete "${sandbox}" -n "${NAMESPACE}" 2>/dev/null || true
done

# Delete raw agent pods
info "Deleting agent pods..."
oc delete pod -n "${NAMESPACE}" -l app=opencode --ignore-not-found

# Delete attacker listener
info "Deleting attacker listener..."
oc delete deployment,svc -n "${NAMESPACE}" -l app=attacker-listener --ignore-not-found

# Delete ConfigMaps and Secrets
info "Deleting ConfigMaps and Secrets..."
oc delete configmap malicious-patch -n "${NAMESPACE}" --ignore-not-found
oc delete secret opencode-api-keys -n "${NAMESPACE}" --ignore-not-found
oc delete secret openshell-jwt-keys -n "${NAMESPACE}" --ignore-not-found

# Uninstall OpenShell
info "Uninstalling OpenShell gateway..."
helm uninstall openshell -n "${NAMESPACE}" 2>/dev/null || true

# Remove SCC
info "Removing openshell-kata SCC..."
oc delete scc openshell-kata --ignore-not-found 2>/dev/null || true

# Delete Agent Sandbox CRDs (optional -- may affect other users)
# info "Deleting Agent Sandbox CRDs..."
# oc delete -f https://raw.githubusercontent.com/nvidia/openshell/main/deploy/kube/manifests/agent-sandbox.yaml 2>/dev/null || true

# Delete namespace
info "Deleting namespace ${NAMESPACE}..."
oc delete namespace "${NAMESPACE}" --ignore-not-found

echo ""
info "Teardown complete."
info "Note: Kata Containers operator, KataConfig, and Agent Sandbox CRDs"
info "are NOT removed. Remove them manually if needed:"
info "  oc delete kataconfig default"
info "  oc delete subscription sandboxed-containers-operator -n openshift-sandboxed-containers-operator"
