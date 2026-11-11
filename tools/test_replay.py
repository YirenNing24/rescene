#!/usr/bin/env python3
"""Generate actual Godot replay streams and compare with the Go judge."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rescene-replay-parity-") as directory:
        env = dict(os.environ, RESCENE_REPLAY_GOLDENS=str(Path(directory)/"replays.json"))
        subprocess.run([args.godot,"--headless","--path",str(PROJECT),"--script","res://tools/export_replay_fixtures.gd"],env=env,check=True,timeout=180)
        subprocess.run(["go","test","-run","TestReplayParity","-count=1","-v"],cwd=PROJECT/"backend",env=env,check=True,timeout=90)

if __name__ == "__main__":
    main()
