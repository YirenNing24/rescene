#!/usr/bin/env python3
"""Game/Fiber/FalkorDB integration against a local HTTPS Engine fixture."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid

PROJECT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()
    database = os.environ.get("FALKORDB_TEST_URL", "redis://127.0.0.1:6379")
    graph = "rescene_wallet_ui_" + uuid.uuid4().hex
    wallets = {}
    requests = []

    class EngineFixture(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            if self.path != "/v1/user-wallets/managed" or self.headers.get("X-GMR-Engine-Key") != "fixture-key-never-a-real-credential":
                self.send_error(403)
                return
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            assert body["authProvider"] == "rescene_password_v1"
            user = body["userID"]
            requests.append(user)
            wallets.setdefault(user, {"id":str(uuid.uuid4()),"appId":"fixture-project","userId":user,
                                     "address":"0x"+"a"*40,"walletCustody":"managed","walletType":"managed_user",
                                     "status":"active","authProvider":"rescene_password_v1","createdAt":"2026-11-08T00:00:00Z"})
            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"wallet":wallets[user]}).encode())

    with tempfile.TemporaryDirectory(prefix="rescene-wallet-ui-") as directory:
        temp = Path(directory)
        cert, key = temp / "ca.pem", temp / "ca.key"
        subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-days","1",
                        "-keyout",str(key),"-out",str(cert),"-subj","/CN=localhost",
                        "-addext","subjectAltName=IP:127.0.0.1,DNS:localhost"],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        engine = ThreadingHTTPServer(("127.0.0.1",0),EngineFixture)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert,key)
        engine.socket = context.wrap_socket(engine.socket,server_side=True)
        threading.Thread(target=engine.serve_forever,daemon=True).start()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1",0))
            port = sock.getsockname()[1]
        binary = temp / "api"
        subprocess.run(["go","build","-buildvcs=false","-o",str(binary),"."],cwd=PROJECT/"backend",check=True)
        environment = dict(os.environ,APP_ENV="development",ADDR=f"127.0.0.1:{port}",FALKORDB_URL=database,
                           FALKORDB_GRAPH=graph,DATA_DIR=str(temp/"keys"),ENGINE_BASE_URL=f"https://127.0.0.1:{engine.server_port}",
                           LEADERBOARD_ENABLED="false",STARLIGHT_ENABLED="false",MARKETPLACE_ENABLED="false",SHOP_ENABLED="false",ENGINE_API_KEY="fixture-key-never-a-real-credential",ENGINE_PROJECT_ID="fixture-project",SSL_CERT_FILE=str(cert))
        environment.pop("JWT_SECRET",None)
        backend = subprocess.Popen([str(binary)],cwd=PROJECT/"backend",env=environment,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        game = None
        try:
            deadline = time.monotonic()+15
            while time.monotonic()<deadline:
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz",timeout=1) as response:
                        if response.status == 200: break
                except OSError:
                    time.sleep(0.1)
            else:
                raise TimeoutError("Wallet test API did not become ready")
            client_env = dict(os.environ,RESCENE_API_URL=f"http://127.0.0.1:{port}",RESCENE_AUTH_FILE=str(temp/"session.txt"))
            command = [args.godot,"--path",str(PROJECT),"--script","res://tests/wallet_flow_regression.gd"]
            if not args.capture: command.insert(1,"--headless")
            log_path = temp / "wallet-game.log"
            with log_path.open("w") as output:
                game = subprocess.Popen(command,env=client_env,stdout=output,stderr=subprocess.STDOUT)
            try:
                code = game.wait(timeout=40)
            except BaseException:
                print(log_path.read_text(),end="",flush=True)
                raise
            log = log_path.read_text()
            print(log,end="",flush=True)
            if code or "ERROR:" in log or "WARNING:" in log:
                raise RuntimeError("Wallet game integration failed or emitted Godot diagnostics")
            assert len(wallets)==1 and len(requests)==1, "Repeated login/refresh created an extra wallet"
            print("HTTPS Engine / Fiber / FalkorDB / game wallet integration: PASS")
        finally:
            if game is not None and game.poll() is None:
                game.terminate()
                game.wait(timeout=5)
            backend.terminate()
            backend.wait(timeout=10)
            engine.shutdown()
            engine.server_close()
            subprocess.run(["redis-cli","-u",database,"GRAPH.DELETE",graph],stdout=subprocess.DEVNULL,check=True)


if __name__ == "__main__":
    main()
