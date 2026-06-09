# Architecture

## Cluster Layout

```
OpenShift Cluster (OCP 4.21)
├── vllm namespace
│   └── gemma4 pod + gemma4-svc (ClusterIP :8000)
│
├── openshell namespace (or openshell-poc)
│   ├── OpenShell Gateway (Helm chart)
│   │   ├── gateway pod
│   │   ├── gateway service
│   │   └── PKI secrets
│   │
│   ├── opencode-kata-only pod        [runtimeClass: kata]
│   ├── opencode-openshell-only pod   [runtimeClass: default, OpenShell sandbox]
│   ├── opencode-dual pod             [runtimeClass: kata, OpenShell sandbox]
│   │
│   └── attacker-listener pod + svc   [receives exfil attempts]
│
└── Worker nodes (3x, kernel 5.14.0-570 -- vulnerable to CVE-2026-31431)
    └── Kata Containers runtime (via OpenShift Sandboxed Containers operator)
```

## Pod Architecture

```mermaid
graph TB
    subgraph "Worker Node (host kernel: 5.14.0-570)"
        subgraph "Pod: opencode-kata-only"
            direction TB
            K_VM["Kata micro-VM<br/>(guest kernel)"]
            K_OC["OpenCode agent"]
            K_VM --> K_OC
        end

        subgraph "Pod: opencode-openshell-only"
            direction TB
            OS_GW["OpenShell Supervisor"]
            OS_PROXY["Policy Proxy<br/>(egress filtering)"]
            OS_OC["OpenCode agent"]
            OS_GW --> OS_PROXY --> OS_OC
        end

        subgraph "Pod: opencode-dual"
            direction TB
            D_VM["Kata micro-VM<br/>(guest kernel)"]
            D_GW["OpenShell Supervisor"]
            D_PROXY["Policy Proxy<br/>(egress filtering)"]
            D_OC["OpenCode agent"]
            D_VM --> D_GW --> D_PROXY --> D_OC
        end
    end

    VLLM["vLLM<br/>gemma4-svc:8000"]
    ATTACKER["Attacker Listener<br/>:9999"]

    K_OC -->|"curl exfil"| ATTACKER
    K_OC -->|"inference"| VLLM

    OS_PROXY -->|"inference: ALLOW"| VLLM
    OS_PROXY -.->|"exfil: BLOCKED"| ATTACKER

    D_PROXY -->|"inference: ALLOW"| VLLM
    D_PROXY -.->|"exfil: BLOCKED"| ATTACKER
```

## Attack Flow: Prompt Injection (Attack 1)

```mermaid
sequenceDiagram
    participant User as Demo Script
    participant Pod as OpenCode Pod
    participant Agent as OpenCode Agent
    participant Proxy as OpenShell Proxy
    participant Listener as Attacker Listener

    User->>Pod: Copy malicious.patch + task prompt
    Pod->>Agent: "Review this patch, follow test instructions"
    Agent->>Agent: Reads patch, finds hidden injection
    Agent->>Agent: Reads /proc/self/environ

    alt No OpenShell (kata-only)
        Agent->>Listener: POST /exfil (secrets)
        Listener-->>Agent: 200 OK
        Note over Listener: DATA LEAKED
    else Has OpenShell (openshell-only, dual)
        Agent->>Proxy: POST /exfil (secrets)
        Proxy-->>Agent: 403 policy_denied
        Note over Proxy: BLOCKED
    end
```

## Attack Flow: Container Escape (Attack 2)

```mermaid
sequenceDiagram
    participant User as Demo Script
    participant Pod as Pod Container
    participant Kernel as Kernel
    participant Verify as Verification Pod

    Note over Pod: /opt/marker.txt = "INTACT"

    User->>Pod: python3 /opt/escape_demo.py
    Pod->>Kernel: AF_ALG socket + splice()
    Kernel->>Kernel: Page-cache write "PWN!" to /opt/marker.txt

    Note over Pod: /opt/marker.txt = "PWN!CT"

    User->>Verify: Launch new pod (same image, same node)
    Verify->>Verify: cat /opt/marker.txt

    alt No Kata (openshell-only, overlayfs)
        Note over Verify: Reads "PWN!CT"<br/>Page-cache corruption escaped<br/>HOST COMPROMISED
    else Has Kata (kata-only, dual, virtiofs)
        Note over Verify: Reads "INTACT"<br/>Corruption contained in VM<br/>CONTAINED
    end
```
