# Infrastructure Setup

## Prerequisites

- OpenShift cluster (OCP 4.16+) with at least one bare-metal worker
  node (required for Kata Containers' hardware virtualization)
- `oc` CLI logged in with cluster-admin privileges
- `helm` v3 installed
- `openshell` CLI installed (for sandbox creation)
- Container image registry accessible from the cluster (e.g., quay.io)

## 1. Verify Kernel Vulnerability

Before proceeding, confirm the worker nodes are running a kernel
vulnerable to CVE-2026-31431:

```bash
./infra/verify-kernel.sh
```

The script checks each worker node's kernel version against known
patched versions. The exploit requires a kernel that predates commit
`a664bf3d603d` (merged April 1, 2026).

## 2. Install Kata Containers (OpenShift Sandboxed Containers)

### Install the operator

```bash
# Install the operator subscription
oc apply -f infra/kata-operator.yaml

# Wait for the operator to be ready
oc wait --for=condition=Available deployment/controller-manager \
  -n openshift-sandboxed-containers-operator --timeout=300s

# Create KataConfig to install Kata on worker nodes
# This triggers a node reboot as it installs the Kata runtime
# The operator creates the 'kata' RuntimeClass automatically
oc apply -f infra/kata-runtimeclass.yaml
```

### Verify Kata installation

```bash
# Check RuntimeClass exists
oc get runtimeclass kata

# Test with a simple pod
oc run kata-test --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --restart=Never --overrides='{"spec":{"runtimeClassName":"kata"}}' \
  -- sleep 30

oc get pod kata-test -o jsonpath='{.spec.runtimeClassName}'
# Should output: kata

oc delete pod kata-test
```

### Patch Kata initramfs to add veth module

The default Kata initramfs shipped with OpenShift Sandboxed Containers
**lacks the `veth` driver**, which is required for OpenShell's network
namespace setup.

> **Note:** A MachineConfig approach (`kata-veth-machineconfig.yaml`)
> does NOT work on RHCOS 9.6 with composefs because the Kata dracut
> directory under `/usr` is read-only even after `ostree admin unlock`.

Use the DaemonSet approach instead, which unpacks the existing initramfs
from `/var/cache` (writable), adds the veth module, and repacks it:

```bash
oc apply -f infra/kata-veth-patch-job.yaml

# Wait for all pods to show Running (they sleep after patching)
oc get pods -n openshift-sandboxed-containers-operator -l app=kata-veth-patch

# Check logs to confirm success
oc logs -n openshift-sandboxed-containers-operator -l app=kata-veth-patch

# Clean up (one-shot job, no longer needed)
oc delete -f infra/kata-veth-patch-job.yaml
```

This patch does not survive node reboots (the `kata-osbuilder-generate`
service regenerates the initramfs from the unpatched dracut config on
boot). Re-run the DaemonSet after any node reboot.

`setup.sh` handles this step automatically.

## 3. Build and Push Container Images

```bash
export REGISTRY=quay.io/yourorg

# Build from repo root
docker build -f images/agent-sandbox/Dockerfile \
  -t $REGISTRY/openshell-poc-agent-sandbox:latest .

docker build -t $REGISTRY/openshell-poc-attacker-listener:latest \
  images/attacker-listener/

# Push (ensure repos are public or create pull secrets)
docker push $REGISTRY/openshell-poc-agent-sandbox:latest
docker push $REGISTRY/openshell-poc-attacker-listener:latest
```

## 4. Deploy Everything

Once Kata is installed (with veth patch) and images are pushed, a
single script deploys everything:

```bash
export REGISTRY=quay.io/yourorg
./demo/setup.sh
```

The script handles, in order:
1. Namespace creation
2. Agent Sandbox CRDs and controller
3. `openshell-kata` SCC creation and grants
4. OpenShell gateway install via Helm (with Kata-specific overrides)
5. JWT signing key generation (required because pkiInitJob is disabled)
6. Gateway readiness wait
7. ConfigMap creation from attack payload files
8. API key secret
9. Attacker listener deployment
10. Agent pod creation:
    - `opencode-kata-only`: raw Pod with `runtimeClassName: kata` (no OpenShell)
    - `opencode-openshell-only`: created via `openshell sandbox create` (has OpenShell, default runtime)
    - `opencode-dual`: created via `openshell sandbox create` (has OpenShell + Kata runtime via gateway default)
11. OpenShell network policy applied to protected sandboxes

To tear everything down:

```bash
./demo/teardown.sh
```

## Troubleshooting

### Kata pods stuck in ContainerCreating

- Verify the worker node has hardware virtualization enabled:
  `oc debug node/<node> -- grep -c vmx /proc/cpuinfo`
- Check that the veth module is in the Kata initramfs:
  `oc debug node/<node> -- chroot /host lsinitrd /var/cache/kata-containers/osbuilder-images/kata.initrd | grep veth`

### OpenShell gateway not starting

- Check pod logs: `oc logs -n openshell-poc statefulset/openshell`
- Verify SCC assignment: `oc get scc openshell-kata -o yaml | grep serviceaccount`
- Check JWT keys exist: `oc get secret openshell-jwt-keys -n openshell-poc`

### OpenShell sandbox creation fails

- Ensure the `openshell` CLI is registered with the gateway:
  `openshell status`
- If not registered, get the NodePort and register:
  `oc get svc openshell -n openshell-poc`
  `openshell gateway add http://<node-ip>:<node-port> --name openshift-kata`

### vLLM not reachable from pods

- Verify the service exists: `oc get svc -n vllm`
- Test DNS resolution from a pod: `nslookup gemma4-svc.vllm.svc.cluster.local`
