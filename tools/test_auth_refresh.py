#!/usr/bin/env python3
"""Test thirty-day login across real Godot processes and an isolated FalkorDB API."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request
import uuid

PROJECT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    database = os.environ.get("FALKORDB_TEST_URL", "redis://127.0.0.1:6379")
    graph = "rescene_session_test_" + uuid.uuid4().hex
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="rescene-auth-refresh-") as directory:
        temp = Path(directory)
        binary = temp / "api"
        subprocess.run(["go", "build", "-buildvcs=false", "-o", str(binary), "."], cwd=PROJECT / "backend", check=True)
        server_env = dict(os.environ, APP_ENV="development", ADDR=f"127.0.0.1:{port}",
                          FALKORDB_URL=database, FALKORDB_GRAPH=graph, DATA_DIR=str(temp / "keys"),
                          LEADERBOARD_ENABLED="false",STARLIGHT_ENABLED="false",MARKETPLACE_ENABLED="false",SHOP_ENABLED="false")
        server_env.pop("ENGINE_API_KEY", None)
        server_env.pop("JWT_SECRET", None)
        auth_file = temp / "session.txt"
        client_env = dict(os.environ, RESCENE_API_URL=f"http://127.0.0.1:{port}", RESCENE_AUTH_FILE=str(auth_file))
        server = None

        def redis(*command):
            return json.loads(subprocess.check_output(["redis-cli", "-u", database, "--json", *command], text=True))

        def start():
            nonlocal server
            server = subprocess.Popen([str(binary)], cwd=PROJECT / "backend", env=server_env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen(client_env["RESCENE_API_URL"] + "/healthz", timeout=1) as response:
                        if response.status == 200:
                            return
                except OSError:
                    time.sleep(0.1)
            raise RuntimeError("Session test API did not become ready")

        def stop():
            nonlocal server
            if server is not None:
                server.terminate()
                server.wait(timeout=10)
            server = None

        def game(mode, **extra):
            result = subprocess.run([args.godot, "--headless", "--path", str(PROJECT), "--script",
                                     "res://tests/refresh_persistence_regression.gd"],
                                    env=dict(client_env, RESCENE_AUTH_TEST_MODE=mode, **extra),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=35)
            print(result.stdout, end="", flush=True)
            if result.returncode or "ERROR:" in result.stdout or "WARNING:" in result.stdout:
                raise RuntimeError(f"Session test {mode} failed")

        try:
            start()
            form_test = subprocess.run([args.godot, "--headless", "--path", str(PROJECT), "--script",
                                        "res://tests/password_form_regression.gd"], env=client_env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=35)
            print(form_test.stdout, end="", flush=True)
            if form_test.returncode or "ERROR:" in form_test.stdout or "WARNING:" in form_test.stdout:
                raise RuntimeError("Password form regression failed")
            game("seed")
            assert auth_file.stat().st_mode & 0o777 == 0o600, "Session file must be owner-only"
            game("restore")
            # The refresh endpoint must work independently of access-token validity.
            saved = json.loads(auth_file.read_text())
            saved["access_token"] = "expired-access-fixture"
            auth_file.write_text(json.dumps(saved))
            game("restore_expired_access")
            game("exercise")
            game("prepare_lost_response")
            stop()
            start()
            game("restore_lost_response")
            game("restore_after_server_restart")
            # Transient outages must not delete the user's refresh credential.
            stop()
            game("offline")
            start()
            game("restore")
            game("logout")
            game("legacy")
            # Only the isolated test graph's session expiry is advanced.
            redis("GRAPH.QUERY", graph, "MATCH (s:LoginSession) SET s.expires_at=1 RETURN count(s)")
            game("expire_refresh")
            auth_file.write_text('{"version":2,"refresh_token":"invalid","access_token":"invalid"}')
            game("invalid")
            print("30-day refresh, restart, rotation, lost-response recovery and logout: PASS")
        finally:
            stop()
            redis("GRAPH.DELETE", graph)


if __name__ == "__main__":
    main()
