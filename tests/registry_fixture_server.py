#!/usr/bin/env python3
"""Loopback-only deterministic registry fixture used by the local Zig test gate."""

from __future__ import annotations

import io
import json
import sys
import tarfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


COUNTS: dict[str, int] = {}


def package_archive() -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz", format=tarfile.PAX_FORMAT) as archive:
        content = b"fixture package\n"
        info = tarfile.TarInfo("fixture-package/package.txt")
        info.size = len(content)
        info.mode = 0o644
        info.mtime = 0
        archive.addfile(info, io.BytesIO(content))
    return output.getvalue()


PACKAGE_ARCHIVE = package_archive()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def send_payload(
        self,
        status: int,
        payload: bytes,
        content_type: str = "application/json",
        headers: dict[str, str] | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        COUNTS[path] = COUNTS.get(path, 0) + 1

        if path == "/success":
            self.send_payload(200, b'{"ok":true}')
        elif path == "/auth":
            if self.headers.get("Authorization") == "Bearer fixture-token":
                self.send_payload(200, b'{"authenticated":true}')
            else:
                self.send_payload(401, b'{"error":"unauthorized"}')
        elif path == "/redirect":
            self.send_payload(302, b"", headers={"Location": "/success"})
        elif path == "/timeout":
            time.sleep(0.25)
            self.send_payload(200, b'{"late":true}')
        elif path == "/malformed":
            self.send_payload(200, b"{not-json")
        elif path == "/oversized":
            self.send_payload(200, b"[" + b"0" * (8 * 1024 * 1024) + b"]")
        elif path == "/rate-limit":
            if COUNTS[path] == 1:
                self.send_payload(429, b'{"error":"rate limited"}')
            else:
                self.send_payload(200, b'{"retried":true}')
        elif path == "/retry":
            if COUNTS[path] < 3:
                self.send_payload(503, b'{"error":"retry"}')
            else:
                self.send_payload(200, b'{"retried":true}')
        elif path == "/health":
            self.send_payload(200, b'{"status":"ok"}')
        elif path == "/api/v1/packages/fixture/package":
            base = f"http://127.0.0.1:{self.server.server_port}"
            payload = {
                "name": "package",
                "full_name": "fixture/package",
                "description": "local fixture package",
                "version": "1.0.0",
                "tarball_url": f"{base}/artifacts/fixture-package.tar.gz",
                "published_at": "2026-01-01T00:00:00Z",
                "last_updated": "2026-01-01T00:00:00Z",
            }
            self.send_payload(200, json.dumps(payload).encode())
        elif path == "/api/v1/repos/fixture/package/releases":
            base = f"http://127.0.0.1:{self.server.server_port}"
            payload = [{
                "tag_name": "v1.0.0",
                "name": "fixture",
                "published_at": "2026-01-01T00:00:00Z",
                "prerelease": False,
                "tarball_url": f"{base}/artifacts/fixture-package.tar.gz",
                "zipball_url": None,
            }]
            self.send_payload(200, json.dumps(payload).encode())
        elif path == "/api/v1/search":
            base = f"http://127.0.0.1:{self.server.server_port}"
            payload = {"items": [{
                "name": "package",
                "full_name": "fixture/package",
                "description": "local fixture package",
                "version": "1.0.0",
                "tarball_url": f"{base}/artifacts/fixture-package.tar.gz",
                "sha256_hash": None,
                "published_at": "2026-01-01T00:00:00Z",
                "registry_name": "fixture",
                "last_updated": "2026-01-01T00:00:00Z",
            }]}
            self.send_payload(200, json.dumps(payload).encode())
        elif path == "/artifacts/fixture-package.tar.gz":
            self.send_payload(200, PACKAGE_ARCHIVE, "application/gzip")
        elif path == "/api/v1/packages/malformed/pkg":
            self.send_payload(200, b"{not-json")
        else:
            self.send_payload(404, json.dumps({"path": path}).encode())


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: registry_fixture_server.py PORT_FILE")
    port_file = Path(sys.argv[1])
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port_file.write_text(str(server.server_port), encoding="ascii")
    server.serve_forever()


if __name__ == "__main__":
    main()
