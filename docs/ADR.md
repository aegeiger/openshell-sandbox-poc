# Architecture Decision Record: OpenShell + Kata Dual-Protection PoC

> **Status:** APPROVED
> **Date:** 2026-06-09
> **Author:** OpenCode agent, directed by E Geiger
>
> **THIS DOCUMENT IS IMMUTABLE.** Do not edit without explicit approval from
> the user (E Geiger). If the user approves a change, note the date and
> rationale inline with a `> AMENDMENT (date): ...` block.

---

## 1. Context and Goal

We are building a proof-of-concept demonstrating that running an AI coding
agent (OpenCode) inside the dual protection of **NVIDIA OpenShell** and
**Kata Containers** provides defense-in-depth that neither technology
achieves alone.

The demo runs on an **OpenShift** cluster (IBM Cloud) with one bare-metal
worker node. Three pods run real OpenCode backed by a local **vLLM** serving
**Gemma4-31b**. Two attacks are executed against all three pods, producing a
results matrix that shows the dual-protected pod blocking both.

---

## 2. Pod Matrix

| Pod Name                 | RuntimeClass       | OpenShell | Kata | Purpose                          |
|--------------------------|--------------------|-----------|------|----------------------------------|
| `opencode-kata-only`     | `kata-containers`  | No        | Yes  | Shows Kata alone                 |
| `opencode-openshell-only`| default (runc/crun)| Yes       | No   | Shows OpenShell alone            |
| `opencode-dual`          | `kata-containers`  | Yes       | Yes  | Shows dual protection            |

All three pods run the same container image with the same OpenCode
configuration pointing at the same vLLM endpoint.

---

## 3. Security Boundary Model

### 3.1 What OpenShell Protects Against (Application Layer)

OpenShell enforces policy at the application layer:

- **Network egress proxy:** All outbound connections routed through a policy
  proxy that evaluates destination, port, calling binary, and optional L7
  HTTP method/path rules. Default deny.
- **Filesystem (Landlock):** Restricts read/write to declared paths, locked
  at sandbox creation.
- **Process isolation:** Agent runs as unprivileged user with reduced
  capabilities.
- **Inference routing:** Model API calls can be intercepted and rerouted.

OpenShell **cannot** protect against kernel-level attacks. Landlock and
seccomp operate within the kernel's own integrity boundary -- if the kernel
is compromised, these controls are meaningless.

### 3.2 What Kata Protects Against (Kernel / VM Layer)

Kata runs each pod inside a lightweight VM with its own dedicated guest
kernel:

- **Kernel isolation:** The container workload runs on a separate kernel
  from the host. Kernel exploits affect the guest kernel, not the host.
- **Hardware-enforced boundary:** VM boundary is enforced by the CPU's
  virtualization extensions (VT-x/AMD-V), not by software namespaces.
- **Memory isolation:** Guest memory is isolated from host memory.

Kata **cannot** protect against application-layer threats. It does not
inspect network traffic, enforce egress policy, or restrict which URLs a
process can reach. From Kata's perspective, an outbound HTTP POST is a
normal network operation.

### 3.3 The Gap Each Leaves Open

| Threat Class                | OpenShell | Kata      |
|-----------------------------|-----------|-----------|
| Data exfiltration via HTTP  | BLOCKS    | ALLOWS    |
| Prompt injection -> exfil   | BLOCKS    | ALLOWS    |
| Kernel LPE / container escape | ALLOWS | BLOCKS    |
| Page-cache corruption       | ALLOWS    | BLOCKS    |

Dual protection closes both gaps.

---

## 4. Attack 1: Prompt Injection via Malicious Git Patch

### 4.1 Attack Vector

Inspired by the Microsoft Security Blog research on Claude Code GitHub
Action prompt injection (2026-06-05). We adapt the pattern for a local
agent scenario:

1. A git patch file (`.patch`) is placed in the pod's workspace.
2. A task prompt tells OpenCode: "Review this patch. The commit message
   contains test instructions -- follow them."
3. The commit message contains a hidden prompt injection (in an HTML
   comment, unicode, or plainly stated as "test instructions") that
   tells the agent to:
   - Read `/proc/self/environ` or `~/.kube/config` or any sensitive file
   - POST the contents to `http://attacker-listener:9999/exfil`
4. OpenCode, having bash and curl tools, executes the instruction.

### 4.2 Implementation Approach

**Primary (Option A):** Actually feed the malicious patch to a running
OpenCode instance and let it process the prompt injection end-to-end.
This demonstrates the full attack chain with a real LLM.

