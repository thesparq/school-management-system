# Minimal Authentik stand-in for the admin check.
#
# Like the repo root's mock_authentik.py, but it hands out a distinct `pk` per create (so each role's
# profile gets its own record id) and accepts DELETE, which the backend calls to compensate when a
# profile write fails.
#
#   python3 tests/e2e/fixtures/mock_authentik_unique.py
#
# Then point the backend at it:
#   AUTHENTIK_API_URL=http://127.0.0.1:9000/api/v3/core/users/ AUTHENTIK_API_TOKEN=mock

from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import itertools
import json

PORT = 9000
counter = itertools.count(1)


class MockHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/application/o/authorize/':
            redirect_uri = parse_qs(parsed.query).get('redirect_uri', ['http://localhost:9090/'])[0]
            self.send_response(302)
            self.send_header('Location', f"{redirect_uri}#access_token=dev-skip&expires_in=3600")
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/api/v3/core/users/':
            pk = f"mock_uuid_{next(counter)}"
            body = json.dumps({"pk": pk}, separators=(",", ":")).encode()
            self.send_response(201)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_DELETE(self):
        # Succeeds so the compensation path can be observed end to end.
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    print(f"mock Authentik on http://127.0.0.1:{PORT}")
    HTTPServer(('127.0.0.1', PORT), MockHandler).serve_forever()
