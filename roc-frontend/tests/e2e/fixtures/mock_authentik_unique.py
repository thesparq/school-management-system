# Minimal Authentik stand-in for the admin checks.
#
# Like the repo root's mock_authentik.py, but it keeps a real user table, which is what the
# identity/profile split needs: POST creates a login with a fresh `pk`, GET lists the logins in
# Authentik's own shape (`{"pagination": {…}, "results": [{pk, email, name, is_active, …}, …]}`),
# PATCH updates the fields it is given (the backend sends `{"email": …}` and `{"is_active": false}`)
# and DELETE removes one. An unknown pk answers 404, the way Authentik does, so the backend's
# cannot-disable-this-login path is observable instead of silently succeeding.
#
# The directory starts with the logins an admin creates in Authentik itself — one per role plus two
# that belong to no role (see `seed_user`). The backend's user listing is driven by these groups, so
# these logins appear in their tab with no profile row behind them; the sandbox database seeds no
# profiles for them, which is exactly the state that has to be listable and completable. The pk of a
# seeded login carries the process id like a created one does, so a restart cannot re-issue a pk that
# already has a profile.
#
# The instance-wide userinfo endpoint the backend validates tokens against (`/application/o/
# userinfo/`, the path AuthUrls derives from an issuer) is here too: each `mock-*-token` answers with
# the `groups` claim a real login would carry, which is where the backend reads the caller's role
# from. `mock-groupless-token` stands for a login in no directory group (a student). The DEV_MODE
# tokens (`dev-skip`, `dev-student`, `dev-teacher`) never reach this handler.
#
# A **JWT-shaped** bearer token is answered from its own claims instead, which is what a real
# userinfo endpoint does with the access tokens it issued: `sub` names a login in this directory and
# the answer is that login's `groups_obj` names, so a suite can mint a token for any login it has
# (`{"sub": …, "exp": …}`) and watch what the directory says about it. Two states are refused the
# way Authentik refuses them — an `exp` that has passed, and a login that is missing or has
# `is_active` false — so a disabled account's token really stops working here. The signature is not
# checked: this mock stands in for the decision, not for the cryptography.
#
# `GET /userinfo_calls` reports how many validations this endpoint has answered, so a suite can prove
# the backend served a request from its token cache rather than asking again.
#
#   python3 tests/e2e/fixtures/mock_authentik_unique.py [port]
#
# The port defaults to 9000 and can also come from MOCK_AUTHENTIK_PORT, so several sandboxes can run
# side by side.
#
# Then point the backend at it:
#   AUTHENTIK_API_URL=http://127.0.0.1:9000/api/v3/core/users/ AUTHENTIK_API_TOKEN=mock
#   AUTHENTIK_ISSUER_URL=http://127.0.0.1:9000/application/o/school/

from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import base64
import itertools
import json
import os
import sys
import time

PORT = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MOCK_AUTHENTIK_PORT', '9000'))
USERS_PATH = '/api/v3/core/users/'
USERINFO_PATH = '/application/o/userinfo/'
TOKEN_PATH = '/application/o/token/'
# The one password the mock's grant accepts for any login it knows (see do_POST).
MOCK_PASSWORD = 'mock-current-password'
counter = itertools.count(1)
# Every pk this process hands out carries the process id, so a restarted mock cannot re-issue a pk an
# earlier run already wrote a profile under (the sandbox database outlives the mock, and a colliding
# create fails on the record id). Created logins get a **number**, the way Authentik's own API sends a
# pk (`"pk":15`): a mock that only ever sends string pks cannot catch a reader that misses the number
# form, and missing it is how a created login's profile row gets written under a placeholder id.
pk_prefix = f"mock_uuid_{os.getpid()}"
users = {}  # pk (as text) -> the login, exactly as the list endpoint returns it
password_sets = {}  # pk -> the password the app asked to set (so tests can assert the call landed)
userinfo_calls = 0  # how many validations the userinfo endpoint has answered


def next_pk():
    """A numeric pk, unique to this process: the pid's digits then a counter."""
    return int(f"{os.getpid()}{next(counter)}")


def seed_user(suffix, username, name, email, groups, is_active=True):
    """One login the directory starts with, shaped as Authentik's list endpoint sends it: the group
    ids in `groups` and the group objects (which carry the names) in `groups_obj`. The backend reads
    the names from `groups_obj`, because that is where this API version puts them."""
    pk = f"{pk_prefix}_{suffix}"
    group_ids = [f"{pk_prefix}_group_{index}" for index, _ in enumerate(groups)]
    users[pk] = {
        'pk': pk,
        'username': username,
        'name': name,
        'email': email,
        'is_active': is_active,
        'groups': group_ids,
        'groups_obj': [
            {'pk': group_id, 'name': group, 'is_superuser': False, 'attributes': {}}
            for group_id, group in zip(group_ids, groups)
        ],
    }


