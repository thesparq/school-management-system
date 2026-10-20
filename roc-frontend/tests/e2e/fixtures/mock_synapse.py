#!/usr/bin/env python3
"""A stand-in Synapse for the e2e checks that drive the chat page.

Answers the calls the page itself makes when it logs in and reads its room list:

    GET  /_matrix/client/v3/login                                        -> 200 the providers it offers
    GET  /_matrix/client/v3/login/sso/redirect/oidc-authentik?redirectUrl=…
                                                                         -> 302 back with ?loginToken=
    POST /_matrix/client/v3/login                                        -> 200 access_token (m.login.token)
    POST /_matrix/client/v3/createRoom                                   -> 200 a new room id
    POST /_matrix/client/v3/rooms/<roomId>/join                          -> 200 the same id, now joined
    GET  /_matrix/client/v3/sync                                         -> 200 the rooms this token has joined
    GET  /_matrix/client/v3/account/whoami                               -> the user a token belongs to

A redirect naming a provider this homeserver does not offer answers 404
`M_NOT_FOUND "Unknown identity provider"`, which is what the real Synapse answered to the id the page
used to pin (see below).

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

# The identity providers this homeserver offers. The deployed one is configured in
# `devops/matrix-config/homeserver.yaml` with `idp_id: authentik`, and Synapse exposes that to clients as
# **`oidc-authentik`**: it prefixes a provider's configured id with the sign-in mechanism it belongs to
# (`synapse/config/oidc.py`), which is the detail a page that pins the configured value gets wrong. The
# mock offers the prefixed id — so a page that guesses has to fail here the way it failed against the
# deployed homeserver — and refuses anything else exactly as Synapse does.
#
# `SSO_PROVIDERS_FILE`, when set, is read on every request, so a suite can change what the homeserver
# offers while the page is open ("[]" for a homeserver that offers nothing).
DEFAULT_PROVIDERS = [{"id": "oidc-authentik", "name": "Johnethel School SSO"}]
PROVIDERS_FILE = os.environ.get("SSO_PROVIDERS_FILE", "")


def providers():
    if not PROVIDERS_FILE:
        return DEFAULT_PROVIDERS
    try:
        with open(PROVIDERS_FILE) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return DEFAULT_PROVIDERS

_state_lock = threading.Lock()
_login_counter = 0
_unspent_login_tokens = set()
_session_counter = 0
# The rooms this stub has been asked to make, and which token has joined which. Everything the page does
# with rooms is local to the homeserver, so a suite that creates a channel and then joins it as somebody
# else is driving the two calls the real Synapse would receive.
_room_counter = 0
_rooms = {}
_joined = {}


def user_for_token(token):
    # A minted token carries a session number and the urlencoded user id: `syt_mock_<session>_<user id>`.
    # The session is what makes two logins two *sessions* even though this stub has one user — without it,
    # a room an administrator joined would read as joined for the pupil too, and every membership check in
    # a suite would pass for the wrong reason.
    if token.startswith("syt_mock_"):
        parts = token[len("syt_mock_") :].split("_", 1)
        if len(parts) == 2:
            return urllib.parse.unquote(parts[1])
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
        if self.path == "/_matrix/client/v3/login":
            # What this homeserver will accept, the way a client asks (MSC2858): the page reads the
            # provider list here rather than assuming the name the config file uses.
            return self._send(200, json.dumps({"flows": [
                {"type": "m.login.sso", "identity_providers": providers()},
                {"type": "m.login.token"},
            ]}))
        if self.path.startswith("/_matrix/client/v3/login/sso/redirect"):
            # The homeserver's SSO entry point: hand the browser to the identity provider and come back to
            # `redirectUrl` with a one-time login token. A provider it does not offer is refused before
            # anything is handed over — 404, as the real homeserver answers.
            idp_id = urllib.parse.urlparse(self.path).path.rsplit("/", 1)[-1]
            if idp_id not in [p["id"] for p in providers()]:
                return self._send(404, '{"errcode":"M_NOT_FOUND","error":"Unknown identity provider"}')
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
            token = self._bearer()
            if user_for_token(token) is None:
                return self._send(401, '{"errcode":"M_UNKNOWN_TOKEN","error":"Unrecognised access token"}')
            # The rooms this token has joined, each with the name it was made with: what the page's own room
            # list is built from. A token that has joined nothing gets the empty list a freshly connected
            # account sees, which is what the page renders its "no channels yet" state for.
            with _state_lock:
                mine = sorted(_joined.get(token, set()))
                rooms = {
                    room_id: {
                        "state": {"events": [{"type": "m.room.name", "state_key": "", "content": {"name": _rooms.get(room_id, room_id)}}]},
                        "timeline": {"events": []},
                        "unread_notifications": {"notification_count": 0},
                    }
                    for room_id in mine
                }
            return self._send(200, json.dumps({"next_batch": "mock_batch", "rooms": {"join": rooms, "invite": {}}}))
        self._send(404, '{"errcode":"M_UNRECOGNIZED","error":"no such endpoint"}')

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._record(body)
        if self.path == "/_matrix/client/v3/createRoom":
            # A channel being made. The request body is in the log for a suite to read — that is where a
            # private channel (the same call with `visibility: private`) is told apart from a public one.
            try:
                parsed = json.loads(body or b"{}")
            except ValueError:
                parsed = {}
            token = self._bearer()
            with _state_lock:
                global _room_counter
                _room_counter += 1
                room_id = f"!mockroom{_room_counter}:matrix.johnethel.school"
                _rooms[room_id] = parsed.get("name") or room_id
                _joined.setdefault(token, set()).add(room_id)
            return self._send(200, json.dumps({"room_id": room_id, "room_alias": None}))
        if self.path.startswith("/_matrix/client/v3/rooms/") and self.path.endswith("/join"):
            # Joining by address: a public channel from the school's list, or an unlisted one whose code the
            # person was given. Whether a room is joinable is the homeserver's business (its join rules), not
            # this stub's — but the room does then show in this token's next sync, which is what puts it in
            # the page's sidebar.
            room_id = urllib.parse.unquote(self.path[len("/_matrix/client/v3/rooms/") : -len("/join")])
            token = self._bearer()
            with _state_lock:
                _rooms.setdefault(room_id, room_id)
                _joined.setdefault(token, set()).add(room_id)
            return self._send(200, json.dumps({"room_id": room_id}))
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
            with _state_lock:
                global _session_counter
                _session_counter += 1
                session = _session_counter
            return self._send(
                200,
                json.dumps(
                    {
                        "user_id": USER_ID,
                        "access_token": "syt_mock_%d_%s" % (session, urllib.parse.quote(USER_ID)),
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
