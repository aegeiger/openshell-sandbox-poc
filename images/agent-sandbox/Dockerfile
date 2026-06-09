# Agent sandbox image for OpenShell + Kata dual-protection PoC
#
# Based on the OpenShell community base sandbox image.
# Adds: OpenCode, Python3, curl, and the CVE-2026-31431 exploit.
#
# Build from repo root:
#   docker build -f images/agent-sandbox/Dockerfile \
#     -t REGISTRY/openshell-poc/agent-sandbox:latest .

FROM ghcr.io/nvidia/openshell-community/sandboxes/base:latest

USER root

# Install additional tools needed for the demo
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        curl \
        jq \
        git \
    && rm -rf /var/lib/apt/lists/*

# Copy OpenCode configuration
COPY images/agent-sandbox/opencode.json /home/user/.config/opencode/config.json

# Copy the CVE-2026-31431 exploit into /opt for the demo
# WARNING: This is exploit code for authorized testing only.
COPY attacks/attack2-container-escape/copy_fail_exp.py /opt/copy_fail_exp.py
COPY attacks/attack2-container-escape/escape_demo.py /opt/escape_demo.py

# Copy the post-exploit verification script
COPY attacks/attack2-container-escape/verify-escape.sh /opt/verify-escape.sh
RUN chmod +x /opt/verify-escape.sh

# Create a marker file for the container escape demo.
# If the exploit corrupts this file's page cache, the corruption is
# visible to other containers sharing the same image layer on the host.
RUN echo "INTACT" > /opt/marker.txt

# Switch back to unprivileged user
USER user
WORKDIR /home/user/workspace