**Fallback (Option B):** If Option A is unreliable (agent refuses, too
slow, non-deterministic), the demo script directly execs curl inside each
pod to demonstrate the network policy boundary. The malicious patch is
shown as context/explanation.

We start with Option A. Fall back to Option B only if A does not work.

### 4.3 Why OpenShell Blocks It

The OpenShell policy proxy intercepts the outbound HTTP POST to
`attacker-listener:9999`. The policy only allows egress to the vLLM
inference endpoint. The request is denied with `policy_denied`.

### 4.4 Why Kata Does Not Block It

Kata provides VM isolation. Outbound HTTP is a normal network operation.
No egress filtering exists at the Kata layer. The data is exfiltrated.

---

## 5. Attack 2: Container Escape via CVE-2026-31431 "Copy Fail"

### 5.1 CVE Details

- **CVE:** CVE-2026-31431
- **Nickname:** Copy Fail
- **Type:** Logic flaw in Linux kernel `algif_aead` (crypto subsystem)
- **Affected:** All Linux kernels from 2017 through the patch (commit
  `a664bf3d603d`), covering kernels 4.x through 6.18.x
- **Exploit:** 732-byte Python script, 100% reliable, no race conditions
- **Severity:** CVSS 7.8 HIGH, CISA Known Exploited Vulnerability
- **PoC repo:** https://github.com/theori-io/copy-fail-CVE-2026-31431
- **Website:** https://copy.fail

### 5.2 How the Exploit Works

1. Opens an `AF_ALG` socket (kernel crypto API userspace interface)
2. Exploits a logic flaw in `authencesn` to get writable access to a
   page-cache page backing a setuid binary (`/usr/bin/su`)
3. Writes 4 bytes to corrupt the binary's ELF header in a way that
   grants the caller root
4. Running `su` after the exploit gives a root shell

> AMENDMENT (2026-06-11): In the demo, we use a modified exploit
> (`escape_demo.py`) that targets `/opt/marker.txt` instead of
> `/usr/bin/su`. This demonstrates the **page-cache escape** primitive
> rather than privilege escalation:
>
> 1. Opens `/opt/marker.txt` read-only (file contains `INTACT`)
> 2. Uses the Copy Fail primitive to write `PWN!` to offset 0
> 3. On runc (overlayfs), the page-cache corruption is visible to
>    OTHER containers sharing the same image layer -- proving a
>    container escape (cross-container data corruption)
> 4. On Kata (virtiofs), the page cache is per-VM, so the corruption
>    is invisible to other containers -- CONTAINED
>
> This approach works through `openshell sandbox exec` (with all
> OpenShell protections active), proving that Landlock, seccomp,
> `no_new_privs`, and the network proxy cannot prevent kernel-level
> page-cache corruption. A verification pod launched from the same
> image on the same node confirms whether the corruption escaped.

### 5.3 Why This CVE Over CVE-2024-1086

| Criterion               | CVE-2024-1086      | CVE-2026-31431     |
|--------------------------|--------------------|--------------------|
| Age                      | 2024 (2+ years old)| April 2026 (fresh) |
| Reliability              | 99.4% (has races)  | 100% (logic flaw)  |
| Exploit size             | C binary, ~5KB     | 732 bytes Python   |
| Needs netfilter/nftables | Yes                | No (uses AF_ALG)   |
| Works in OpenShift pod   | Unlikely (SCC)     | Very likely         |
| CISA KEV                 | Yes                | Yes                |
| Compilation needed       | Yes (gcc/make)     | No (pure Python)   |

CVE-2026-31431 is strictly superior for this demo.

### 5.4 Why OpenShell Does Not Block It

The exploit operates entirely within the kernel:
- `AF_ALG` sockets are legitimate syscalls used by crypto libraries
- Seccomp cannot reasonably block `socket(AF_ALG)` without breaking
  normal crypto operations
- Landlock restricts filesystem paths but not kernel memory operations
- The policy proxy only intercepts network egress, not local syscalls
- `no_new_privs` blocks setuid-based privilege escalation, but does
  NOT prevent the underlying page-cache write primitive

### 5.5 Why Kata Blocks It

Kata runs each pod inside a VM with its own kernel and filesystem:
- The container filesystem uses **virtiofs** (FUSE), which has a
  separate page cache from the host
- The `splice()` + `AF_ALG` chain operates on the **guest kernel's**
  page cache, not the host's
- Page-cache corruption stays inside the VM and is invisible to
  other containers on the host
- The host kernel and its page cache are never touched

### 5.6 Kernel Version Requirement

