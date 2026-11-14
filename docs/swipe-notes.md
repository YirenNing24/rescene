# Upward swipe notes

Swipe notes are short, mint-colored discs with a floating upward arrow and a fading chevron. The arrow bobs in stage time, follows perspective, and freezes on pause. Drawing uses small canvas polygons and strokes; it adds no particle emitters, textures or screen-sized post-processing.

Start a touch at the collector and flick upward as the disc arrives. Collection needs roughly 49 design pixels (about 32 pixels in the 720p target) of upward movement within 8–220ms. Upward travel must be at least the horizontal travel. Timing is measured when the distance threshold is crossed, using the existing Perfect/Great/Good windows and lane tolerance. A tap, stationary hold, downward swipe, tiny jitter or mostly sideways motion cannot score it. Each contact can collect one swipe note; lift before the next. Another finger can independently tap or hold. Final release coordinates are included so Android can recognize a quick flick when drag events were coalesced during a slow frame. Canceled touches never collect on release.

Each swipe counts as one scoring unit. Perfect swipe hits use the same card score/healing rules, combo and momentum as other Perfect heads. It has no sustain tail, checkpoints or vortex.

`tools/add_swipe_notes.py` deterministically converts spaced isolated taps, preserving every note time, lane, length and scoring-unit count. Chords and active ribbons are left intact. Initial spacing is at least eight seconds on Easy, six on Normal, 4.5 on Hard and 3.5 on Ultra Hard. The current 116 active charts contain 1,411 swipe notes. The generator applies the same pass after lane tuning; rerunning it is idempotent. The tutorial teaches three upward swipes after curves.

The exported chart revisions change, so the APK and authoritative server catalog must be released together. Previous bests are excluded from revised-chart rankings and replaced by the first clear of that revision, following the existing chart-update rule. Accounts, card stats and progression are preserved.

Replay protocol 5 retains four-integer events. Action 4 records vertical coordinates in ten-thousandths of the stage height, separately from action 1 (lane movement), so pure vertical gestures are not lost. Both judges apply identical direction, displacement, duration, timing and one-hit-per-contact rules. Protocols 3/4 remain readable and reject action 4. Vertical positions also keep a held ribbon from counting while the finger is above or below its hit area.

Validation: strict GDScript, all 116 chart mechanics, all-chart Go replays, adversarial swipe tests, 155 Godot/Go parity fixtures, native two-finger input and fast-release tests through the Android 1600×720 render target, tutorial isolation, and GPU rendering/startup checks. Physical-device playtesting remains necessary to judge gesture feel.
