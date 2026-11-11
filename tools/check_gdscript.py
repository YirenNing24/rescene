#!/usr/bin/env python3
"""Import and compile all game/test/tool GDScript under the project's strict rules."""
import argparse
from pathlib import Path
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.7 executable")
    args = parser.parse_args()
    for mode in (["--editor", "--quit"], ["--script", "res://tools/check_gdscript.gd"]):
        result = subprocess.run(
            [args.godot, "--headless", "--path", str(PROJECT), *mode],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180,
        )
        # Godot can report script errors while returning exit status zero.
        if result.returncode or "ERROR:" in result.stdout or "WARNING:" in result.stdout:
            print(result.stdout, end="")
            return result.returncode or 1
        if "--script" in mode:
            print(result.stdout, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
