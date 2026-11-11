# RESCENE Rhythm app icon

The outlined italic R uses the game's Nimbus Roman typeface, lilac/navy palette,
orbit, star and beat marks. No installed font is needed at runtime.

`icon.svg` is the desktop/project icon. Android explicitly uses `launcher.png`
(192px) plus the separate 432px adaptive foreground, full-bleed background and
white-alpha monochrome mask. Essential foreground art stays inside the central
264px safe zone; Android owns the final launcher mask.

To regenerate from the game's font, install `fonttools` and `cairosvg` in a build
environment, then run `python tools/generate_app_icons.py`. The game and Android
build need neither package. The same vector also supplies the web companion
favicon. The release builder verifies every exported launcher/splash icon differs
from the stock template so a default Godot icon cannot silently ship again.