# One login per role: these are the users an admin made in Authentik, and the listing has to show
# them before any profile row exists.
seed_user('seed_student', 'seed-student', 'Seed Student', 'seed-student@example.com', ['Students'])
seed_user('seed_teacher', 'seed-teacher', 'Seed Teacher', 'seed-teacher@example.com', ['Teachers'])
seed_user('seed_parent', 'seed-parent', 'Seed Parent', 'seed-parent@example.com', ['Parents'])
seed_user('seed_admin', 'seed-admin', 'Seed Admin', 'seed-admin@example.com', ['Super Admins'])
# Not members of the school: a login in no role group belongs to no tab. One carries no group at all
# and one an unrelated group, so both ways of mapping to no role are covered.
seed_user('seed_service', 'seed-service-account', 'Seed Service Account', 'seed-service@example.com', [])
seed_user('seed_outpost', 'seed-outpost', 'Seed Outpost', '', ['sms-service-account'])
# An account that was switched off in Authentik: the listing reports it as inactive rather than
# dropping it, so the state is visible to the admin.
seed_user('seed_inactive', 'seed-inactive', 'Seed Inactive Student', 'seed-inactive@example.com', ['Students'], is_active=False)
# Authentik sends a login's pk as a **number** (`"pk":13`), and the group objects that follow it carry
# a string `pk` of their own. This login keeps that shape in the sandbox: a mock that only ever sends
# string pks cannot catch a reader that takes a group's pk for the login's, which is exactly the bug
# the real directory exposed (the login's pk is the first `pk` in the object, group pks come later).
users['9001'] = {
    'pk': 9001,
    'username': 'seed-numeric',
    'name': 'Seed Numeric Student',
    'email': 'seed-numeric@example.com',
    'is_active': True,
    'groups': [f'{pk_prefix}_group_numeric'],
    'groups_obj': [
        {'pk': f'{pk_prefix}_group_numeric', 'name': 'Students', 'is_superuser': False, 'attributes': {}}
    ],
}
# And one that is an administrator, so the caller path can be driven with a numeric pk: the app keys a
# profile row as `type::record('<table>', '<pk>')`, a *string* id, and a bare `admin_profile:9002` is a
# different record that no lookup finds (see the progress tracker). The school's own admin is pk 5.
users['9002'] = {
    'pk': 9002,
    'username': 'seed-numeric-admin',
    'name': 'Seed Numeric Admin',
    'email': 'seed-numeric-admin@example.com',
    'is_active': True,
    'groups': [f'{pk_prefix}_group_numeric_admin'],
    'groups_obj': [
        {'pk': f'{pk_prefix}_group_numeric_admin', 'name': 'Super Admins', 'is_superuser': False, 'attributes': {}}
    ],
}

# token -> the userinfo body the backend reads the caller's id and role from
userinfo = {
    'mock-student-token': {'sub': 'mock_uuid_student', 'uid': 'mock_uuid_student', 'name': 'Sandbox Student',
                           'email': 'student@example.com', 'groups': ['Students']},
    'mock-teacher-token': {'sub': 'mock_uuid_teacher', 'uid': 'mock_uuid_teacher', 'name': 'Sandbox Teacher',
                           'email': 'teacher@example.com', 'groups': ['Teachers']},
    'mock-admin-token': {'sub': 'mock_uuid_admin', 'uid': 'mock_uuid_admin', 'name': 'Sandbox Admin',
                         'email': 'admin@example.com', 'groups': ['Administrators']},
    'mock-groupless-token': {'sub': 'mock_uuid_groupless', 'uid': 'mock_uuid_groupless', 'name': 'Sandbox Groupless',
                             'email': 'groupless@example.com', 'groups': []},
    # The school's own provider answers a *hashed* subject (Authentik's default `sub_mode`), so a real body
    # carries no pk at all — `sub` is a hash of the login's uuid, and there is no `uid`. This token stands
    # for the seeded administrator (`seed-admin@example.com`), whose profile row is keyed by its pk, so it
    # is the shape a school-side lookup has to resolve through the directory.
    'mock-hashed-token': {'sub': 'addd0ec45fbe222e313c56cf123a6ab99080a2723b8ab5df9f5c72ab7f07145a',
                          'name': 'Seed Admin', 'email': 'seed-admin@example.com', 'preferred_username': 'seed-admin',
                          'groups': ['Super Admins']},
    # A login whose pk is a *number*, as the real directory's are (`"pk":13`): the app keys a profile row as
    # `type::record('<table>', '<pk>')` — a string id — and a bare `admin_profile:9002` is a *different*
    # record that no lookup finds. The school's own admin is pk 5, so this is the shape their row had to be
    # keyed in (and the shape the sandbox's `mock_uuid_…` pks never exercise).
    'mock-numeric-admin-token': {'sub': '9002', 'uid': '9002', 'name': 'Seed Numeric Admin',
                                 'email': 'seed-numeric-admin@example.com', 'groups': ['Super Admins']},
}


