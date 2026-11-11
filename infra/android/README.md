# Small Android release template

`custom.py` builds Godot **4.7.2-stable** for this canvas-only GLES3 game. It omits
3D, Vulkan, physics, navigation, XR, video decoders, 3D asset importers, and unused
networking/modules. Size optimization and ThinLTO remove additional unused code.

It retains the advanced Unicode text server (including Korean), advanced GUI
controls (dropdowns, photo picker, reports), SVG, fonts, PNG/JPEG/WebP, MP3, regex,
TLS/HTTPS, threads, and Swappy frame pacing. Do not disable these just to save space.
Custom shaders, effects, and the dedicated mobile gameplay viewport remain intact.

## Rebuild

Install SCons and the Android SDK, including NDK **29.0.14206865** and build-tools
**36.1.0**. Download the matching source tag from
<https://github.com/godotengine/godot/releases/tag/4.7.2-stable>. Keep the extracted
engine source outside the game directory. The matching official Android export
template must already be installed in the Godot user directory.

```sh
python3 tools/build_android_template.py --source /path/to/godot-4.7.2-stable --jobs 6
python3 tools/build_android_release.py
```

The first command builds ARM64 and x86_64 native libraries and packages them with
the **unchanged, same-version** official Java/JNI shell. It also downloads Swappy
if missing. `builds/templates/build.json` records engine/profile/template details.
The export preset points only at this project-specific release template; other
Godot projects and the installed official templates are untouched.

The public APK contains only ARM64, suitable for modern Android phones including
Redmi 13. For emulator validation, build a separate artifact:

```sh
python3 tools/build_android_release.py --emulator
```

This produces `builds/RESCENE-Rhythm-emulator.apk` without replacing the public
APK or its manifest. Both use the same game content and slim engine configuration.

Release export includes all 32 catalog tracks, the menu track and the scene's
splash track, but excludes
unreferenced duplicates/alternate versions from the APK. Originals stay in the
source audio directory. It scans scripts and text scenes/resources for audio
references. Export verifies every required imported audio resource,
ABI, signature, and 16 KiB ZIP alignment before replacing the release artifact.
It retains the existing signing identity so the APK can update prior installs.

## Publish

```sh
node tools/publish_android_release.mjs
cd webapp
npm run deploy
```

The publisher uploads to versioned objects in the `rescene` Cloudflare R2 bucket,
reads the object back and verifies SHA-256, then deploys the API Worker with the
new object key. It also updates the web companion's release manifest. The second
command deploys the displayed version/size/checksum. Previous R2 release objects
remain available for rollback; point `APK_OBJECT_KEY` to the prior version and
redeploy the API Worker. There is no APK upload to the VPS.

## In-app updates

From v0.1.6, **Settings → Check for updates** and the login screen open the native
update panel. Android also checks after entering the lobby and offers a newer
release while the player is in the menu. Updates are optional and never interrupt
gameplay. Close & pause/backgrounding preserves the partial download; Resume
continues its byte range against an immutable version URL in R2.

`/updates/android.json` returns the current signed release's version, code, size,
SHA-256, signing certificate fingerprint, notes and pinned APK URL. No JWT or
private server credentials are involved. Downloads accept only the trusted
distribution origin and expected version paths, verify byte-range framing, and
check the complete SHA-256 on a worker thread. Failed hashes are removed. The
client re-verifies before launching Android's installer using Godot's existing
FileProvider support. `REQUEST_INSTALL_PACKAGES` enables the system installation
flow; the player grants “Allow from this source” if asked and confirms Update.
There is no silent-install promise. The same signing key/package preserves app
data; successful installations clear their APK cache on the next update check.

An optional `?arch=x86_64` manifest and separate emulator APK let QA test actual
Android installation without increasing the ARM64 phone download. The publisher
uploads matching emulator artifacts when `emulator-release.json` has the same
version/code as the phone release. Always bump **both** Android version/code in
`export_presets.cfg` and the matching `config/version`/`rescene/app/version_code`
settings in `project.godot`. The builder rejects mismatches. Release notes live in
`infra/android/release-notes.json`. Keep published version objects immutable.

`python3 tools/test_app_updates.py` exercises the real GDScript downloader against
an isolated loopback fixture, including pause/resume, connection interruption,
corrupt bytes, bad ranges, and cache cleanup. The loopback override works only in
desktop debug runs and uses a separate update-cache directory. Worker tests:

```sh
node --test infra/game-api/download.test.mjs infra/game-api/updates.test.mjs
```

Release 0.1.8 also fixes touch scrolling for both Journey tabs and the gameplay
team showcase (empty hidden, one card static, populated slots only). Regression:

```sh
godot --headless --path . --script tests/journey_showcase_regression.gd
```

Android emulator validation covered a live R2 download, pause/resume, checksum
verification, unknown-source permission and system installation from 0.1.6 to
0.1.7 with login preserved. Version 0.1.8 was then checked on Android for Journey
scrolling in both directions. Physical Redmi testing remains pending.

## Launcher branding

Release 0.1.9 replaces the stock Godot icon with the game's lilac R/orbit mark.
`export_presets.cfg` specifies all four icon inputs (regular, adaptive foreground,
background, monochrome) and the Android splash icon. `icon.svg` and the companion
favicon share the mark. Sources and generation notes: `assets/branding/README.md`.
The release builder rejects an APK if any of its 24 launcher images or splash
icon still matches the stock template. Install over the existing package to keep
login and app data; no uninstall is needed for the icon change.

Release 0.1.10 fixes combo-pillar opacity in the transparent mobile gameplay
viewport. The additive shader now derives alpha from emitted light and discards
empty pixels, instead of giving the entire quad alpha 1. RGB is normalized by
coverage to preserve additive beam intensity. The fixed sprite pool and milestone
triggers are unchanged.

GPU regression (requires a display):

```sh
godot --path . --script tests/combo_pillar_transparency.gd
# Negative control: intentionally restores old alpha and must fail.
godot --path . --script tests/combo_pillar_transparency.gd -- --old-alpha
godot --path . --script tools/capture_combo_pillars.gd -- --mobile-rendering
```

The regression checks actual viewport alpha and the final background composite
at sprite boundaries throughout the effect's lifetime, and verifies the beam
still emits light. `tests/combo_effects_regression.gd` covers judgment wiring,
10-combo intervals, misses, pause, expiry, retry and bounded node reuse.

Release 0.1.11 adds a required, initially unchecked registration agreement, plus
scrollable Terms & Conditions and Privacy Policy modals. The fan-made/nonprofit
notice and scam warning appear on the auth screen and in the documents. Contact:
winterape25@gmail.com. Policy JSON is bundled for offline reading and verified by
the APK builder. The API records the accepted policy versions and server time;
older apps must update before registering. Login and refresh remain compatible.
The web companion uses the same document file and agreement payload.

```sh
godot --path . --script tests/legal_registration_regression.gd
cd webapp && npx playwright test tests/legal.spec.ts
```
