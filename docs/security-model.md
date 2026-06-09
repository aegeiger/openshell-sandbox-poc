# Security Boundary Model

This document explains why neither OpenShell nor Kata Containers alone
covers all threat classes when running AI coding agents, and why the
combination provides defense in depth.

## Two Layers, Two Threat Classes

### OpenShell: Application-Layer Defense

NVIDIA OpenShell wraps each agent sandbox in a policy-enforced runtime:

- **Network egress proxy** -- All outbound connections route through a
  proxy that evaluates destination, port, calling binary, and optional
  L7 HTTP method/path rules. Default posture is deny-all.
- **Filesystem isolation (Landlock)** -- Kernel-enforced read/write
  restrictions on filesystem paths, locked at sandbox creation.
- **Process isolation** -- The agent runs as an unprivileged user with
  dropped capabilities. No privilege escalation via the process model.
- **Inference routing** -- Model API calls can be intercepted and
  rerouted through managed endpoints.

**What it blocks:** Data exfiltration via HTTP/HTTPS, unauthorized API
calls, filesystem access outside declared paths, credential leakage
through network channels.

**What it cannot block:** Kernel-level exploits. Landlock and seccomp
operate within the kernel's integrity boundary. If an attacker corrupts
kernel memory (e.g., via a page-cache write bug), these controls are
bypassed entirely. The policy proxy cannot intercept syscalls that
operate below the network stack.

### Kata Containers: Kernel-Layer Defense

Kata Containers runs each pod inside a lightweight virtual machine with
its own dedicated guest kernel:

- **Separate kernel** -- The workload interacts with a guest kernel, not
  the host kernel. Kernel exploits affect only the guest.
- **Hardware-enforced isolation** -- The VM boundary is enforced by
  CPU virtualization extensions (VT-x / AMD-V), not by Linux namespaces
  or cgroups.
- **Memory isolation** -- Guest memory is isolated from host memory.
  Page-cache corruption stays within the VM.

**What it blocks:** Container escape exploits, kernel privilege
escalation, page-cache corruption attacks, /proc-based host access.

**What it cannot block:** Application-layer threats. Kata does not
inspect network traffic, enforce egress policies, or restrict which
URLs a process can reach. From Kata's perspective, `curl http://evil/`
is a perfectly normal network operation.

## The Gap Matrix

| Threat                          | OpenShell | Kata      | Both      |
|---------------------------------|-----------|-----------|-----------|
| Data exfiltration via HTTP      | BLOCKS    | allows    | BLOCKS    |
| Prompt injection leading to exfil| BLOCKS   | allows    | BLOCKS    |
| Kernel LPE (CVE-2026-31431)    | allows    | BLOCKS    | BLOCKS    |
| Page-cache write to setuid binary| allows   | BLOCKS    | BLOCKS    |
| Host filesystem read via /proc  | allows    | BLOCKS    | BLOCKS    |

## Why This Matters for AI Agents

AI agents execute code from natural-language instructions. This makes
them vulnerable to both threat classes simultaneously:

1. **Prompt injection** -- Untrusted input (a malicious git patch, an
   issue comment, a PR description) can contain hidden instructions
   that steer the agent toward exfiltrating secrets. This is an
   application-layer attack that OpenShell's network policy blocks.

2. **Compromised dependencies** -- The agent may run code that exploits
   a kernel vulnerability. Since agents routinely execute `pip install`,
   `npm install`, `make`, and arbitrary shell commands, the kernel
   attack surface is directly exposed. Kata's VM boundary contains this.

Running an agent with only one protection layer leaves a gap that a
sophisticated attacker can exploit. Dual protection closes both gaps.
