# Implementation Plan

> **This is a living document.** Task statuses are updated as work progresses.
> However, the task list itself (adding/removing/reordering tasks) must NOT
> be changed without explicit approval from the user (E Geiger).
>
> **Status legend:** `[ ]` pending, `[>]` in progress, `[x]` done, `[-]` skipped/blocked

---

## Phase 1: Repo Scaffolding and Documentation

- [x] 1.1 Create `docs/ADR.md` -- architecture decision record
- [x] 1.2 Create `docs/PLAN.md` -- this file
- [x] 1.3 Create `AGENTS.md` -- agent self-reference instructions
- [x] 1.4 Create `README.md` -- project overview for humans
- [x] 1.5 Create `docs/security-model.md` -- detailed security boundary doc
- [x] 1.6 Create `docs/architecture.md` -- mermaid diagrams

## Phase 2: Attack Payloads

- [x] 2.1 Create `attacks/README.md` -- safety disclaimers
- [x] 2.2 Create `attacks/attack1-prompt-injection/malicious.patch`
- [x] 2.3 Create `attacks/attack1-prompt-injection/task-prompt.txt`
- [x] 2.4 Create `attacks/attack1-prompt-injection/README.md`
- [x] 2.5 Download/create `attacks/attack2-container-escape/copy_fail_exp.py`
- [x] 2.6 Create `attacks/attack2-container-escape/verify-escape.sh`
- [x] 2.7 Create `attacks/attack2-container-escape/README.md`

## Phase 3: Container Images

- [x] 3.1 Create `images/agent-sandbox/Dockerfile`
- [x] 3.2 Create `images/agent-sandbox/opencode.json`
- [x] 3.3 Copy exploit into `images/agent-sandbox/copy_fail_exp.py`
- [x] 3.4 Create `images/attacker-listener/Dockerfile`
- [x] 3.5 Create `images/attacker-listener/listener.py`

## Phase 4: Infrastructure Manifests

- [x] 4.1 Create `infra/README.md` -- setup instructions
- [x] 4.2 Create `infra/kata-operator.yaml` or operator subscription YAML
- [x] 4.3 Create `infra/kata-runtimeclass.yaml`
- [x] 4.4 Create `infra/verify-kernel.sh`

## Phase 5: Kubernetes Deployment Manifests

- [x] 5.1 Create `deploy/namespace.yaml`
- [x] 5.2 Create `deploy/openshell-helm-values.yaml`
- [x] 5.3 Create `deploy/openshell-policy.yaml`
- [x] 5.4 Create `deploy/pod-kata-only.yaml`
- [x] 5.5 Create `deploy/pod-openshell-only.yaml`
- [x] 5.6 Create `deploy/pod-dual.yaml`
- [x] 5.7 Create `deploy/configmap-opencode.yaml`
- [x] 5.8 Create `deploy/configmap-malicious-patch.yaml`
- [x] 5.9 Create `deploy/attacker-listener.yaml`
- [x] 5.10 Create `deploy/secret-api-keys.yaml.example`

## Phase 6: Demo Scripts

- [ ] 6.1 Create `demo/lib/colors.sh`
- [ ] 6.2 Create `demo/lib/utils.sh`
- [ ] 6.3 Create `demo/setup.sh`
- [ ] 6.4 Create `demo/teardown.sh`
- [ ] 6.5 Create `demo/run-demo.sh` -- main demo script

## Phase 7: Final Documentation

- [ ] 7.1 Review all files for consistency with ADR
- [ ] 7.2 Verify repo structure matches ADR section 7
- [ ] 7.3 Final `README.md` polish

---

## Dependencies and Ordering

- Phase 2 and Phase 3 can proceed in parallel.
- Phase 4 and Phase 5 depend on decisions in the ADR being finalized.
- Phase 6 depends on Phase 2 (attack payloads), Phase 3 (images),
  and Phase 5 (deployment manifests).
- Phase 7 depends on everything else.

## Notes

- ~~The vLLM endpoint URL is TBD~~ **RESOLVED (2026-06-09):**
  `http://gemma4-svc.vllm.svc.cluster.local:8000`, model ID `gemma4-31b`,
  OpenAI-compatible API. ClusterIP service in `vllm` namespace, no route.
- Container image registry is TBD. Use `REGISTRY/openshell-poc/` as
  placeholder. The user will provide the actual registry.
- ~~The OpenShift cluster details are TBD~~ **RESOLVED (2026-06-09):**
  OCP 4.21, RHCOS 9.6, 3 masters + 3 workers, all running kernel
  `5.14.0-570.103.1.el9_6` (built 2026-03-24, VULNERABLE to
  CVE-2026-31431). `algif_aead` is builtin. CRI-O 1.34.6.
- Workers available for Kata: 3 worker nodes, all identical config.