def bearer_token(handler):
    header = handler.headers.get('Authorization') or ''
    return header[len('Bearer '):] if header.startswith('Bearer ') else ''


def jwt_claims(token):
    """The claims of a JWT-shaped token, or None when the string is not one.

    Only the payload is read. The signature is not checked: this mock stands in for the decision a
    real endpoint makes about a token it issued, not for the cryptography behind that decision.
    """
    parts = token.split('.')
    if len(parts) != 3:
        return None
    payload = parts[1] + '=' * (-len(parts[1]) % 4)
    try:
        claims = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    except (ValueError, UnicodeDecodeError):
        return None
    return claims if isinstance(claims, dict) else None


def claims_userinfo(token):
    """The userinfo body a JWT-shaped token stands for, or None when it stands for nobody.

    A token is honoured for a login the directory has and has not switched off, and only until its
    `exp` — the two refusals a real endpoint makes. The body is the directory's, not the token's:
    `groups` comes from the login's own group objects, which is what Authentik answers from too.
    """
    claims = jwt_claims(token)
    if claims is None:
        return None
    sub = str(claims.get('sub') or '')
    login = users.get(sub)
    exp = claims.get('exp')
    if not sub or login is None or not login['is_active']:
        return None
    if not isinstance(exp, (int, float)) or exp <= time.time():
        return None
    return {
        'sub': sub,
        'uid': sub,
        'name': login.get('name') or claims.get('name', ''),
        'email': login.get('email', ''),
        # The real userinfo carries the username too, and the app's password check sends it as the password
        # grant's `username` — the identifier Authentik's own identification stage expects.
        'preferred_username': login.get('username', ''),
        'groups': [group['name'] for group in login.get('groups_obj', [])],
    }


def pk_of(path):
    # `/api/v3/core/users/<pk>/` -> `<pk>` as text; None for the collection path itself.
    if not path.startswith(USERS_PATH):
        return None
    return path[len(USERS_PATH):].strip('/') or None


def send(handler, status, payload=None, spaced=False):
    # The REST API answers compact; the OIDC userinfo endpoint answers spaced ("field": "value")
    # like the real Authentik, which the backend's text scanners must tolerate.
    body = b'' if payload is None else (
        json.dumps(payload) if spaced else json.dumps(payload, separators=(",", ":"))
    ).encode()
    handler.send_response(status)
    if payload is not None:
        handler.send_header('Content-Type', 'application/json')
    handler.send_header('Content-Length', str(len(body)))
    handler.end_headers()
    if body:
        handler.wfile.write(body)


def read_body(handler):
    # The backend sends a Content-Length body; chunked is decoded too so a change there is not a
    # silent empty update.
    if (handler.headers.get('Transfer-Encoding') or '').lower() == 'chunked':
        chunks = []
        while True:
            size = int(handler.rfile.readline().strip() or b'0', 16)
            if size == 0:
                handler.rfile.readline()
                break
            chunks.append(handler.rfile.read(size))
            handler.rfile.readline()
        return b''.join(chunks)
    length = int(handler.headers.get('Content-Length') or 0)
    return handler.rfile.read(length) if length else b''


def read_json(handler):
    raw = read_body(handler)
    try:
        return json.loads(raw.decode() or '{}')
    except (UnicodeDecodeError, json.JSONDecodeError):
        print(f"mock Authentik: unreadable body ({len(raw)} bytes) on {handler.path}", file=sys.stderr)
        return {}


class MockHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/application/o/authorize/':
            redirect_uri = parse_qs(parsed.query).get('redirect_uri', ['http://localhost:9090/'])[0]
            self.send_response(302)
            self.send_header('Location', f"{redirect_uri}#access_token=dev-skip&expires_in=3600")
            self.end_headers()
        elif parsed.path.rstrip('/') == USERINFO_PATH.rstrip('/'):
            global userinfo_calls
            userinfo_calls += 1
            token = bearer_token(self)
            body = userinfo.get(token)
            if body is None:
                body = claims_userinfo(token)
            if body is None:
                send(self, 401, {'detail': 'Invalid token.'})
            else:
                send(self, 200, body, spaced=True)
        elif parsed.path.rstrip('/') == '/userinfo_calls':
            send(self, 200, {'count': userinfo_calls})
        elif parsed.path.rstrip('/') == '/password_sets':
            send(self, 200, password_sets)
        elif pk_of(parsed.path) is None and parsed.path.rstrip('/') == USERS_PATH.rstrip('/'):
            query = parse_qs(parsed.query)
            page_size = max(1, int(query.get('page_size', ['20'])[0]))
            page = max(1, int(query.get('page', ['1'])[0]))
            # Mixed pk types (a number for a real login, a string in this mock) are compared as text:
            # the listing is a stable order, not a numeric one.
            listing = sorted(users.values(), key=lambda user: str(user['pk']))
            start = (page - 1) * page_size
            window = listing[start:start + page_size]
            send(self, 200, {
                'pagination': {
                    'next': 0,
                    'previous': 0,
                    'count': len(listing),
                    'current': page,
                    'total_pages': max(1, -(-len(listing) // page_size)),
                    'start_index': start + 1,
                    'end_index': start + len(window),
                },
                'results': window,
            })
        else:
            send(self, 404, {'detail': 'Not found.'})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == TOKEN_PATH:
            # The password grant: what the app's backend calls to check a *current* password. It answers the
            # way the real provider does — a token when the credentials are right, `invalid_grant` when they
            # are not — and accepts one fixed password for any login it knows, so a suite can drive both.
            form = parse_qs(self.rfile.read(int(self.headers.get('Content-Length', 0))).decode())
            if (form.get('grant_type') or [''])[0] != 'password':
                return send(self, 400, '{"error":"unsupported_grant_type"}')
            identifier = (form.get('username') or [''])[0]
            password = (form.get('password') or [''])[0]
            login = next((u for u in users.values()
                          if u.get('username') == identifier or u.get('email') == identifier
                          or (u.get('attributes') or {}).get('upn') == identifier), None)
            if login is None or password != MOCK_PASSWORD:
                return send(self, 400, '{"error":"invalid_grant","error_description":"Invalid credentials"}')
            return send(self, 200, '{"access_token":"mock-password-grant-token","token_type":"Bearer","expires_in":300}')
        self._post_legacy()

    def _post_legacy(self):
        path = urlparse(self.path).path
        set_password = path.endswith('/set_password/')
        if set_password:
            pk = pk_of(path[:-len('/set_password/')])
            if pk is None or pk not in users:
                send(self, 404, {'detail': 'Not found.'})
                return
            body = read_json(self)
            password_sets[pk] = body.get('password', '')
            send(self, 204)
        elif path == USERS_PATH:
            body = read_json(self)
            pk = next_pk()
            email = body.get('email', '')
            users[str(pk)] = {
                'pk': pk,
                'username': body.get('username', email),
                'name': body.get('name', ''),
                'email': email,
                'is_active': True,
                'groups': [],
                # Created without a group, as Authentik creates one: the login is in the directory but
                # in no role's tab until an admin puts it in a group.
                'groups_obj': [],
                # Whatever the app asked for — the school number's short form lands here as `upn`, which
                # the grant above matches as well as the username (the real provider's identification
                # stage does the same when its UPN user field is ticked).
                'attributes': body.get('attributes') or {},
            }
            send(self, 201, users[str(pk)])
        else:
            send(self, 404, {'detail': 'Not found.'})

    def do_PATCH(self):
        pk = pk_of(urlparse(self.path).path)
        if pk is None or pk not in users:
            send(self, 404, {'detail': 'Not found.'})
            return
        for field, value in read_json(self).items():
            users[pk][field] = value
        send(self, 200, users[pk])

    def do_DELETE(self):
        pk = pk_of(urlparse(self.path).path)
        if pk is None or users.pop(pk, None) is None:
            send(self, 404, {'detail': 'Not found.'})
            return
        send(self, 204)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    print(f"mock Authentik on http://127.0.0.1:{PORT}")
    HTTPServer(('127.0.0.1', PORT), MockHandler).serve_forever()
