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
import itertools
import json
import os
import sys

PORT = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MOCK_AUTHENTIK_PORT', '9000'))
USERS_PATH = '/api/v3/core/users/'
USERINFO_PATH = '/application/o/userinfo/'
counter = itertools.count(1)
# Every pk this process hands out carries the process id, so a restarted mock cannot re-issue a pk an
# earlier run already wrote a profile under (the sandbox database outlives the mock, and a colliding
# create fails on the record id). Created logins get a **number**, the way Authentik's own API sends a
# pk (`"pk":15`): a mock that only ever sends string pks cannot catch a reader that misses the number
# form, and missing it is how a created login's profile row gets written under a placeholder id.
pk_prefix = f"mock_uuid_{os.getpid()}"
users = {}  # pk (as text) -> the login, exactly as the list endpoint returns it
password_sets = {}  # pk -> the password the app asked to set (so tests can assert the call landed)


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
}


def bearer_token(handler):
    header = handler.headers.get('Authorization') or ''
    return header[len('Bearer '):] if header.startswith('Bearer ') else ''


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
            body = userinfo.get(bearer_token(self))
            if body is None:
                send(self, 401, {'detail': 'Invalid token.'})
            else:
                send(self, 200, body, spaced=True)
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
