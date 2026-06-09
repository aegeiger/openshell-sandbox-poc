# Attack Payloads

> **WARNING: This directory contains exploit code and prompt injection
> payloads. These materials are for authorized security testing and
> demonstration purposes only.**

## Legal Disclaimer

The code and payloads in this directory are provided for educational
and authorized security testing purposes only. Do not use this code
against systems you do not own or have explicit written authorization
to test.

The authors assume no liability for misuse of these materials.

## Contents

### Attack 1: Prompt Injection via Malicious Git Patch

**Directory:** `attack1-prompt-injection/`

A crafted git patch file containing a hidden prompt injection in its
commit message. When an AI coding agent is asked to review the patch,
the injection instructs the agent to exfiltrate sensitive data via HTTP.

- **Threat class:** Application-layer (network exfiltration)
- **Blocked by:** OpenShell (network policy proxy)
- **Not blocked by:** Kata Containers (no egress filtering)

### Attack 2: Container Escape via CVE-2026-31431

**Directory:** `attack2-container-escape/`

A 732-byte Python exploit for CVE-2026-31431 ("Copy Fail"), a logic
flaw in the Linux kernel's `algif_aead` crypto subsystem. The exploit
achieves local privilege escalation to root by corrupting the page
cache of a setuid binary.

- **Threat class:** Kernel-layer (container escape / LPE)
- **Blocked by:** Kata Containers (VM boundary)
- **Not blocked by:** OpenShell (kernel bug bypasses Landlock/seccomp)

## Safe Handling

1. **Never run the container escape exploit on production nodes.** It
   corrupts `/usr/bin/su` in the page cache. While not persistent across
   reboot, the resulting root shell is real.

2. **The attacker listener logs all received data.** Ensure it does not
   run on networks where it could capture real secrets.

3. **The prompt injection payload is designed to be obvious** in source
   form. In a real attack, injections would be more heavily obfuscated.
