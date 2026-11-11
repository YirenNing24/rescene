#!/usr/bin/env python3
"""Real FalkorDB + Fiber + Godot integration; disposable graph/accounts only."""
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
    parser.add_argument("--capture", action="store_true", help="Render native screenshots too")
    args = parser.parse_args()
    database = os.environ.get("FALKORDB_TEST_URL", "redis://127.0.0.1:6379")
    graph = "rescene_ui_test_" + uuid.uuid4().hex
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="rescene-progression-") as directory:
        temp = Path(directory)
        binary = temp / "rescene-api"
        subprocess.run(["go", "build", "-buildvcs=false", "-o", str(binary), "."], cwd=PROJECT / "backend", check=True)
        server_env = dict(os.environ, APP_ENV="development", ADDR=f"127.0.0.1:{port}",
                          FALKORDB_URL=database, FALKORDB_GRAPH=graph, DATA_DIR=str(temp / "keys"))
        server_env.pop("JWT_SECRET", None)
        # Never create real Engine wallets for disposable game test accounts.
        server_env.pop("ENGINE_API_KEY", None)
        server_env["LEADERBOARD_ENABLED"] = "false"
        server_env.update(STARLIGHT_ENABLED="false", MARKETPLACE_ENABLED="false", SHOP_ENABLED="false")
        marker = temp / "marker.json"
        environment = dict(os.environ, RESCENE_API_URL=f"http://127.0.0.1:{port}",
                           RESCENE_AUTH_FILE=str(temp / "token.txt"), RESCENE_PROGRESS_MARKER=str(marker))
        backend = None
        game = None

        def redis(*command):
            output = subprocess.check_output(["redis-cli", "-u", database, "--json", *command], text=True)
            return json.loads(output)

        def start_backend():
            nonlocal backend
            backend = subprocess.Popen([str(binary)], cwd=PROJECT / "backend", env=server_env,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen(environment["RESCENE_API_URL"] + "/healthz", timeout=1) as response:
                        if response.status == 200:
                            return
                except OSError:
                    pass
                if backend.poll() is not None:
                    raise RuntimeError("Test API exited during startup")
                time.sleep(0.1)
            raise TimeoutError("Test API was not ready")

        def stop_backend():
            nonlocal backend
            if backend is not None and backend.poll() is None:
                backend.terminate()
                backend.wait(timeout=10)
            backend = None

        def wait_file(path):
            deadline = time.monotonic() + 30
            while not path.exists():
                if game.poll() is not None:
                    raise RuntimeError("Game exited before preparing the test fixture")
                if time.monotonic() >= deadline:
                    raise TimeoutError("Game did not prepare the test fixture")
                time.sleep(0.05)

        def age_ticket():
            wait_file(marker)
            identity = json.loads(marker.read_text())
            # Controlled fixture clock adjustment, never a public/debug HTTP route.
            selector = "MATCH (p:Progression {owner:" + json.dumps(identity["user_id"]) + "})"
            raw = redis("GRAPH.QUERY", graph, selector + " RETURN p.payload,p.version")
            payload, version = raw[1][0]
            state = json.loads(payload)
            assert state["active"]["id"] == identity["run_id"]
            state["active"]["started_at"] -= 180000
            query = (selector + " WHERE p.version=" + str(version) + " SET p.payload=" +
                     json.dumps(json.dumps(state)) + ",p.version=p.version+1 RETURN p.version")
            redis("GRAPH.QUERY", graph, query)
            Path(str(marker) + ".ready").touch()

        def run_game(script, prepare=False, disconnect=False):
            nonlocal game
            marker.unlink(missing_ok=True)
            for suffix in (".ready", ".disconnect", ".offline"):
                Path(str(marker) + suffix).unlink(missing_ok=True)
            command = [args.godot, "--path", str(PROJECT), "--script", "res://tests/" + script]
            if not args.capture:
                command.insert(1, "--headless")
            log_path = temp / (script + ".log")
            with log_path.open("w") as output:
                game = subprocess.Popen(command, env=environment, stdout=output, stderr=subprocess.STDOUT)
            try:
                if prepare:
                    age_ticket()
                if disconnect:
                    wait_file(Path(str(marker) + ".disconnect"))
                    stop_backend()
                    Path(str(marker) + ".offline").touch()
                code = game.wait(timeout=45)
            except BaseException:
                print(log_path.read_text(), end="", flush=True)
                raise
            game = None
            log = log_path.read_text()
            print(log, end="", flush=True)
            if code or "ERROR:" in log or "WARNING:" in log:
                raise RuntimeError(f"{script} failed (exit {code}); Godot diagnostics must also be clean")

        try:
            start_backend()
            run_game("auth_flow_regression.gd")
            run_game("progression_flow_regression.gd", prepare=True)
            run_game("progression_pending_regression.gd", prepare=True, disconnect=True)
            start_backend()
            run_game("progression_restart_regression.gd")
            run_game("energy_flow_regression.gd")
            print("Progression integration, restart and interrupted sync: PASS", flush=True)
        finally:
            if game is not None and game.poll() is None:
                game.terminate()
                game.wait(timeout=5)
            stop_backend()
            redis("GRAPH.DELETE", graph)


if __name__ == "__main__":
    main()