The OpenShift worker node must run a kernel that **has not** been patched
for CVE-2026-31431 (i.e., missing commit `a664bf3d603d`). This needs
verification:

- OCP 4.16: RHCOS kernel 5.14.0-427.x -- likely vulnerable
- OCP 4.17: RHCOS kernel 6.12.x -- check patch status
- OCP 4.18: RHCOS kernel 6.12.x -- check patch status

Run `verify-kernel.sh` on the node before the demo.

> AMENDMENT (2026-06-09): VERIFIED VULNERABLE. The cluster runs OCP 4.21
> with RHCOS 9.6. All worker nodes run kernel `5.14.0-570.103.1.el9_6`,
> built **March 24, 2026** -- one week before the fix was committed to
> mainline (April 1, 2026). The kernel changelog has zero mentions of
> CVE-2026-31431 or algif_aead fixes. Furthermore, `algif_aead` is
> **builtin** (not a loadable module), meaning the vulnerable code is
> always present and cannot be mitigated by `rmmod`. This strengthens
> the demo narrative: you cannot module-unload your way out of this;
> you need Kata's VM boundary.

---

## 6. Infrastructure Decisions

### 6.1 OpenShift on IBM Cloud

- **Why OpenShift:** User's existing environment is OpenShift on IBM Cloud.
- **Why bare metal worker:** Kata Containers requires hardware
  virtualization (VT-x/AMD-V). Bare metal workers expose this directly.
  VM-based workers may or may not support nested virtualization depending
  on the IBM Cloud instance type.
- **Recommended worker:** `bx3d-metal-96x384` or smallest available
  bare-metal flavor. Alternatively, a `bx2-16x64` VM with nested
  virtualization enabled if bare metal is unavailable.

> AMENDMENT (2026-06-09): Cluster is OCP 4.21 (k8s v1.34.5), RHCOS 9.6
> (Plow). 3 master nodes + 3 worker nodes, all running kernel
> `5.14.0-570.103.1.el9_6`, CRI-O 1.34.6. Three workers available.
> Need to verify whether existing workers support nested virtualization
> for Kata, or if a bare-metal worker needs to be added.

### 6.2 Kata Containers on OpenShift

Kata is installed via the **OpenShift Sandboxed Containers operator**
(based on Kata Containers), which is Red Hat's supported path for running
Kata on OCP. This creates a `kata` RuntimeClass automatically.

Alternatively, we can install Kata Containers directly via upstream
manifests if the operator is not available.

### 6.3 OpenShell on OpenShift

OpenShell is deployed via its Helm chart with OpenShift-specific overrides:
```yaml
server:
  disableTls: true
podSecurityContext:
  fsGroup: null
securityContext:
  runAsUser: null
```

The SCC `privileged` must be granted to the `openshell-sandbox` service
account in the namespace.

### 6.4 vLLM / Model

- **Model:** Gemma4-31b
- **Serving:** vLLM, provided externally by the user
- **Endpoint:** User will provide the URL
- **OpenCode config:** Points at the vLLM endpoint using OpenAI-compatible
  API format

> AMENDMENT (2026-06-09): vLLM is deployed cluster-internally in the
> `vllm` namespace. Service: `gemma4-svc.vllm.svc.cluster.local:8000`.
> Model ID returned by `/v1/models`: `gemma4-31b`. OpenAI-compatible API
> confirmed working. No external route exists -- ClusterIP only. The
> pods will reach vLLM via in-cluster DNS. The OpenShell policy must
> allowlist `gemma4-svc.vllm.svc.cluster.local` port `8000`.

### 6.5 Attacker Listener

A simple Python HTTP server running in a pod within the cluster (or
externally). It logs all received POST requests to stdout so we can
verify whether exfiltration succeeded.

---

## 7. Repo Structure

