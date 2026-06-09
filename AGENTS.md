# Agent Instructions

> These instructions are for AI coding agents (OpenCode, Claude, Copilot,
> etc.) working on this repository. Read this file in full before making
> any changes.

---

## Mandatory Pre-Work: Read These Files First

Before starting ANY implementation work, you MUST read:

1. **`docs/ADR.md`** -- The architecture decision record. This defines
   the repo structure, the attacks, the pod matrix, the security model,
   and all design decisions. Every file you create must conform to it.

2. **`docs/PLAN.md`** -- The implementation plan with task status tracking.
   Find which task you are working on. Update its status when you start
   (`[>]`) and when you finish (`[x]`).

If you have not read both files, STOP and read them now.

---

## Rules

### Rule 1: The ADR Is Immutable

`docs/ADR.md` is the source of truth. You MUST NOT edit it unless the
user (E Geiger) explicitly tells you to. If you believe something in the
ADR is wrong or needs updating, ASK the user. Do not silently diverge.

This means:
- Do not rename files or directories away from the structure in ADR
  Section 7 without user approval.
- Do not change the attack strategy described in ADR Sections 4-5.
- Do not change the pod matrix in ADR Section 2.
- Do not change infrastructure decisions in ADR Section 6.

If you find yourself thinking "the ADR says X but I think Y is better,"
STOP and ask the user.

### Rule 2: Update the Plan, Don't Rewrite It

`docs/PLAN.md` tracks implementation progress. When you work on a task:

- Mark it `[>]` (in progress) when you start.
- Mark it `[x]` (done) when you finish.
- If a task is blocked, mark it `[-]` and add a note explaining why.

You MUST NOT:
- Add new tasks without user approval.
- Remove tasks without user approval.
- Reorder tasks without user approval.
- Change task descriptions without user approval.

You CAN update the "Notes" section at the bottom of PLAN.md to record
discoveries, blockers, or decisions made during implementation.

### Rule 3: Don't Hallucinate APIs or Features

This project integrates two real products:
- **NVIDIA OpenShell** (https://github.com/NVIDIA/OpenShell) -- alpha
  software, Kubernetes support is experimental.
- **Kata Containers** (https://github.com/kata-containers/kata-containers)

When writing manifests or configuration:
- Reference the actual OpenShell Helm chart values from `deploy/helm/openshell/values.yaml`
  in the upstream repo. Do not invent Helm values that don't exist.
- Reference the actual Kata Containers RuntimeClass spec. Do not invent
  fields.
- Reference the actual OpenShift Sandboxed Containers operator if using
  the Red Hat path.

If you are unsure about an API or configuration field, say so. Do not
guess.

### Rule 4: Placeholders for User-Provided Values

The following values are provided by the user at deploy time. Use these
exact placeholder strings everywhere:

| Placeholder                   | Meaning                              |
|-------------------------------|--------------------------------------|
| `VLLM_ENDPOINT`               | vLLM base URL for Gemma4-31b        |
| `REGISTRY`                    | Container image registry             |
| `OPENSHIFT_API`               | OpenShift API server URL             |
| `ATTACKER_LISTENER_URL`       | URL of the exfiltration listener     |

Do not hardcode real URLs, registries, or credentials.

### Rule 5: Security and Safety

This repo contains exploit code (CVE-2026-31431) and prompt injection
payloads. Every directory containing attack material must include a
README.md with:
- A clear disclaimer that the code is for authorized testing only
- A description of what the exploit does
- Instructions for safe handling

Never commit real credentials, API keys, or tokens. Use `.example`
files for secret templates.

### Rule 6: No Secrets or Cluster-Identifying Information in Code

This repo will be pushed to GitHub. NEVER write any of the following
into committed files (code, YAML, docs, scripts, comments, or any
other tracked content):

- **IP addresses** -- no node IPs, pod IPs, service ClusterIPs, or
  external IPs from the real cluster
- **Hostnames** -- no real node names, cluster DNS names, or
  cloud-provider-generated identifiers
- **API keys, tokens, or passwords** -- not even expired or example
  ones that look real
- **Externally-routable URLs** -- no OpenShift console URLs, cloud
  provider dashboard links, or public endpoints
- **Cloud account identifiers** -- no IBM Cloud account IDs, project
  IDs, resource group names, or subscription details

**What IS acceptable:**
- Cluster-internal Kubernetes DNS names (e.g., `gemma4-svc.vllm.svc.cluster.local`)
  -- these are not routable outside the cluster
- Public software versions (e.g., OCP 4.21, kernel 5.14.0-570)
- Placeholder strings from Rule 4 (`VLLM_ENDPOINT`, `REGISTRY`, etc.)
- Public upstream URLs (e.g., GitHub repos, documentation sites)

When recording findings from the live cluster in docs, sanitize first:
strip IPs, replace real hostnames with generic labels, and omit any
value that could fingerprint the specific cluster.

### Rule 7: File-by-File Guidance

| File/Dir                          | Key Constraint                                           |
|-----------------------------------|----------------------------------------------------------|
| `deploy/pod-*.yaml`              | Must match pod matrix in ADR Section 2 exactly           |
| `deploy/openshell-policy.yaml`   | Must allow ONLY the vLLM endpoint, deny everything else  |
| `attacks/attack1-*/`             | Prompt injection attack per ADR Section 4                |
| `attacks/attack2-*/`             | CVE-2026-31431 per ADR Section 5                         |
| `demo/run-demo.sh`               | Must follow the flow in ADR Section 8                    |
| `images/agent-sandbox/Dockerfile` | Must include OpenCode, Python3, curl, and the exploit    |
| `infra/verify-kernel.sh`         | Must check for CVE-2026-31431 patch status               |

---

## How to Work on This Repo

1. Read `docs/ADR.md` and `docs/PLAN.md`.
2. Find the next pending task in `docs/PLAN.md`.
3. Mark it `[>]` in progress.
4. Implement it, following the ADR.
5. Mark it `[x]` done.
6. Move to the next task.

If you are resuming work after a break, re-read `docs/ADR.md` and
`docs/PLAN.md` to re-orient. Do not rely on memory.

---

## Summary of What We're Building

Three OpenCode pods on OpenShift. Two attacks. One results matrix.

| Attack                  | kata-only      | openshell-only    | dual              |
|-------------------------|----------------|-------------------|--------------------|
| Prompt injection exfil  | DATA LEAKED    | BLOCKED           | BLOCKED            |
| CVE-2026-31431 escape   | CONTAINED (VM) | HOST COMPROMISED  | CONTAINED (VM)     |
