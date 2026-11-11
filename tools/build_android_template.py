#!/usr/bin/env python3
"""Compile only needed Godot native features; reuse matching official Java shell."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2"
ABIS = {"arm64": "arm64-v8a", "x86_64": "x86_64"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Godot 4.7.2-stable source directory")
    parser.add_argument("--sdk", type=Path, default=Path.home() / "Android/Sdk")
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--package-only", action="store_true", help="Repackage previously built libraries with an unchanged recorded profile")
    args = parser.parse_args()
    source: Path = args.source.resolve()
    version = runpy.run_path(str(source / "version.py"))
    actual = ".".join(str(version[key]) for key in ("major", "minor", "patch"))
    if actual != VERSION or version["status"] != "stable":
        raise RuntimeError(f"Expected {VERSION}-stable source, found {actual}-{version['status']}")
    official = Path.home() / f".local/share/godot/export_templates/{VERSION}.stable/android_release.apk"
    if not official.is_file():
        raise RuntimeError(f"Install the matching official Android release template: {official}")
    destination = ROOT / "builds/templates"
    destination.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, ANDROID_HOME=str(args.sdk.resolve()))
    if not (source / "thirdparty/swappy-frame-pacing/arm64-v8a/libswappy_static.a").is_file():
        subprocess.run(["python3", "misc/scripts/install_swappy_android.py"], cwd=source, check=True)
    if args.package_only:
        previous = json.loads((destination / "build.json").read_text())
        if previous["profile_sha256"] != hashlib.sha256((ROOT / "infra/android/custom.py").read_bytes()).hexdigest():
            raise RuntimeError("Build profile changed; recompile before packaging.")
    for arch in ([] if args.package_only else ABIS):
        log = destination / f"engine-{arch}.log"
        print(f"Compiling {arch}; log: {log}", flush=True)
        with log.open("w") as output:
            subprocess.run([
                "scons", f"-j{args.jobs}", "platform=android", "target=template_release", f"arch={arch}",
                f"profile={ROOT / 'infra/android/custom.py'}",
            ], cwd=source, env=environment, stdout=output, stderr=subprocess.STDOUT, check=True)
    # Java/JNI code is unchanged. Use the official APK for this exact source
    # version and replace both the engine and its matching NDK C++ runtime.
    template = destination / "android_release.apk"
    temporary = template.with_suffix(".apk.tmp")
    native_root = source / "platform/android/java/lib/libs/release"
    strip = args.sdk / "ndk/29.0.14206865/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
    native_files: dict[str, Path] = {}
    for abi in ABIS.values():
        for filename in ("libgodot_android.so", "libc++_shared.so"):
            native = destination / "native" / abi / filename
            native.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(native_root / abi / filename, native)
            subprocess.run([str(strip), "--strip-unneeded", str(native)], check=True)
            native_files[f"lib/{abi}/{filename}"] = native
    with ZipFile(official) as original, ZipFile(temporary, "w") as packed:
        for entry in original.infolist():
            signature = entry.filename.startswith("META-INF/") and entry.filename.count("/") == 1 and Path(entry.filename).suffix.upper() in {".SF", ".RSA", ".DSA", ".MF"}
            if entry.filename.startswith("lib/") or signature:
                continue
            packed.writestr(entry, original.read(entry.filename))
        for name, path in native_files.items():
            packed.write(path, name, compress_type=ZIP_DEFLATED, compresslevel=9)
    temporary.replace(template)
    metadata = {
        "godot_version": VERSION + ".stable",
        "source": "https://github.com/godotengine/godot/tree/4.7.2-stable",
        "profile_sha256": hashlib.sha256((ROOT / "infra/android/custom.py").read_bytes()).hexdigest(),
        "template_sha256": hashlib.sha256(template.read_bytes()).hexdigest(),
        "native_bytes": {name: path.stat().st_size for name, path in native_files.items()},
        "architectures": list(ABIS.values()),
    }
    (destination / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Built {template} ({template.stat().st_size:,} bytes)", flush=True)


if __name__ == "__main__":
    main()
