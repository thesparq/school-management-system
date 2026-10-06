#!/usr/bin/env python3
"""SPA-aware static file server.

Serves files from the www/ directory. Any request that doesn't match a real
file gets served index.html instead, so client-side routing works correctly.
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9090
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'www')

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        # Strip query string for file lookup
        path = self.path.split('?')[0].split('#')[0]
        file_path = os.path.join(DIRECTORY, path.lstrip('/'))

        # If it's a real file, serve it normally
        if os.path.isfile(file_path):
            super().do_GET()
        else:
            # SPA fallback: serve index.html for all non-file routes
            self.path = '/index.html'
            super().do_GET()

if __name__ == '__main__':
    with http.server.HTTPServer(('', PORT), SPAHandler) as httpd:
        print(f"SPA server running on http://localhost:{PORT} (serving {DIRECTORY})")
        httpd.serve_forever()
