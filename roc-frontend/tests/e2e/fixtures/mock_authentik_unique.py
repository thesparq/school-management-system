# Minimal Authentik stand-in for the admin checks.
#
# Like the repo root's mock_authentik.py, but it keeps a real user table, which is what the
# identity/profile split needs: POST creates a login with a fresh `pk`, GET lists the logins in
# Authentik's own shape (`{"pagination": {…}, "results": [{pk, email, name, is_active, …}, …]}`),
# PATCH updates the fields it is given (the backend sends `{"email": …}` and `{"is_active": false}`)
# and DELETE removes one. An unknown pk answers 404, the way Authentik does, so the backend's
# cannot-disable-this-login path is observable instead of silently succeeding.
#
#   python3 tests/e2e/fixtures/mock_authentik_unique.py [port]
#
# The port defaults to 9000 and can also come from MOCK_AUTHENTIK_PORT, so several sandboxes can run
# side by side.
#
# Then point the backend at it:
#   AUTHENTIK_API_URL=http://127.0.0.1:9000/api/v3/core/users/ AUTHENTIK_API_TOKEN=mock

from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import itertools
import json
import os
import sys

PORT = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MOCK_AUTHENTIK_PORT', '9000'))
USERS_PATH = '/api/v3/core/users/'
counter = itertools.count(1)
users = {}  # pk -> the login, exactly as the list endpoint returns it


def pk_of(path):
    # `/api/v3/core/users/<pk>/` -> `<pk>`; None for the collection path itself.
    if not path.startswith(USERS_PATH):
        return None
    return path[len(USERS_PATH):].strip('/') or None


def send(handler, status, payload=None):
    body = b'' if payload is None else json.dumps(payload, separators=(",", ":")).encode()
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
        elif pk_of(parsed.path) is None and parsed.path.rstrip('/') == USERS_PATH.rstrip('/'):
            query = parse_qs(parsed.query)
            page_size = max(1, int(query.get('page_size', ['20'])[0]))
            page = max(1, int(query.get('page', ['1'])[0]))
            listing = sorted(users.values(), key=lambda user: user['pk'])
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
        if urlparse(self.path).path == USERS_PATH:
            body = read_json(self)
            pk = f"mock_uuid_{next(counter)}"
            email = body.get('email', '')
            users[pk] = {
                'pk': pk,
                'username': body.get('username', email),
                'name': body.get('name', ''),
                'email': email,
                'is_active': True,
                'groups': [],
            }
            send(self, 201, users[pk])
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
