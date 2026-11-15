# Android installer diagnostics

The Korean installer message in the report translates to “App not installed because the package appears to be invalid.” It does not contain Android's detailed install failure code. The reported phone is a Redmi Note 15 Pro and this is a first installation; no previous copy of the game is involved.

The public 0.1.27 download was checked in full: 217,852,811 bytes and SHA-256 `7a62635377b9ae33cbd88e623996acbcfab0931738a7b67c62fa2e0e2332e334`, matching the signed local APK. ZIP CRCs, signature schemes v2/v3, package metadata, 16 KB ELF LOAD alignment and ZIP alignment passed. It contains ARM64 native libraries, requires Android API 24 or later, and requires OpenGL ES 3.

A separate, reproducible packaging defect was found in Godot 4.7.2's non-Gradle exporter (`platform/android/export/export_plugin.cpp`, provider-authorities handling). It rewrites **all** provider authorities to the app's `.fileprovider`, including the newly included Jetpack Startup provider. The resulting APK had both providers claiming `com.rescene.rhythm.fileprovider`. Jetpack's [documented authority](https://developer.android.com/topic/libraries/app-startup) is `${applicationId}.androidx-startup`.

From 0.1.28, `tools/android_manifest.py` repairs the exported binary manifest **before** ZIP alignment and signing. FileProvider keeps `com.rescene.rhythm.fileprovider`, preserving the Android updater's URI contract. Startup uses `com.rescene.rhythm.androidx-startup`. The repair appends a distinct string and rewrites only the Startup authority references; it preserves all other attributes, resource IDs and components. The release builder rejects unexpected provider sets and validates the final APK authorities. Package ID and signing key are unchanged.

Run the regression checks with:

```sh
python3 -m unittest discover -s tools -p test_android_manifest.py -v
python3 tools/build_android_release.py
```

Checks cover the actual template's broken export, shared string indices, idempotency, UTF-8/UTF-16 strings, Unicode, malformed headers and preservation of unrelated metadata. SDK `aapt` independently parses the resulting manifest, and `apksigner`/`zipalign` validate the final signed package.

The provider defect is corrected, but the exact Redmi installation failure still needs a successful retry or the device's detailed PackageInstaller error. The local Android emulator crashed during startup, before an install could be tested. Do not present an emulator installation or physical-device test as passed.

If installation still fails, obtain the Android/HyperOS version and collect the actual error using `adb install -r RESCENE-Rhythm.apk` on the player's connected device. Do not recommend uninstalling an existing app or disabling device security checks as a speculative fix. For a first installation, deleting the failed download and downloading the new version is enough to retry without touching account data.
