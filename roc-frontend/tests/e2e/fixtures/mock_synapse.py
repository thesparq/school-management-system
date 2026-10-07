#!/usr/bin/env python3
"""A stand-in Synapse for the matrix_token.sh e2e check.

Answers the calls the backend's /api/matrix/token proxy makes:

    PUT  /_synapse/admin/v2/users/<id>          -> 200 {}            (ensure user)
    POST /_synapse/admin/v1/users/<id>/login    -> 200 access_token  (mint token)
    GET  /_matrix/client/v3/account/whoami      -> the user a token belongs to (validate)

Every request is logged to stdout as `METHOD PATH [BODY]`, so the shell suite can assert the
user id the backend built (`%40<user>%3Amatrix.johnethel.school`) and the display name it sent.
A minted token is `syt_mock_<urlencoded user id>`; whoami recognises a minted token and answers
with the user it was minted for, which is what lets the suite prove a reused token is not minted
again. Any other path answers 404; a wrong admin bearer answers 403.

Usage:  python3 mock_synapse.py [port]   (default 9010; LOG_FILE env appends the request log)
"""

import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ADMIN_TOKEN = "mock-admin-token"
log = open(os.environ.get("LOG_FILE", "/dev/stdout"), "a", buffering=1)


def user_for_token(token):
    # A minted token carries the urlencoded user id after "syt_mock_".
    if token.startswith("syt_mock_"):
        return urllib.parse.unquote(token[len("syt_mock_") :])
    return None


class Handler(BaseHTTPRequestHandler):
    def _record(self, body):
        log.write(f"{self.command} {self.path}" + (f" {body.decode(errors='replace')}" if body else "") + "\n")

    def _send(self, status, payload):
        data = payload.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _admin_ok(self):
        return self.headers.get("Authorization") == f"Bearer {ADMIN_TOKEN}"

    def _bearer(self):
        auth = self.headers.get("Authorization", "")
        return auth[len("Bearer ") :] if auth.startswith("Bearer ") else ""

    def do_PUT(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._record(body)
        if self.path.startswith("/_synapse/admin/v1/users/") and self.path.endswith("/admin"):
            if not self._admin_ok():
                return self._send(403, '{"errcode":"M_FORBIDDEN","error":"admin required"}')
            return self._send(200, "{}")
        if not self.path.startswith("/_synapse/admin/v2/users/"):
            return self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')
        if not self._admin_ok():
            return self._send(403, '{"errcode":"M_FORBIDDEN","error":"admin required"}')
        self._send(200, "{}")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._record(body)
        if not self.path.startswith("/_synapse/admin/v1/users/"):
            return self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')
        if not self._admin_ok():
            return self._send(403, '{"errcode":"M_FORBIDDEN","error":"admin required"}')
        user_id = self.path.removeprefix("/_synapse/admin/v1/users/").removesuffix("/login")
        self._send(200, '{"access_token":"syt_mock_%s","device_id":"MOCKDEV","home_server":"mock"}' % user_id)

    def do_GET(self):
        self._record(b"")
        if self.path == "/_matrix/client/v3/account/whoami":
            user = user_for_token(self._bearer())
            if user is None or not user.startswith("@"):
                return self._send(401, '{"errcode":"M_UNKNOWN_TOKEN","error":"Unrecognised access token"}')
            return self._send(200, '{"user_id":"%s","is_guest":false}' % user)
        self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9010
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