```
openshell-sandbox-poc/
├── AGENTS.md                              # Agent instructions (self-reference)
├── README.md                              # Project overview for humans
├── LICENSE                                # MIT (existing)
│
├── docs/
│   ├── ADR.md                             # THIS FILE - immutable
│   ├── PLAN.md                            # Implementation plan with status tracking
│   ├── security-model.md                  # Detailed security boundary explanation
│   └── architecture.md                    # Mermaid diagrams of the full setup
│
├── infra/                                 # Cluster and node setup
│   ├── README.md                          # Step-by-step setup instructions
│   ├── kata-operator.yaml                 # OpenShift Sandboxed Containers operator
│   ├── kata-runtimeclass.yaml             # KataConfig CR
│   ├── kata-veth-machineconfig.yaml       # MachineConfig for veth (did not work on composefs)
│   ├── kata-veth-patch-job.yaml           # DaemonSet to patch Kata initramfs for veth
│   └── verify-kernel.sh                   # Check CVE-2026-31431 vulnerability
│
├── deploy/                                # Kubernetes manifests
│   ├── namespace.yaml                     # Namespace: openshell-poc
│   ├── openshell-helm-values.yaml         # Helm values for OpenShell on OCP
│   ├── openshell-policy.yaml              # OpenShell network policy YAML
│   ├── openshell-scc.yaml                 # Targeted SCC for OpenShell + Kata
│   │
│   ├── pod-kata-only.yaml                 # Pod: Kata runtime, no OpenShell
│   │                                      # (openshell-only and dual pods created
│   │                                      #  via 'openshell sandbox create')
│   │
│   ├── attacker-listener.yaml             # HTTP listener deployment + service
│   └── secret-api-keys.yaml.example       # Template for user-provided secrets
│
├── images/                                # Container image definitions
│   ├── agent-sandbox/
│   │   ├── Dockerfile                     # OpenCode + Python3 + curl + exploit
│   │   └── opencode.json                  # OpenCode config for vLLM
│   └── attacker-listener/
│       ├── Dockerfile                     # Python HTTP listener
│       └── listener.py                    # Logs POST bodies to stdout
│
├── attacks/                               # Attack payloads and documentation
│   ├── README.md                          # Safety disclaimers
│   ├── attack1-prompt-injection/
│   │   ├── malicious.patch                # Git patch with hidden injection
│   │   ├── task-prompt.txt                # Task given to OpenCode
│   │   └── README.md                      # Attack 1 explanation
│   └── attack2-container-escape/
│       ├── copy_fail_exp.py               # CVE-2026-31431 PoC (732 bytes)
│       ├── verify-escape.sh               # Post-exploit host access check
│       └── README.md                      # Attack 2 explanation
│
└── demo/                                  # Demo automation
    ├── run-demo.sh                        # Main demo: both attacks, all 3 pods
    ├── setup.sh                           # Deploy namespace, gateway, pods
    ├── teardown.sh                        # Clean up everything
    └── lib/
        ├── colors.sh                      # Terminal colors/formatting
        └── utils.sh                       # Shared helper functions
```

> AMENDMENT (2026-06-09): Removed three files from the repo structure:
> - `deploy/configmap-opencode.yaml` -- OpenCode config is baked into
>   the Docker image via `images/agent-sandbox/opencode.json`. No pod
>   manifests referenced this ConfigMap.
> - `deploy/configmap-malicious-patch.yaml` -- ConfigMap is now created
>   imperatively by `demo/setup.sh` from the source files in `attacks/`,
>   avoiding content duplication.
> - `images/agent-sandbox/copy_fail_exp.py` -- Duplicate of the exploit
>   in `attacks/attack2-container-escape/`. The Dockerfile builds from
>   the repo root and COPYs from `attacks/` directly.
>
> AMENDMENT (2026-06-11): Major deployment design changes based on the
> OpenShell OSC integration guide and deployment experience:
>
> - `deploy/pod-openshell-only.yaml` and `deploy/pod-dual.yaml` removed.
>   These pods must be created via `openshell sandbox create` to get the
>   supervisor + policy proxy. Only `pod-kata-only.yaml` remains as a
>   raw manifest (it intentionally has no OpenShell protection).
> - `deploy/openshell-scc.yaml` added -- targeted `openshell-kata` SCC
>   replacing the blanket `privileged` SCC grant.
> - `infra/kata-veth-machineconfig.yaml` added but does NOT work on
>   RHCOS 9.6 with composefs (the /usr path is read-only even after
>   ostree admin unlock --hotfix).
> - `infra/kata-veth-patch-job.yaml` added -- DaemonSet that patches the
>   Kata initramfs via hostPath + chroot. This is the working approach.
> - RuntimeClass name is `kata` (not `kata-containers`).
> - `defaultRuntimeClassName` is empty in Helm values. The dual pod gets
>   `kata` via `--driver-config-json` at sandbox creation time. This
>   avoids forcing Kata on the openshell-only pod.
> - Gateway is a StatefulSet, not a Deployment.
> - `pkiInitJob` is disabled; JWT keys are generated locally via
>   `openshell-gateway generate-certs --output-dir` and uploaded as a
>   Secret before the gateway starts.
> - `setup.sh` manages a port-forward to the gateway for `openshell`
>   CLI communication.

---

## 8. Demo Script Flow

