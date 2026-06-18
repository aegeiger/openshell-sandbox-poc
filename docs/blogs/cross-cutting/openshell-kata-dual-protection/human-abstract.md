# Abstract: Defence in Depth for AI Coding Agents (2-Part Series)

## Thesis

AI Coding agents are taking known and existing security challenges and make them more profound. In
order to achieve their goal they must be granted a certain degree of freedom to run almost arbitrary
code, which emphasizes concerns such as secrets keeping and sharing resources with other workloads.
Different tools address different challenges in this stack. To get the best protection, an approach
of defence in depth using a combination of tools should be taken. Using Open Shell to protect
network access and Open Shift Sandboxed Containers to protect shared resources, we are able to ward
off attacks we couldn't using just one solution.

## Target Audience

Security architects, platform engineers, and IT decision-makers evaluating how to safely run AI coding agents in Kubernetes/OpenShift environments.

## Blog Type

Two part series;
1. Security architecture narrative, thought leadership
2. Step-by-step tutorial

## Key Points

1. **Two threat classes, two protection layers.** OpenShell enforces application-layer policy (egress
   filtering, filesystem isolation, process sandboxing) but can't stop kernel bugs. Open Shift
   Sandboxed Containers provides VM-level kernel isolation but doesn't inspect network traffic. Each
   leaves a gap the other fills.

2. **Real attacks, not theory.** We demonstrate both gaps with real exploits on a live Open Shift 
   cluster: a prompt injection that exfiltrates environment variables inspired by a real report from
   Microsoft, and a slight modification of CVE-2026-31431 "Copy Fail" (a 100% reliable exploit, CISA
   KEV listed) that corrupts page cache across container boundaries. Both of them reported within the
   last 3 months, demonstrating the risk is real.

3. **The results matrix tells the story.** Three identically configured OpenCode pods -- one with 
   only Open Shift Sandboxed Containers, one with only OpenShell, one with both. Each attack succeeds
   against the pod missing its corresponding protection. Only the dual-protected pod blocks both.   
   
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

### Part 1: The Security Architecture Story

**Title (working)** One Sandbox Is Not Enough: Defence In Depth For AI Agents

**Story arc:** Problem → Why it's hard → What OpenShell does → What Kata does → The gap each leaves → Why you need both → The results matrix (foreshadowing Part 2)

**Proposed sections:**
- H2: AI agents essentially run arbitrary code
- H2: OpenShell: the exoskeleton protecting your agents, and more importantly, your secrets
- H2: Kata Containers: isolating the kernel itself
- H2: The gap neither closes alone
- H2: Dual protection: closing both gaps on OpenShift
- H2: What happens when you test it (bridge to Part 2)

### Part 2: The Play-by-Play Demo Story

**Title (working)** Real World Attacks Meeting Real Sandboxes

**Story arc** Setup  → Attack 1 (prompt injection, three pods) → Attack 2 (CVE-2026-31431, three pods) → Results matrix → What it means

**Proposed sections:**
- H2: Three pods, three protection configurations
- H2: Attack 1: prompt injection exfiltration
- H3: Why Open Shell protects against this attack and Open Shift Sandboxed Containers does not
- H2: Attack 2: CVE-2026-31431 container escape
- H3: Why OpenShift sandboxed containers protects against this attack and OpenShell does not
- H2: The results matrix
- H2: What this means for your AI agent deployments

## Series Context

- Part 1 of 2. Part 1 is the architecture/reasoning story. Part 2 is the evidence/demo story.
- Part 1 should stand alone for readers who only want the "why."
- Part 2 should reference Part 1 but also be readable independently by including a brief setup recap.

## Timing

No specific event tie-in. CVE-2026-31431 was disclosed April 2026 and added to CISA KEV May 2026, making it topical.
