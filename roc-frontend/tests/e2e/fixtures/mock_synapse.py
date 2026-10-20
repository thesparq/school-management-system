#!/usr/bin/env python3
"""A stand-in Synapse for the e2e checks that drive the chat page.

Answers the calls the page itself makes when it logs in and reads its room list:

    GET  /_matrix/client/v3/login/sso/redirect/authentik?redirectUrl=…  -> 302 back with ?loginToken=
    POST /_matrix/client/v3/login                                        -> 200 access_token (m.login.token)
    GET  /_matrix/client/v3/sync                                         -> 200 an empty sync
    GET  /_matrix/client/v3/account/whoami                               -> the user a token belongs to

This is the flow the [REDACTED] uses: the homeserver's own OIDC provider logs the person in (see
`devops/matrix-config/homeserver.yaml`), so nothing needs an administrator's token to make an account
or mint one. The mock therefore does **not** answer `/_synapse/admin/…` at all — a suite can assert
that no part of the flow reaches for an admin credential, which is the property that replaced the
token proxy. The identity-provider hop is Authentik's in the real deployment; here the login token is
issued straight away.

Each redirect mints a fresh single-use `loginToken`; exchanging one twice answers 401
`M_UNKNOWN_TOKEN`, exactly as a replayed token does against the real homeserver (a reload after the
redirect must not look like a successful login). A minted access token is `syt_mock_<urlencoded user
id>`, which `whoami` recognises.

Every request is logged to stdout as `METHOD PATH [BODY]`, so a suite can count redirects (a reload
must not start another login) and see exactly which paths were asked for.

Usage:  python3 mock_synapse.py [port]   (default 9010; LOG_FILE env appends the request log)
"""

import json
import os
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER_ID = "@thesparq:matrix.johnethel.school"
log = open(os.environ.get("LOG_FILE", "/dev/stdout"), "a", buffering=1)

_state_lock = threading.Lock()
_login_counter = 0
_unspent_login_tokens = set()


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
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _cors(self):
        # The page talks to the homeserver from the app's own origin, so every answer carries the CORS
        # headers — the real deployment sets `enable_cors: true` in the homeserver's config for exactly
        # this reason, and without them the browser blocks the answer to a login the server accepted.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")

    def _redirect(self, location):
        self.send_response(302)
        self._cors()
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_OPTIONS(self):
        self._record(b"")
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _bearer(self):
        auth = self.headers.get("Authorization", "")
        return auth[len("Bearer ") :] if auth.startswith("Bearer ") else ""

    def do_GET(self):
        self._record(b"")
        if self.path.startswith("/_matrix/client/v3/login/sso/redirect"):
            # The homeserver's SSO entry point: hand the browser to the identity provider and come back to
            # `redirectUrl` with a one-time login token.
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            back = (query.get("redirectUrl") or [""])[0]
            if not back:
                return self._send(400, '{"errcode":"M_INVALID_PARAM","error":"redirectUrl is required"}')
            global _login_counter
            with _state_lock:
                _login_counter += 1
                token = f"mock-login-token-{_login_counter}"
                _unspent_login_tokens.add(token)
            self._redirect(f"{back}{'&' if '?' in back else '?'}loginToken={token}")
            return
        if self.path == "/_matrix/client/v3/account/whoami":
            user = user_for_token(self._bearer())
            if user is None or not user.startswith("@"):
                return self._send(401, '{"errcode":"M_UNKNOWN_TOKEN","error":"Unrecognised access token"}')
            return self._send(200, '{"user_id":"%s","is_guest":false}' % user)
        if self.path.startswith("/_matrix/client/v3/sync"):
            if user_for_token(self._bearer()) is None:
                return self._send(401, '{"errcode":"M_UNKNOWN_TOKEN","error":"Unrecognised access token"}')
            # An empty room list: the page renders its own "no channels yet" state, which is what a
            # freshly connected account sees.
            return self._send(200, '{"next_batch":"mock_batch","rooms":{"join":{},"invite":{}}}')
        self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._record(body)
        if self.path == "/_matrix/client/v3/login":
            try:
                parsed = json.loads(body or b"{}")
            except ValueError:
                parsed = {}
            token = parsed.get("token", "")
            with _state_lock:
                known = token in _unspent_login_tokens
                if known:
                    _unspent_login_tokens.discard(token)
            if parsed.get("type") != "m.login.token" or not known:
                return self._send(401, '{"errcode":"M_UNKNOWN_TOKEN","error":"Invalid login token"}')
            return self._send(
                200,
                json.dumps(
                    {
                        "user_id": USER_ID,
                        "access_token": "syt_mock_" + urllib.parse.quote(USER_ID),
                        "device_id": "MOCKDEV",
                        "home_server": "matrix.johnethel.school",
                    }
                ),
            )
        self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')

    def do_PUT(self):
        self._record(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        # The admin API the token proxy used to call. Nothing in the SSO flow touches it, so answering
        # 404 here keeps that honest: a suite that sees a PUT is looking at a regression.
        self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9010
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