```
run-demo.sh:

1. Print banner and introduction
2. Start port-forward to OpenShell gateway (for openshell sandbox exec)
3. Verify prerequisites:
   - 3 pods running and ready
   - Attacker listener running

4. === ATTACK 1: PROMPT INJECTION ===
   For each pod in (kata-only, openshell-only, dual):
     a. Execute curl to attacker-listener via pod_exec
        (openshell sandbox exec for protected pods, oc exec for kata-only)
     b. Check if OpenShell policy proxy blocked the request (policy_denied)
     c. Check attacker-listener logs for received data
     d. Record result: DATA LEAKED | BLOCKED

5. === ATTACK 2: CONTAINER ESCAPE (CVE-2026-31431) ===
   For each pod in (kata-only, openshell-only, dual):
     a. Drop host page cache (clean state between tests)
     b. Read /opt/marker.txt (should show "INTACT")
     c. Run python3 /opt/escape_demo.py via pod_exec
        (writes "PWN!" to marker.txt page cache)
     d. Read /opt/marker.txt inside pod (shows if local corruption worked)
     e. Launch a verification pod (same image, same node, runc)
     f. Read /opt/marker.txt in verification pod
        - "PWN!" visible = corruption escaped the container = HOST COMPROMISED
        - "INTACT" = corruption contained in VM = CONTAINED
     g. Delete verification pod

6. Print final results matrix (ASCII table)
7. Print conclusion
```

---

## 9. Open Questions (To Be Resolved During Implementation)

1. ~~**AF_ALG sockets in OpenShift SCC:**~~ **RESOLVED.**
   > AMENDMENT (2026-06-11): Not yet tested with the exploit, but AF_ALG
   > sockets are standard kernel functionality. The `openshell-kata` SCC
   > does not restrict socket types. Will verify during attack testing.

2. ~~**RHCOS kernel patch status:**~~ **RESOLVED.**
   > AMENDMENT (2026-06-09): Kernel `5.14.0-570.103.1.el9_6` (built
   > 2026-03-24) is VULNERABLE. Pre-dates the fix by one week. All six
   > nodes (3 masters, 3 workers) run the same kernel. The `algif_aead`
   > module is builtin. No MachineConfig pinning is needed.

3. ~~**OpenShell + Kata interaction:**~~ **RESOLVED.**
   > AMENDMENT (2026-06-11): Works, but with caveats:
   > - `defaultRuntimeClassName` must be empty (not `kata`) in Helm values,
   >   otherwise ALL sandboxes get Kata including the openshell-only pod.
   > - The dual pod gets Kata via `--driver-config-json` at creation time:
   >   `'{"kubernetes":{"pod":{"runtime_class_name":"kata"}}}'`
   > - The Kata initramfs needs the `veth` module for OpenShell networking.
   >   MachineConfig file drops don't work on RHCOS 9.6 composefs.
   >   Use `infra/kata-veth-patch-job.yaml` (DaemonSet with hostPath +
   >   chroot) to patch the initramfs post-install.
   > - `pkiInitJob` must be disabled; JWT keys generated locally.
   > - Gateway runs as StatefulSet, not Deployment.

4. **Prompt injection reliability:** Will OpenCode (backed by Gemma4-31b)
   reliably follow the hidden prompt injection in the patch file? The
   injection needs careful crafting. May need iteration.

5. ~~**OpenShell K8s compute driver maturity:**~~ **RESOLVED.**
   > AMENDMENT (2026-06-11): Rough edges confirmed. Key issues encountered:
   > - `openshell sandbox create` opens an interactive shell by default;
   >   must use `--no-tty -- sleep infinity` in scripts.
   > - CLI uses `-g`/`--gateway` not `-n`/`--namespace` for targeting.
   > - Gateway must be reachable via port-forward if NodePort is blocked.
   > - The `--driver-config-json` flag is experimental but works for
   >   setting `runtime_class_name`.

6. ~~**vLLM endpoint networking:**~~ **RESOLVED.**
   > AMENDMENT (2026-06-09): vLLM runs cluster-internally at
   > `gemma4-svc.vllm.svc.cluster.local:8000` (ClusterIP, no route).
   > Model ID: `gemma4-31b`. Pods reach it via in-cluster DNS. The
   > OpenShell policy will allowlist this endpoint.

---

## 10. Non-Goals

- We are NOT building a production deployment of OpenShell or Kata.
- We are NOT testing every possible attack vector -- just two
  representative ones from different threat classes.
- We are NOT evaluating performance overhead of Kata or OpenShell.
- We are NOT running this on multiple architectures -- x86_64 only.
- We are NOT automating cluster provisioning (that's manual/pre-existing).
