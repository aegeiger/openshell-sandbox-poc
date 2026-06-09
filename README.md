# OpenShell + Kata Containers: Dual-Protection PoC

A proof-of-concept demonstrating that running an AI coding agent inside
the dual protection of [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell)
and [Kata Containers](https://github.com/kata-containers/kata-containers)
provides defense-in-depth that neither technology achieves alone.

## The Problem

AI coding agents like [OpenCode](https://opencode.ai/) execute arbitrary
code on your behalf. This creates two distinct threat classes:

1. **Application-layer attacks** -- A prompt injection tricks the agent
   into exfiltrating secrets via HTTP. Kata Containers (VM isolation)
   does not inspect network traffic, so the data leaks.

2. **Kernel-layer attacks** -- A container escape exploit
   ([CVE-2026-31431](https://copy.fail)) escalates to host root.
   OpenShell's Landlock/seccomp/proxy cannot protect against kernel
   memory corruption bugs.

Neither technology alone covers both. Together, they do.

## Results Matrix

| Attack                    | kata-only        | openshell-only     | dual (kata+openshell) |
|---------------------------|------------------|--------------------|-----------------------|
| Prompt injection exfil    | DATA LEAKED      | BLOCKED            | BLOCKED               |
| CVE-2026-31431 escape     | CONTAINED (VM)   | HOST COMPROMISED   | CONTAINED (VM)        |

## Architecture

Three OpenCode pods on OpenShift, each backed by the same vLLM endpoint
serving Gemma4-31b:

| Pod                      | RuntimeClass      | OpenShell | Kata |
|--------------------------|-------------------|-----------|------|
| `opencode-kata-only`     | `kata-containers` | No        | Yes  |
| `opencode-openshell-only`| default (runc)    | Yes       | No   |
| `opencode-dual`          | `kata-containers` | Yes       | Yes  |

## Quick Start

```bash
# 1. Prerequisites: OpenShift cluster with Kata and OpenShell installed
#    See infra/README.md for setup instructions

# 2. Build and push container images
export REGISTRY=your-registry.example.com
docker build -t $REGISTRY/openshell-poc/agent-sandbox:latest images/agent-sandbox/
docker build -t $REGISTRY/openshell-poc/attacker-listener:latest images/attacker-listener/
docker push $REGISTRY/openshell-poc/agent-sandbox:latest
docker push $REGISTRY/openshell-poc/attacker-listener:latest

# 3. Deploy everything
./demo/setup.sh

# 4. Run the demo
./demo/run-demo.sh

# 5. Clean up
./demo/teardown.sh
```

## Repo Structure

```
infra/          Cluster setup: Kata operator, RuntimeClass, kernel check
deploy/         Kubernetes manifests for all 3 pods + supporting resources
images/         Dockerfiles for agent sandbox and attacker listener
attacks/        Attack payloads with documentation and safety disclaimers
demo/           Demo automation scripts
docs/           ADR, implementation plan, security model, architecture
```

## Safety

This repo contains exploit code and prompt injection payloads for
**authorized security testing only**. See [attacks/README.md](attacks/README.md)
for safety guidelines. Never run the container escape exploit on
production systems.

## License

MIT -- see [LICENSE](LICENSE).
