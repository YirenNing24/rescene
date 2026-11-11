#!/usr/bin/env python3
"""Real native photo uploads and restart persistence in a disposable graph."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    graph = 'rescene_photos_test_' + uuid.uuid4().hex
    database = os.environ.get('FALKORDB_TEST_URL', 'redis://127.0.0.1:6379')
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix='rescene-photos-') as directory:
        temp = Path(directory)
        binary = temp / 'api'
        subprocess.run(['go', 'build', '-buildvcs=false', '-o', str(binary), '.'], cwd=ROOT / 'backend', check=True)
        env = dict(os.environ, APP_ENV='development', ADDR=f'127.0.0.1:{port}', FALKORDB_URL=database,
                   FALKORDB_GRAPH=graph, DATA_DIR=str(temp / 'keys'), PROFILE_MEDIA_DIR=str(temp / 'photos'),
                   ENGINE_API_KEY='', ENGINE_PROJECT_ID='', MARKETPLACE_ENABLED='false', SHOP_ENABLED='false',
                   CARDS_ENABLED='false', PULSE_CARDS_ADDRESS='', STARLIGHT_ENABLED='false', LEADERBOARD_ENABLED='false')
        env.pop('JWT_SECRET', None)
        game_env = dict(os.environ, RESCENE_API_URL=f'http://127.0.0.1:{port}',
                        RESCENE_AUTH_FILE=str(temp / 'session.json'), RESCENE_MEDIA_TEST_DIR=directory)
        server = None

        def start():
            nonlocal server
            server = subprocess.Popen([str(binary)], cwd=ROOT / 'backend', env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen(game_env['RESCENE_API_URL'] + '/healthz', timeout=1):
                        return
                except OSError:
                    if server.poll() is not None:
                        raise RuntimeError('Photo fixture API exited')
                    time.sleep(0.1)
            raise TimeoutError('Photo fixture API did not start')

        def stop():
            nonlocal server
            if server and server.poll() is None:
                server.terminate()
                server.wait(timeout=10)
            server = None

        try:
            for phase in ('upload', 'restore'):
                start()
                game_env['RESCENE_MEDIA_TEST_PHASE'] = phase
                command = [args.godot, '--path', str(ROOT), '--script', 'res://tests/profile_media_regression.gd']
                if not args.capture:
                    command.insert(1, '--headless')
                result = subprocess.run(command, env=game_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, timeout=120)
                print(result.stdout, end='', flush=True)
                if result.returncode or 'ERROR:' in result.stdout or 'WARNING:' in result.stdout:
                    raise RuntimeError(f'Native photo test failed in {phase}')
                stop()
            print('Native avatars/gallery, expired JWT refresh, restart persistence and view-only public profiles: PASS')
        finally:
            stop()
            subprocess.run(['redis-cli', '-u', database, 'GRAPH.DELETE', graph], stdout=subprocess.DEVNULL, check=True)


if __name__ == '__main__':
    main()
