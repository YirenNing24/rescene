#!/usr/bin/env python3
"""Exercise native follows, online friends and chat against a disposable graph."""
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    database = os.environ.get('FALKORDB_TEST_URL', 'redis://127.0.0.1:6379')
    graph = 'rescene_social_test_' + uuid.uuid4().hex
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    origin = f'http://127.0.0.1:{port}'
    with tempfile.TemporaryDirectory(prefix='rescene-social-') as directory:
        temp = Path(directory)
        binary = temp / 'api'
        subprocess.run(['go', 'build', '-buildvcs=false', '-o', str(binary), '.'], cwd=ROOT / 'backend', check=True)
        env = dict(os.environ, APP_ENV='development', ADDR=f'127.0.0.1:{port}', FALKORDB_URL=database,
                   FALKORDB_GRAPH=graph, DATA_DIR=str(temp / 'keys'), PROFILE_MEDIA_DIR=str(temp / 'photos'),
                   ENGINE_API_KEY='', ENGINE_PROJECT_ID='', MARKETPLACE_ENABLED='false', SHOP_ENABLED='false',
                   CARDS_ENABLED='false', PULSE_CARDS_ADDRESS='', STARLIGHT_ENABLED='false', LEADERBOARD_ENABLED='false')
        env.pop('JWT_SECRET', None)
        backend = None
        lost = {'done': False}
        lock = threading.Lock()

        class Proxy(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def dispatch(self):
                data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                headers = {k: v for k, v in self.headers.items() if k.lower() not in ('host', 'connection', 'content-length')}
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=25)
                try:
                    connection.request(self.command, self.path, data, headers)
                    upstream = connection.getresponse()
                    raw = upstream.read()
                    status = upstream.status
                    content_type = upstream.getheader('Content-Type', 'application/json')
                    # Lose one successful result after the server commits it.
                    with lock:
                        if self.command == 'POST' and self.path.endswith('/messages') and status == 200 and not lost['done']:
                            lost['done'] = True
                            status = 503
                            raw = b'{"error":{"message":"Simulated lost send response"}}'
                    self.send_response(status)
                    self.send_header('Content-Type', content_type)
                    self.send_header('Content-Length', str(len(raw)))
                    self.end_headers()
                    self.wfile.write(raw)
                except (OSError, http.client.HTTPException):
                    self.send_error(503)
                finally:
                    connection.close()

            do_GET = dispatch
            do_POST = dispatch
            do_PUT = dispatch
            do_DELETE = dispatch

        proxy = ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
        threading.Thread(target=proxy.serve_forever, daemon=True).start()

        def query(cypher):
            return json.loads(subprocess.check_output(['redis-cli', '-u', database, '--json', 'GRAPH.QUERY', graph, cypher], text=True))

        def api(path, token='', body=None, raw=None):
            req = urllib.request.Request(origin + path, data=raw if raw is not None else json.dumps(body).encode() if body is not None else None,
                                         headers={'Content-Type': 'application/octet-stream' if raw is not None else 'application/json',
                                                  'Authorization': 'Bearer ' + token} if token else {'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=20) as response:
                return json.load(response)

        def start():
            nonlocal backend
            backend = subprocess.Popen([str(binary)], cwd=ROOT / 'backend', env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                try:
                    api('/healthz')
                    return
                except OSError:
                    if backend.poll() is not None:
                        raise RuntimeError('Social fixture API exited')
                    time.sleep(0.1)
            raise TimeoutError('Social fixture API did not start')

        def stop():
            nonlocal backend
            if backend and backend.poll() is None:
                backend.terminate()
                backend.wait(timeout=10)
            backend = None

        try:
            start()
            policy = json.loads((ROOT / 'assets/legal/policies.json').read_text())
            main_account = api('/api/v1/auth/register', body={'username': 'ReMine', 'password': 'social-fixture-password', 'accept_policies': True, 'terms_version': policy['version'], 'privacy_version': policy['version']})
            owner = main_account['user']['id']
            owner_token = main_account['access_token']
            friends = []
            # Seed disposable accounts with the same test-only password hash.
            # This bypasses the public registration limiter without weakening it.
            names = ['Luna', 'Mira', 'Yuna', 'Aria', 'Noel', 'Sora', 'NewScene']
            for index, name in enumerate(names):
                uid = uuid.uuid4().hex
                query('MATCH(u:User {id:' + json.dumps(owner) + '}) CREATE(v:User {id:' + json.dumps(uid) +
                      ',username:' + json.dumps(name) + ',username_key:' + json.dumps(name.lower()) +
                      ',created_at:"fixture",password_hash:u.password_hash}) RETURN v.id')
                login = api('/api/v1/auth/login', body={'username': name, 'password': 'social-fixture-password'})
                token = login['access_token']
                api('/api/v1/social/players/' + owner + '/follow', token, {'enabled': True})
                if index < 6:
                    api('/api/v1/social/players/' + uid + '/follow', owner_token, {'enabled': True})
                api('/api/v1/social/presence', token, {'device_id': 'a' * 32, 'online': index < 5, 'activity': 'lobby'})
                photo = ROOT / 'output/cards/pulse-le-set/sources' / f'{index + 1:02}.jpg'
                if not photo.exists():
                    photo = next((ROOT / 'output/cards/pulse-le-set/sources').glob('*.jpg'))
                api('/api/v1/profile/media/avatar', token, raw=photo.read_bytes())
                friends.append({'id': uid, 'username': name, 'token': token})
            luna = friends[0]
            texts = [
                (luna['token'], owner, 'Hey! Ready for another round of With?'),
                (owner_token, luna['id'], 'Absolutely. That last chorus is my favourite.'),
                (luna['token'], owner, 'Same! I finally got a full combo on Normal.'),
                (luna['token'], owner, 'Let’s try Hard next. Good luck ✨'),
            ]
            for token, peer_id, text in texts:
                api('/api/v1/social/conversations/' + peer_id + '/messages', token,
                    {'request_id': uuid.uuid4().hex, 'text': text})
            fixture = temp / 'fixture.json'
            fixture.write_text(json.dumps({'owner': owner, 'friends': friends}))
            fixture.chmod(0o600)
            game_env = dict(os.environ, RESCENE_API_URL=f'http://127.0.0.1:{proxy.server_port}',
                            RESCENE_AUTH_FILE=str(temp / 'session.json'), RESCENE_SOCIAL_FIXTURE=str(fixture))
            for phase in ('exercise', 'restore'):
                game_env['RESCENE_SOCIAL_PHASE'] = phase
                command = [args.godot, '--path', str(ROOT), '--script', 'res://tests/social_regression.gd']
                if not args.capture:
                    command.insert(1, '--headless')
                result = subprocess.run(command, env=game_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
                print(result.stdout, end='', flush=True)
                if result.returncode or 'ERROR:' in result.stdout or 'WARNING:' in result.stdout:
                    raise RuntimeError(f'Native social test failed in {phase}')
                if phase == 'exercise':
                    if not lost['done']:
                        raise AssertionError('Lost-send fixture did not execute')
                    rows = query('MATCH(m:DirectMessage) WHERE m.body="On my way! Let’s make it a full combo." RETURN count(m)')
                    if rows[1][0][0] != 1:
                        raise AssertionError('Lost send duplicated or lost its message')
                    stop()
                    start()
            print('Real native online-friend rail, followers/following, chat, lost-response recovery, blocks and restart: PASS')
        finally:
            proxy.shutdown()
            proxy.server_close()
            stop()
            subprocess.run(['redis-cli', '-u', database, 'GRAPH.DELETE', graph], stdout=subprocess.DEVNULL, check=True)


if __name__ == '__main__':
    main()
