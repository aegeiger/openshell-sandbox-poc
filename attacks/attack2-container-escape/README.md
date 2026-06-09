# Attack 2: Container Escape via CVE-2026-31431 "Copy Fail"

> **For authorized security testing only. Do not run on production systems.**

## Overview

CVE-2026-31431 is a logic flaw in the Linux kernel's `algif_aead`
crypto subsystem (part of the AF_ALG interface). The exploit corrupts
the page cache of a setuid binary to achieve local privilege escalation
from an unprivileged user to root.

## CVE Details

| Field          | Value                                              |
|----------------|----------------------------------------------------|
| CVE ID         | CVE-2026-31431                                     |
| Nickname       | Copy Fail                                          |
| CVSS           | 7.8 HIGH (AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H)  |
| Affected       | Linux kernels from 2017 through commit `a664bf3d603d` |
| Exploit size   | 732 bytes (Python)                                 |
| Reliability    | 100% (straight-line logic flaw, no race conditions)|
| CISA KEV       | Yes (added 2026-05-01)                             |
| Fix commit     | `a664bf3d603dc3bdcf9ae47cc21e0daec706d7a5`         |

## How the Exploit Works

1. Opens an `AF_ALG` socket with the `authencesn(hmac(sha256),cbc(aes))`
   algorithm
2. Uses `splice()` to create a pipe between the page-cache backing of
   `/usr/bin/su` and the AF_ALG socket
3. A logic flaw in the in-place operation path allows the exploit to
   get a writable reference to the page-cache page
4. Writes 4 bytes that corrupt the ELF binary in a controlled way
5. Running `su` after the corruption yields a root shell

## Files

- `copy_fail_exp.py` -- The 732-byte Python exploit (from upstream PoC)
- `verify-escape.sh` -- Post-exploit script to check host access

## How It Works in the Demo

```bash
# 1. Run the exploit (gets root via corrupted /usr/bin/su)
python3 /opt/copy_fail_exp.py

# 2. Get root shell
su

# 3. Check if we escaped to the host
bash /opt/verify-escape.sh
```

## Expected Results

| Pod Configuration | Result |
|-------------------|--------|
| kata-only         | **CONTAINED** -- root of Kata guest VM, not the host |
| openshell-only    | **HOST COMPROMISED** -- root of the actual node |
| dual              | **CONTAINED** -- root of Kata guest VM, not the host |

## Why Kata Blocks This

With Kata, the pod runs inside a lightweight VM with its own guest
kernel. The exploit corrupts the guest kernel's page cache and gains
root inside the VM. But `/proc/1/root/etc/shadow` shows the VM's
shadow file, not the host node's. The host kernel is never exposed
to the exploit.

## Why OpenShell Does Not Block This

OpenShell's protections operate at the application layer:
- **Landlock** restricts filesystem paths but not kernel memory ops
- **Seccomp** cannot block `AF_ALG` sockets without breaking crypto
- **Policy proxy** intercepts network egress, not local syscalls

The exploit operates entirely within the kernel, below all of these
defense layers.

## References

- https://copy.fail -- Project website
- https://github.com/theori-io/copy-fail-CVE-2026-31431 -- Upstream PoC
- https://xint.io/blog/copy-fail-linux-distributions -- Technical writeup
- https://nvd.nist.gov/vuln/detail/CVE-2026-31431 -- NVD entry
