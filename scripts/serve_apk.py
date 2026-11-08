"""Serve exactly the family APK on loopback, for a private Tailscale download."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import re
import shutil
import sys

DIST = Path(__file__).resolve().parents[1] / 'dist'


def download_target(path):
    if path == '/health':
        return None, 'health'
    if path in ('/update.json', '/descargar/update.json'):
        return DIST/'android-update.json', 'json'
    if path in ('/windows-update.json', '/descargar/windows-update.json'):
        return DIST/'windows-update.json', 'json'
    if path in ('/', '/Mesa-Android.apk', '/descargar/Mesa-Android.apk'):
        return DIST/'Mesa-Android.apk', 'apk'
    match = re.fullmatch(r'/(?:descargar/)?(Mesa-Android-\d+\.\d+\.\d+-\d+\.apk)',path)
    if match:
        return DIST/match[1], 'apk'
    match = re.fullmatch(r'/(?:descargar/)?(Mesa-Setup-\d+\.\d+\.\d+-\d+-x64\.exe)',path)
    return (DIST/match[1], 'exe') if match else (None, 'missing')


class Download(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # PyInstaller --windowed has no stderr; BaseHTTPRequestHandler otherwise
        # crashes in send_response before sending even the HTTP status line.
        if sys.stderr is not None:
            super().log_message(format, *args)

    def deliver(self, body):
        target, kind = download_target(self.path)
        if kind == 'health':
            payload = b'{"product":"mesa-downloads","version":1}'
            self.send_response(200)
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(payload)))
            self.end_headers()
            if body: self.wfile.write(payload)
            return
        if kind == 'missing':
            self.send_error(404)
            return
        try:
            with target.open('rb') as source:
                self.send_response(200)
                mime = {'json':'application/json; charset=utf-8','apk':'application/vnd.android.package-archive','exe':'application/vnd.microsoft.portable-executable'}[kind]
                self.send_header('Content-Type', mime)
                if kind in ('apk','exe'): self.send_header('Content-Disposition', f'attachment; filename="{target.name}"')
                self.send_header('Content-Length', str(os.fstat(source.fileno()).st_size))
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                if body:
                    shutil.copyfileobj(source, self.wfile, 1024 * 1024)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except FileNotFoundError:
            self.send_error(404)

    def do_GET(self):
        self.deliver(True)

    def do_HEAD(self):
        self.deliver(False)


if __name__ == '__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=DIST)
    parser.add_argument('--port',type=int,default=8768)
    args=parser.parse_args()
    if not args.directory.is_dir() or not 1024 <= args.port <= 65535: parser.error('Directorio o puerto incorrectos.')
    DIST=args.directory.resolve()
    ThreadingHTTPServer(('127.0.0.1', args.port), Download).serve_forever()
