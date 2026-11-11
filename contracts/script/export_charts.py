#!/usr/bin/env python3
"""Export the authoritative Go chart catalog for the Foundry registration script."""

import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[2]
    charts = json.loads((root / "backend/charts.json").read_text())
    difficulties = {"Easy": 0, "Normal": 1, "Hard": 2, "Ultra Hard": 3}
    manifest = []
    seen = set()
    for chart in charts:
        song_id = chart["song_id"]
        difficulty = difficulties[chart["difficulty"]]
        revision = chart["revision"]
        units = chart["units"]
        if not isinstance(song_id, str) or not 1 <= len(song_id.encode()) <= 128:
            raise ValueError("Invalid song ID")
        if len(revision) != 64 or len(bytes.fromhex(revision)) != 32 or int(revision, 16) == 0:
            raise ValueError(f"Invalid revision: {song_id}")
        if type(units) is not int or not 1 <= units <= 2**32 - 1:
            raise ValueError(f"Invalid scoring-unit count: {song_id}")
        key = (song_id, difficulty, revision)
        if key in seen:
            raise ValueError(f"Duplicate chart: {key}")
        seen.add(key)
        # Foundry parseJson ABI-encodes object fields in alphabetical key order.
        manifest.append({"difficulty": difficulty, "revision": "0x" + revision, "songId": song_id, "units": units})
    manifest.sort(key=lambda item: (item["songId"], item["difficulty"], item["revision"]))
    destination = root / "contracts/charts.json"
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Exported {len(manifest)} chart revisions to {destination}")


if __name__ == "__main__":
    main()
