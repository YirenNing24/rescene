#!/usr/bin/env python3
"""Exercise the real GDScript downloader against an isolated byte-range fixture."""
from __future__ import annotations
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
DATA = (b'RESCENE verified update fixture\x00' * 110000)[:3145728]
CERT = '732a79726c4e08da0a2ccf7a26e56326288df5ccb53629a0eec315598371c299'
state: dict[str, object] = {'mode': 'normal', 'resumed': False}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format: str, *args: object) -> None:
        pass

    def send_json(self, data: object) -> None:
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        mode = str(state['mode'])
        if self.path.startswith('/control/'):
            state['mode'] = self.path.rsplit('/', 1)[-1]
            self.send_json({'ok': True})
        elif self.path == '/stats':
            self.send_json({'resumed': state['resumed']})
        elif self.path == '/updates/android.json':
            self.send_json({'version': '9.9.9', 'version_code': 999999, 'bytes': len(DATA), 'sha256': '0' * 64 if mode == 'corrupt' else hashlib.sha256(DATA).hexdigest(), 'signing_certificate_sha256': CERT, 'download_url': f'http://127.0.0.1:{self.server.server_port}/updates/android/9.9.9/RESCENE-Rhythm.apk', 'release_notes': 'Isolated regression fixture.'})
        elif self.path == '/updates/android/9.9.9/RESCENE-Rhythm.apk':
            offset = int(self.headers.get('Range', 'bytes=0-').split('=')[1].split('-')[0])
            if offset:
                state['resumed'] = True
            self.send_response(200 if mode == 'full_response' else 206)
            self.send_header('Content-Length', str(len(DATA) - offset))
            self.send_header('Content-Range', f'bytes {offset + (1 if mode == "bad_range" else 0)}-{len(DATA)-1}/{len(DATA)}')
            self.end_headers()
            try:
                self.wfile.write(DATA[offset:offset + 262144] if mode == 'disconnect' else DATA[offset:])
            except (ConnectionResetError, BrokenPipeError):
                pass
        else:
            self.send_error(404)

def main() -> None:
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        result = subprocess.run(['/home/paulanthonyarriola/Desktop/Godot_v4.7.2-stable_linux.x86_64', '--headless', '--path', str(ROOT), '--script', 'res://tests/app_updates_regression.gd'], env=dict(os.environ, RESCENE_UPDATE_TEST_ORIGIN=f'http://127.0.0.1:{server.server_port}'), capture_output=True, text=True, timeout=120)
        print(result.stdout, end='')
        print(result.stderr, end='')
        if result.returncode or 'ERROR:' in result.stdout + result.stderr:
            raise SystemExit(result.returncode or 1)
    finally:
        server.shutdown()
        server.server_close()

if __name__ == '__main__':
    main()
