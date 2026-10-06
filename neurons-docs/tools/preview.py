"""Preview the *production build* under the production base path.

For day-to-day editing use `hugo server` instead (live reload). This script
serves the output of `hugo --minify` (public/) at http://localhost:8080/neurons/
and answers 404 for anything outside /neurons/, so a URL that would break in
production also breaks here.

Usage (from the project root):  hugo --minify && python tools/preview.py [port]
Development helper only — it is not deployed.
"""
import http.server
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "public"
PREFIX = "/neurons"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def _route(self):
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        if path == PREFIX:
            self.send_response(301)
            self.send_header("Location", PREFIX + "/")
            self.end_headers()
            return False
        if not path.startswith(PREFIX + "/"):
            self.send_error(404, "Outside the /neurons/ base path")
            return False
        self.path = self.path[len(PREFIX):]
        return True

    def do_GET(self):
        if self._route():
            super().do_GET()

    def do_HEAD(self):
        if self._route():
            super().do_HEAD()


if __name__ == "__main__":
    if not (ROOT / "index.html").exists():
        sys.exit("public/ is empty: run `hugo --minify` first.")
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler) as httpd:
        print(f"Neurons docs: http://localhost:{port}{PREFIX}/  (Ctrl+C to stop)")
        httpd.serve_forever()
