# Beatmaps

There are 128 playable starting charts: 32 songs × Easy, Normal, Hard and Ultra Hard. They cover the **first half** of the local recording. Notes are generated offline from beat/onset analysis and saved to disk; gameplay does not create random notes. These are generated starting charts, **not hand-authored final charts**. Review rhythm placement, phrasing and difficulty on device before release.

The track/bar/position/length organization follows the author's [g-metarave-beats project](https://github.com/YirenNing24/g-metarave-beats/tree/Authoritative), particularly `Songs/Road/road.gd`, `GameComponents/Bar/bar.gd` and its song-map JSON files. The new loader, perspective renderer and timing/input judge are implemented for this project. Old map timing is retained when `ticks_per_beat` is omitted: 280 ticks per beat, with `len: 70` identifying taps. New maps explicitly use 400 ticks per beat and an explicit `kind`.

Each song ID has four editable `.json` files. Matching `.tres` files carry the same dictionaries as native Godot JSON resources so exported builds can load them. After editing a JSON chart, run this from the project folder:

```sh
python3 tools/build_beatmaps.py --pack-only
```

This packs edits without regenerating or replacing the notes. Let Godot rescan the resources before running. `--pack-only` uses only Python's standard library.

To regenerate charts from audio, install `tools/beatmap-requirements.txt` in a Python virtual environment and ensure `ffmpeg` is available. Then use `python tools/build_beatmaps.py` (all songs) or `python tools/build_beatmaps.py --song "LOVE ATTACK"` (matching titles). **Regeneration replaces authored edits** for the selected songs. The catalog must already contain exact `playable_seconds`; rebuild it with `tools/build_song_catalog.py` after changing audio files.

## Timing and notes

`tempo` is BPM, `offset_seconds` is the start of the musical grid, and `duration_seconds` is the audio cutoff. Tracks are lanes 0–4. Bars are ordered and carry `quarters_count` (normally 4). A note's time in seconds is:

```text
offset_seconds + (beats in preceding bars + pos / ticks_per_beat) * 60 / tempo
```

`kind` is `tap`, `hold` or `slide`. For holds/slides, `len` is the duration in ticks. A slide adds a curve; `at` is a fraction of its duration and `lane` may be fractional:

```json
{
  "pos": 400,
  "len": 1200,
  "kind": "slide",
  "curve": [
    {"at": 0.0, "lane": 0.0},
    {"at": 0.34, "lane": 0.5},
    {"at": 0.7, "lane": 2.0},
    {"at": 1.0, "lane": 1.55}
  ]
}
```

Place that note in track 0 so its head matches the curve's starting lane. Keep points ordered, beginning at `at: 0` and ending at `at: 1`, with lanes between 0 and 4. Rendering and judging share the exact same cubic interpolation in `rhythm_chart.gd`. Holds/slides award a head judgment, half-beat checkpoints and a tail judgment. The generator reserves a ribbon's interval so it never places a new note across its required tracing path; Hard/Ultra Hard also include two-note chords.

The stage uses the audio playback position plus time since the last mix, minus cached device output latency, following [Godot's audio synchronization guidance](https://docs.godotengine.org/en/latest/tutorials/audio/sync_with_audio.html). The clock never runs backward. Pause freezes audio and judgment, and resume allows the active ribbon to be grabbed with a fresh touch index. A local ±150 ms input offset is available in the pause panel for device calibration.
