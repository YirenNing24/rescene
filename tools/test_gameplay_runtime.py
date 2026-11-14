#!/usr/bin/env python3
"""Local start-queue fixture and GPU stress check; renderer errors fail the run."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--render-output', default='res://builds/gameplay-corrected.json')
    parser.add_argument('--max-momentum', action='store_true')
    args = parser.parse_args()
    run_received = threading.Event()
    wallet_started = threading.Event()
    queue_bypassed = threading.Event()

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def respond(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            wallet_started.set()
            if run_received.wait(3):
                queue_bypassed.set()
            self.respond(200, {'starlight': {}})

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            if self.path.endswith('/auth/refresh'):
                self.respond(200, {'user': {'id': 'runtime-fixture'}, 'access_token': 'renewed-access',
                                  'refresh_token': 'r' * 43, 'expires_in': 3600,
                                  'refresh_expires_in': 2592000})
                return
            if self.headers.get('Authorization') == 'Bearer rejected-access':
                self.respond(401, {'error': {'message': 'Refresh required'}})
                return
            if not wallet_started.wait(2):
                self.respond(500, {'error': {'message': 'Fixture wallet did not start'}})
                return
            run_received.set()
            if body.get('delay'):
                time.sleep(0.15)
            self.respond(200, {'reward': {'id': 'fixture-run', 'deck_ids': []}})

    def run(script, environment, render=False):
        command = [args.godot, '--path', str(ROOT), '--script', script]
        command += ['--resolution', '1600x720', '--', args.render_output] if render else ['--headless']
        if render and args.max_momentum:
            command.append('--max-momentum')
        result = subprocess.run(command, env=environment, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=90)
        log = ROOT / 'builds' / (Path(args.render_output).stem + '.log' if render else 'gameplay-start.log')
        log.write_text(result.stdout)
        if result.returncode or 'ERROR:' in result.stdout:
            print(result.stdout[-6000:])
            raise RuntimeError(f'{script} failed; inspect {log}')
        print(f'{script}: PASS (no engine/script errors)')

    with ThreadingHTTPServer(('127.0.0.1', 0), Fixture) as server, tempfile.TemporaryDirectory(prefix='rhythm-start-') as temporary:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            environment = dict(os.environ, RESCENE_API_URL=f'http://127.0.0.1:{server.server_port}',
                               RESCENE_AUTH_FILE=str(Path(temporary) / 'session.txt'))
            run('res://tests/gameplay_start_regression.gd', environment)
            assert queue_bypassed.is_set(), 'Start waited for the unrelated wallet read'
        finally:
            server.shutdown()
            worker.join()
    if args.render:
        run('res://tools/benchmark_gameplay.gd', os.environ, render=True)


if __name__ == '__main__':
    main()
