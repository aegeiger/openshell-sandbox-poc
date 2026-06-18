# Abstract: Defense in Depth for AI Coding Agents (2-Part Series)

## Thesis

AI coding agents execute arbitrary code from natural-language instructions, exposing them to two distinct threat classes that no single technology addresses: application-layer data exfiltration (via prompt injection) and kernel-level container escape (via unpatched CVEs). Running NVIDIA OpenShell and Kata Containers together on Red Hat OpenShift provides defense-in-depth that blocks both.

## Target Audience

Platform engineers, security architects, and IT decision-makers evaluating how to safely run AI coding agents in Kubernetes/OpenShift environments.

## Blog Type

Red Hat Blog (thought leadership + security architecture narrative, not a step-by-step tutorial)

## Key Points (3 maximum)

1. **Two threat classes, two protection layers.** OpenShell enforces application-layer policy (egress filtering, filesystem isolation, process sandboxing) but can't stop kernel bugs. Kata Containers provides VM-level kernel isolation but doesn't inspect network traffic. Each leaves a gap the other fills.

2. **Real attacks, not theory.** We demonstrate both gaps with real exploits on a live OpenShift cluster: a prompt injection that exfiltrates environment variables, and CVE-2026-31431 "Copy Fail" (a 732-byte Python exploit, 100% reliable, CISA KEV listed) that corrupts page cache across container boundaries.

3. **The results matrix tells the story.** Three identically configured OpenCode pods -- one with only Kata, one with only OpenShell, one with both. Each attack succeeds against the pod missing its corresponding protection. Only the dual-protected pod blocks both.

## Products/Projects

- Red Hat OpenShift (4.21)
- OpenShift sandboxed containers (Kata Containers)
- NVIDIA OpenShell
- OpenCode (AI coding agent)
- vLLM serving Gemma4-31b (inference backend)

## CTA

Explore the [OpenShell GitHub repo](https://github.com/NVIDIA/OpenShell) and try [OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers) for your AI agent workloads.

## Source Materials

- `docs/ADR.md` -- Architecture decision record (source of truth for design)
- `docs/security-model.md` -- Security boundary explanation
- `docs/architecture.md` -- Mermaid diagrams of cluster/pod/attack flows
- `docs/run.log` -- Actual demo output from a live OpenShift 4.21 run
- `attacks/attack1-prompt-injection/README.md` -- Attack 1 details
- `attacks/attack2-container-escape/README.md` -- Attack 2 details
- `attacks/attack2-container-escape/escape_demo.py` -- The exploit code
- `deploy/openshell-policy.yaml` -- The OpenShell network policy

**Contradiction handling:** If ADR, attack READMEs, or run.log disagree on specifics, flag the contradiction for the author rather than silently resolving it.

## Series Structure

### Part 1: The Security Architecture Story (~1300-1500 words)

**Title (working):** Your AI coding agent has two blind spots -- here's how to close both

**Story arc:** Problem → Why it's hard → What OpenShell does → What Kata does → The gap each leaves → Why you need both → The results matrix (foreshadowing Part 2)

**Proposed sections:**
- H2: AI agents run code from instructions they can't fully trust
- H2: OpenShell: locking down what the agent can reach
- H2: Kata Containers: isolating the kernel itself
- H2: The gap neither closes alone
- H2: Dual protection: closing both gaps on OpenShift
- H2: What happens when you test it (bridge to Part 2)

### Part 2: The Play-by-Play Demo Story (~1300-1500 words)

**Title (working):** We attacked three AI agent pods -- here's exactly what happened

**Story arc:** Setup → Attack 1 (prompt injection, three pods) → Attack 2 (CVE-2026-31431, three pods) → Results matrix → What it means

**Proposed sections:**
- H2: Three pods, three protection configurations
- H2: Attack 1: prompt injection exfiltration
- H2: Attack 2: CVE-2026-31431 container escape
- H2: The results matrix
- H2: What this means for your AI agent deployments

## Series Context

- Part 1 of 2. Part 1 is the architecture/reasoning story. Part 2 is the evidence/demo story.
- Part 1 should stand alone for readers who only want the "why."
- Part 2 should reference Part 1 but also be readable independently by including a brief setup recap.

## Timing

No specific event tie-in. CVE-2026-31431 was disclosed April 2026 and added to CISA KEV May 2026, making it topical.

---

## Blog Qualifying Summary

- **Blog type**: Red Hat Blog
- **Thesis**: AI coding agents face two distinct threat classes -- application-layer exfiltration and kernel-level escape -- and neither OpenShell nor Kata alone covers both; dual protection on OpenShift blocks both
- **Audience**: Platform engineers, security architects, IT decision-makers
- **Products**: Red Hat OpenShift, OpenShift sandboxed containers, NVIDIA OpenShell, OpenCode, vLLM/Gemma4-31b
- **Domain path**: docs/blogs/cross-cutting/openshell-kata-dual-protection/
- **Source material**: ADR, security model, architecture diagrams, attack READMs, demo run.log, exploit code, OpenShell policy
- **Demo**: Yes -- 3 OpenCode pods on OpenShift, 2 real attacks, 2x3 results matrix
- **Series**: Part 1 of 2 (architecture story + play-by-play demo)
- **CTA**: Explore OpenShell GitHub, try OpenShift sandboxed containers
- **Timing**: None (CVE-2026-31431 is topical, disclosed April 2026)
