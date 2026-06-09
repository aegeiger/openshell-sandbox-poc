# Attack 2: Container Escape via CVE-2026-31431 "Copy Fail"

> **For authorized security testing only. Do not run on production systems.**

## Overview

CVE-2026-31431 is a logic flaw in the Linux kernel's `algif_aead`
crypto subsystem (part of the AF_ALG interface). The exploit gives
an unprivileged process a **page-cache write primitive**: the ability
to write 4 bytes at a time to any file's page cache, even if the
file is only open for reading.

On runc (overlayfs), the page cache is shared with the host kernel.
Corrupting a file's page cache inside one container makes the
corruption visible to **all other containers** sharing the same image
layer -- a true container escape via cross-container data corruption.

On Kata (virtiofs), the page cache is per-VM. Corruption stays
inside the VM and is invisible to other containers.

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
   a target file and the AF_ALG socket
3. A logic flaw in the in-place operation path allows the exploit to
   get a writable reference to the page-cache page
4. Writes 4 bytes at offset 0, corrupting the file's cached content

## Files

- `copy_fail_exp.py` -- The original 732-byte exploit (targets `/usr/bin/su`)
- `escape_demo.py` -- Demo variant that targets `/opt/marker.txt`
  (writes `PWN!` at offset 0 to demonstrate page-cache escape)
- `verify-escape.sh` -- Post-exploit verification script (legacy)

## How It Works in the Demo

The container image includes `/opt/marker.txt` containing `INTACT`.

```
1. Read /opt/marker.txt inside the pod     → "INTACT"
2. Run: python3 /opt/escape_demo.py        → writes "PWN!" via page cache
3. Read /opt/marker.txt inside the pod     → "PWN!CT" (corrupted)
4. Launch a verification pod (same image, same node, runc)
5. Read /opt/marker.txt in verification pod:
   - runc pod:  "PWN!CT" → corruption escaped → HOST COMPROMISED
   - Kata pod:  "INTACT" → corruption contained → CONTAINED (VM)
```

The exploit runs through `openshell sandbox exec` on OpenShell-protected
pods, proving that all of OpenShell's protections (Landlock, seccomp,
`no_new_privs`, network proxy) cannot prevent the kernel-level page-cache
corruption.

## Expected Results

| Pod Configuration | Local corruption | Verification pod | Result |
|-------------------|-----------------|------------------|--------|
| kata-only         | No (virtiofs)   | INTACT           | **CONTAINED** |
| openshell-only    | Yes (overlayfs) | PWN!CT           | **HOST COMPROMISED** |
| dual              | No (virtiofs)   | INTACT           | **CONTAINED** |

## Why Kata Blocks This

Kata runs each pod inside a VM with its own kernel. The container
filesystem uses **virtiofs** (FUSE), which has a separate page cache
from the host. The `splice()` + `AF_ALG` chain operates on the guest
kernel's page cache, not the host's. Corruption stays inside the VM.

## Why OpenShell Does Not Block This

OpenShell's protections operate at the application layer:
- **Landlock** restricts filesystem paths but not kernel memory ops
- **Seccomp** cannot block `AF_ALG` sockets without breaking crypto
- **`no_new_privs`** blocks setuid-based privilege escalation but does
  NOT prevent the page-cache write primitive itself
- **Policy proxy** intercepts network egress, not local syscalls

The exploit only needs read access to the target file (`O_RDONLY`).
The write happens through the kernel bug, bypassing all userspace
access controls.

## References

- https://copy.fail -- Project website
- https://github.com/theori-io/copy-fail-CVE-2026-31431 -- Upstream PoC
- https://xint.io/blog/copy-fail-linux-distributions -- Technical writeup
- https://nvd.nist.gov/vuln/detail/CVE-2026-31431 -- NVD entry
