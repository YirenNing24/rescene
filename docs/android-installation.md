# Android installer diagnostics

The Korean installer message in the report translates to “App not installed because the package appears to be invalid.” It does not contain Android's detailed install failure code. Reported phones include a Redmi Note 15 Pro and a Redmi Note 14. First installation was reported, and the Note 14 user confirmed a fresh 0.1.28 download.

The public 0.1.27 download was checked in full: 217,852,811 bytes and SHA-256 `7a62635377b9ae33cbd88e623996acbcfab0931738a7b67c62fa2e0e2332e334`, matching the signed local APK. ZIP CRCs, signature schemes v2/v3, package metadata, 16 KB ELF LOAD alignment and ZIP alignment passed. It contains ARM64 native libraries, requires Android API 24 or later, and requires OpenGL ES 3.

A separate, reproducible packaging defect was found in Godot 4.7.2's non-Gradle exporter (`platform/android/export/export_plugin.cpp`, provider-authorities handling). It rewrites **all** provider authorities to the app's `.fileprovider`, including the newly included Jetpack Startup provider. The resulting APK had both providers claiming `com.rescene.rhythm.fileprovider`. Jetpack's [documented authority](https://developer.android.com/topic/libraries/app-startup) is `${applicationId}.androidx-startup`.

From 0.1.28, `tools/android_manifest.py` repairs the exported binary manifest **before** ZIP alignment and signing. FileProvider keeps `com.rescene.rhythm.fileprovider`, preserving the Android updater's URI contract. Startup uses `com.rescene.rhythm.androidx-startup`. The repair appends a distinct string and rewrites only the Startup authority references; it preserves all other attributes, resource IDs and components. The release builder rejects unexpected provider sets and validates the final APK authorities. Package ID and signing key are unchanged.

Run the regression checks with:

```sh
python3 -m unittest discover -s tools -p test_android_manifest.py -v
python3 tools/build_android_release.py
```

Checks cover the actual template's broken export, shared string indices, idempotency, UTF-8/UTF-16 strings, Unicode, malformed headers and preservation of unrelated metadata. SDK `aapt` independently parses the resulting manifest, and `apksigner`/`zipalign` validate the final signed package.

The provider defect is corrected, but the exact Redmi installation failure still needs a successful retry or the device's detailed PackageInstaller error. Initial headless emulator attempts crashed. A later Android 14 emulator booted with the host GPU and ARM64 translation enabled; the exact signed ARM64 0.1.28 APK installed successfully using `adb install --no-streaming` (218,430,347 bytes, SHA-256 `0f60b6f904358c687f57d37f85240318983b08f19867cb2df8ac93203de0c48f`). This is an emulator installation test, not confirmation on either Redmi. The continuing failure cannot be attributed to duplicate providers without device diagnostics.

If installation still fails, obtain the Android/HyperOS version and collect the actual error using `adb install -r RESCENE-Rhythm.apk` on the player's connected device. Do not recommend uninstalling an existing app or disabling device security checks as a speculative fix. For a first installation, deleting the failed download and downloading the new version is enough to retry without touching account data.


## Version-pinned browser downloads

The former `/download` URL streamed the mutable latest object directly. A client resuming an old partial file without `If-Range` after a release switch could append bytes from the next APK. No device checksum is available to establish whether this caused the reported error.

`/download` now returns an uncached 307 redirect to `/updates/android/<version>/RESCENE-Rhythm.apk` before sending any APK bytes. That final URL continues selecting the same R2 object after later releases. Existing partial requests to the old mutable URL receive a full 200 response, forcing a restart instead of appending. Versioned endpoints retain normal 206 range support and use a versioned download filename. Tests cover old partials, version switches, filename, range and method validation; live checks cover the redirect, pinned range and forced restart.

An official GitHub release was created during this investigation, after the user's question about GitHub downloads. Neither the original `fluentxverse/rescene-rhythm` repository nor `YirenNing24/rescene` had earlier Releases or APK assets when checked. The new v0.1.28 asset has the same SHA-256 as R2; GitHub's asset digest independently confirms it. Do not describe it as the earlier GitHub download someone else reported. That link is still needed for comparison.

## Offline install-check helper

`infra/android/install-check` is a separate, small native Android diagnostic app built by `tools/build_install_check.py`. It has no internet permission, analytics, game login or broad storage permission. It only reads a document selected by the user, checks the exact release size/SHA-256, package ID, signing certificate and device ABI, then can install that verified game APK with the user's normal Android confirmation. It shows PackageInstaller status, legacy status and Android's detailed message, and lets the user copy those diagnostics. It never uninstalls the game or clears game data. It requires Android 8 or later and does not need native CPU libraries.

The helper is pinned to the release metadata at build time, and refuses other or damaged packages. It asks for Android's ordinary install-from-this-source permission when needed. It does not disable Play Protect or any device security policy. Source and helper build/signing are separate from the game APK; testing it must not be presented as a Redmi fix until the phone's result is known.

The helper’s end-to-end Android 14 tests passed for SHA-256/signature validation, a confirmed first installation, update installation, and reporting cancellation (`INSTALL_FAILED_ABORTED`, legacy -115). A deliberately truncated APK is rejected before installation and leaves the install button disabled. The helper can be removed after diagnosis; it does not run a background service.
