#!/usr/bin/env python3
"""
Simple HTTP listener that logs all POST request bodies to stdout.
Used as the exfiltration target in the prompt injection demo.

Listens on port 9999 by default (override with PORT env var).
"""

import http.server
import sys
import os
from datetime import datetime, timezone


class ExfilHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        timestamp = datetime.now(timezone.utc).isoformat()
        source = self.client_address[0]

        print(f"\n{'='*60}", flush=True)
        print(f"[EXFIL RECEIVED] {timestamp}", flush=True)
        print(f"  Source: {source}", flush=True)
        print(f"  Path:   {self.path}", flush=True)
        print(f"  Size:   {content_length} bytes", flush=True)
        print(f"  Body:", flush=True)
        print(f"{body.decode('utf-8', errors='replace')}", flush=True)
        print(f"{'='*60}\n", flush=True)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"received\n")

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"attacker listener is running\n")

    def log_message(self, format, *args):
        # Suppress default access logging, we do our own
        pass


def main():
    port = int(os.environ.get("PORT", "9999"))
    server = http.server.HTTPServer(("0.0.0.0", port), ExfilHandler)
    print(f"[*] Attacker listener started on port {port}", flush=True)
    print(f"[*] Waiting for exfiltration attempts...", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down.", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
