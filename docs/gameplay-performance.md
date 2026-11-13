# Gameplay performance

The November 13, 2026 optimization keeps the 2400 × 1080 input/layout space,
1600 × 720 Android render target, 120 Hz judge, and replay protocol 4.
It does not change timing windows, scoring, energy, card bonuses, or touch mapping.

## Local comparison

Corrected for 0.1.24: the original 0.1.23 rendered measurement was invalid because
line-color errors prevented spark trails from drawing. The figures below include
the restored trails and a clean engine error log; the earlier 60% claim is withdrawn.

Same offline stress workload on Intel UHD Graphics 770, Godot 4.7.2 GL
Compatibility, 1600 × 720 desktop window and the mobile SubViewport path.
VSync/frame limiting disabled for measurement; 60 warmup frames followed by
360 measured frames. Five simultaneous ribbons/vortices, hit bursts every four
simulated 60 Hz frames, recurring combo pillars, and a five-card carousel.
The independent judge/ribbon CPU samples use Dragon / Ultra Hard (320 notes).

| Measurement | Before | After |
| --- | ---: | ---: |
| Mean rendered frame | 7.039 ms | 4.482 ms |
| 95th percentile frame | 9.112 ms | 6.284 ms |
| 99th percentile frame | 11.842 ms | 7.333 ms |
| Mean canvas draw calls | 649.242 | 93.997 |
| Mean judge update | 0.058 ms | 0.002 ms |
| Mean visible ribbon construction | 0.296 ms | 0.103 ms |

These are local wall-clock/render-loop measurements, **not Redmi FPS results**.
No physical Android device was connected. Phone thermal behavior, battery modes,
refresh-rate settings, and driver performance still require a device test.

## Changes

- Finished notes leave the judge's scan window; rendering shares a bounded visible
  note list. The note order and deterministic event processing stay unchanged.
- Ribbon vertex/color arrays are sized in advance, triangle indices reused, and
  mobile ribbons use 24 smooth segments instead of 36.
- Sparks reuse prepared burst data. Glow sprites, ripples and trail primitives
  are grouped into batches instead of alternating textures/lines per particle.
  Particle counts and fast burst lifetime are retained.
- Pillars and all seven vortex palettes use compressed 32-frame atlases baked
  from the reference shaders. Gameplay no longer executes their expensive
  per-pixel procedural loops or compiles those shaders on the first hit.
- Every equipped portrait is created before play and reused by the carousel.
  Legacy card photos load only when their artwork is actually requested.
  HUD glyphs are warmed before countdown; unchanged HUD strings/material colors
  are not rewritten every frame. Hidden lobby particle processing is stopped.

Atlases add about 5.6 MiB of compressed GPU texture data; they are shared by
all pooled effect sprites. Desktop and Android texture variants are imported
ahead of release, rather than generated during play.

## Reproduce and validate

`python3 tools/test_gameplay_runtime.py --godot /path/to/godot --render` runs
the isolated HTTP start-queue fixture and GPU workload, failing on engine/script
errors even when Godot exits with status zero. Its measurements are saved in
`builds/gameplay-corrected.json`.

Run `tools/benchmark_gameplay.gd` with a GPU display, passing a `res://builds/`
JSON output path after `--`. Use the same machine/window settings and avoid
other benchmark/test processes while measuring. `tools/bake_gameplay_effects.gd`
regenerates the atlases; run Godot's editor import pass afterward.

Validation covers all 116 active charts, 155 client/Go replay fixtures, 56,268
ribbon boundary cases, and 5,916 culling windows. The gameplay integration tests
exercise mobile input, countdown, pause, resume, retry, results, and effect pools.
`tests/combo_pillar_transparency.gd -- --atlas` and `-- --vortex` render both
atlases through a transparent SubViewport and check that their empty space
does not darken the background. The prepared carousel test checks object reuse
across 30 member switches.

## Song connection step

Starting a run with a valid JWT bypasses unrelated wallet/catalog HTTP calls.
Token rotation and rejected-token retry retain the existing session lock, and
pending score receipts still finish before replacing the active run ticket.
The backend reads five equipped cards concurrently at one confirmed block,
validates their member/set identities, and retains atomic server energy spending.
The local fixture blocks a wallet read until the start request arrives; it also
checks token expiry, 401 recovery and account changes during a request.
