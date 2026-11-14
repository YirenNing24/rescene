#!/usr/bin/env python3
"""Build editable beat/bar JSON charts and pack-friendly JSON resources from local audio.

Uses the track/bar/pos/len organization of the user's g-metarave-beats project.
Rhythm positions come from offline onset/beat analysis; no notes are randomized at runtime.
Requires librosa 0.11, numpy and ffmpeg. Generated charts are a starting point for hand review.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
from tune_beatmaps import tune
from add_swipe_notes import add_swipes

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/beatmaps"
DIFFICULTIES = ["Easy", "Normal", "Hard", "Ultra Hard"]


def analyze(song):
    import librosa
    import numpy as np
    path = ROOT / song["audio_path"].removeprefix("res://")
    duration = song["playable_seconds"]
    pcm = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-t", str(duration),
        "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "1", "-ar", "22050", "-",
    ])
    y = np.frombuffer(pcm, dtype="<f4")
    envelope = librosa.onset.onset_strength(y=y, sr=22050, hop_length=256)
    tempo, frames = librosa.beat.beat_track(onset_envelope=envelope, sr=22050, hop_length=256, trim=False)
    bpm = float(np.asarray(tempo).flat[0])
    beats = librosa.frames_to_time(frames, sr=22050, hop_length=256)
    onsets = librosa.onset.onset_detect(onset_envelope=envelope, sr=22050, hop_length=256, units="time")
    if len(beats) < 8:
        bpm = 120.0
        beats = np.arange(0.5, duration, 0.5)
    if bpm < 85:
        beats = np.sort(np.r_[beats, (beats[:-1] + beats[1:]) * 0.5])
        bpm *= 2
    elif bpm > 180:
        beats = beats[::2]
        bpm *= 0.5
    return bpm, beats, onsets


def build(song, level, analysis):
    import numpy as np
    bpm, beats, onsets = analysis
    beat_seconds = 60.0 / bpm
    duration = float(song["playable_seconds"])
    offset = float(beats[0])
    ticks = 400.0
    events = []
    for index in range(len(beats) - 1):
        t, step = float(beats[index]), float(beats[index + 1] - beats[index])
        if t < 1.5 or t > duration - 0.5:
            continue
        if level == 0 and index % 2:
            continue
        subdivisions = [0.0]
        if level >= 2 or (level == 1 and index % 4 == 2):
            subdivisions += [0.5]
        if level == 3 and index % 4 in (1, 3):
            subdivisions += [0.25, 0.75]
        for fraction in sorted(subdivisions):
            candidate = t + step * fraction
            if len(onsets):
                nearest = float(onsets[np.argmin(np.abs(onsets - candidate))])
                if abs(nearest - candidate) < 0.045:
                    candidate = nearest
            if candidate < duration - 0.4:
                events.append(candidate)
    tracks = [{"bars": [], "color": "c7bbffff"} for _ in range(5)]
    bars_count = math.ceil(max(0, duration - offset) / beat_seconds / 4) + 1
    for track in tracks:
        track["bars"] = [{"index": i, "quarters_count": 4, "notes": []} for i in range(bars_count)]
    seed = int(hashlib.sha256((song["id"] + str(level)).encode()).hexdigest()[:8], 16)
    pattern = [0, 2, 4, 1, 3, 2, 0, 3, 1, 4]
    blocked_until = -1.0
    count = 0

    def insert(t, lane, kind="tap", length=0.0, curve=None):
        musical_beat = max(0.0, (t - offset) / beat_seconds)
        bar = int(musical_beat // 4)
        note = {"pos": round((musical_beat % 4) * ticks, 5),
                "len": 70 if kind == "tap" else round(length / beat_seconds * ticks, 5),
                "kind": kind, "layer": 0, "swipe": False, "slanted": kind == "slide"}
        if curve:
            note["curve"] = curve
        tracks[lane]["bars"][bar]["notes"].append(note)

    for t in sorted(events):
        if t < blocked_until:
            continue
        lane = pattern[(count + seed) % len(pattern)]
        kind = "tap"
        length = 0.0
        # Early curves make the mechanic apparent in every difficulty.
        if count % (15 - level * 2) == 5:
            kind = "slide"
            length = beat_seconds * (3 if level >= 2 else 2)
        elif count % (12 - level) == 8:
            kind = "hold"
            length = beat_seconds * (2 if level < 2 else 3)
        if t + length > duration - 0.35:
            kind, length = "tap", 0.0
        curve = None
        if kind == "slide":
            direction = 1 if lane < 2 else -1
            distance = 1.0 if level == 0 else 2.0
            end = min(4.0, max(0.0, lane + direction * distance))
            curve = [{"at": 0.0, "lane": float(lane)},
                     {"at": 0.34, "lane": min(4.0, max(0.0, lane + direction * distance * 0.25))},
                     {"at": 0.7, "lane": end}, {"at": 1.0, "lane": end - direction * 0.45}]
        insert(t, lane, kind, length, curve)
        if kind != "tap":
            blocked_until = t + length + max(0.13, beat_seconds * 0.25)
        elif level >= 2 and count % (9 if level == 2 else 6) == 3:
            insert(t, (lane + 2) % 5)
        count += 1
    chart = {"version": 2, "audio": {"title": song["title"], "artist": song["artist"]},
            "difficulty": DIFFICULTIES[level], "tempo": round(bpm, 6), "ticks_per_beat": ticks,
            "offset_seconds": round(offset, 6), "start_pos": 0, "duration_seconds": duration,
            "source": "offline_audio_beat_and_onset_analysis", "generated": True, "tracks": tracks}
    tune(chart)
    add_swipes(chart)
    return chart


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--song", help="Only process a title containing this text")
    parser.add_argument("--pack-only", action="store_true", help="Pack hand-edited JSON charts without regenerating notes")
    args = parser.parse_args()
    if args.pack_only:
        files = sorted(DEST.glob("*/*.json"))
        for path in files:
            content = json.dumps(json.loads(path.read_text()), ensure_ascii=False, separators=(",", ":"))
            path.with_suffix(".tres").write_text('[gd_resource type="JSON" format=3]\n\n[resource]\ndata = ' + content + "\n")
        print(f"Packed {len(files)} charts without changing their notes.")
        return
    catalog = json.loads((ROOT / "scripts/song_catalog.gd").read_text().split("=", 1)[1])
    for song in catalog:
        if args.song and args.song.casefold() not in song["title"].casefold():
            continue
        analysis = analyze(song)
        folder = DEST / song["id"]
        folder.mkdir(parents=True, exist_ok=True)
        for level, difficulty in enumerate(DIFFICULTIES):
            chart = build(song, level, analysis)
            content = json.dumps(chart, ensure_ascii=False, separators=(",", ":"))
            slug = difficulty.lower().replace(" ", "_")
            (folder / (slug + ".json")).write_text(content + "\n")
            # JSON is a built-in Resource; .tres is included by normal Godot resource exports.
            (folder / (slug + ".tres")).write_text('[gd_resource type="JSON" format=3]\n\n[resource]\ndata = ' + content + "\n")
        print(f"{song['title']}: {analysis[0]:.1f} BPM · four half-length charts", flush=True)


if __name__ == "__main__":
    main()
