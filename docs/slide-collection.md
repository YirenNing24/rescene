# Wider slides and contact feedback

Version 0.1.29 expands curved slide heads by 22% and ribbon width by one third. Both keep perspective scaling; straight hold ribbons and tap note sizes stay unchanged. The curved tracing tolerance rises from 0.72 to 0.96 lanes for the head, tail and pause regrab. Timing windows and 160ms release grace are unchanged. An adjacent lane one full lane away still cannot collect a slide head; wide bends require tracing. Shallow bends that remain within the expanded region may legitimately be held without moving far.

While a slide is actually collected, its ribbon brightens and a soft mint-tinted light appears at the finger position. The existing vortex and the new contact glow use the judge’s same lane and vertical checks, so neither claims a ribbon is collected when the finger has left the region. The light disappears on release or leaving the collector, freezes on pause and resets on retry. Each touch can track independently. Straight holds retain their existing vortex without adding the new slide glow.

The contact layer uses ten reusable sprites sharing one 64×64 radial texture and one additive material. It adds no particle emitters, per-frame texture uploads or screen-sized blur. The additive texture has fully transparent edges, with no rectangular dark background.

Replay version 6 pins the wider slide rules to new server-issued tickets. Versions 3/4/5 retain their original timing/tolerance. Both judges use the same 0.96-lane slide tolerance, while taps, straight holds and swipes retain 0.72 lanes. Chart hashes, note times, scoring units, score caps and card boosts do not change. Existing rankings and older installed APKs remain supported.

Validation covers version-specific Go boundaries and unchanged other note kinds, 158 Godot/Go replay fixtures including wide slide offsets, actual mobile-rendered contact placement and lifecycle, two-finger stage input, all-chart ribbon boundaries, core mechanics, strict GDScript and GPU stress checks. These are local tests; physical-device gesture feel remains to be checked by players.
