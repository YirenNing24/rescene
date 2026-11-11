#!/usr/bin/env python3
"""Build a signed APK with the slim engine and only referenced audio resources."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


def audio_resources() -> tuple[set[str], list[str]]:
    referenced: set[str] = set()
    for directory in ('scripts', 'scenes', 'assets'):
        for pattern in ('*.gd', '*.tscn', '*.tres'):
            for resource in (ROOT / directory).rglob(pattern):
                referenced.update(re.findall(r'res://(assets/audio/[^"\n]+\.mp3)', resource.read_text()))
    if not referenced:
        raise RuntimeError('No audio references found; refusing to export an empty library.')
    for path in referenced:
        if not (ROOT / path).is_file():
            raise RuntimeError(f'Referenced audio missing: {path}')
    unused = sorted(str(path.relative_to(ROOT)) for path in (ROOT / 'assets/audio').glob('*.mp3') if str(path.relative_to(ROOT)) not in referenced)
    return referenced, unused


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/home/paulanthonyarriola/Desktop/Godot_v4.7.2-stable_linux.x86_64')
    parser.add_argument('--emulator', action='store_true', help='Build a separate x86_64 validation APK; leave the public ARM64 release untouched')
    args = parser.parse_args()
    private = ROOT / 'backend/data/android-signing'
    key = json.loads((private / 'credentials.json').read_text())
    preset = ROOT / 'export_presets.cfg'
    original = preset.read_text()
    project_settings = (ROOT / 'project.godot').read_text()
    version = re.search(r'version/name="([^"]+)"', original).group(1)
    version_code = int(re.search(r'version/code=(\d+)', original).group(1))
    if f'config/version="{version}"' not in project_settings or f'app/version_code={version_code}\n' not in project_settings:
        raise RuntimeError('App update version metadata must match the Android export version.')
    template = ROOT / 'builds/templates/android_release.apk'
    if not template.is_file():
        raise RuntimeError('Build the slim template first with tools/build_android_template.py.')
    referenced, unused = audio_resources()
    excluded = re.search(r'^exclude_filter="([^"]*)"', original, re.MULTILINE)
    if not excluded:
        raise RuntimeError('Missing export exclusion setting.')
    effective = original.replace('package/signed=true', 'package/signed=false')
    if args.emulator:
        effective = effective.replace('architectures/arm64-v8a=true', 'architectures/arm64-v8a=false').replace('architectures/x86_64=false', 'architectures/x86_64=true')
    effective = effective.replace(excluded.group(0), 'exclude_filter="' + ','.join([excluded.group(1), *unused]) + '"')
    builds = ROOT / 'builds'
    builds.mkdir(exist_ok=True)
    log = builds / 'android-export.log'
    sdk = Path.home() / 'Android/Sdk/build-tools/36.1.0'
    release = builds / ('RESCENE-Rhythm-emulator.apk' if args.emulator else 'RESCENE-Rhythm.apk')
    with TemporaryDirectory(prefix='android-', dir=builds) as working:
        work = Path(working)
        unsigned, aligned, signed = (work / name for name in ('unsigned.apk', 'aligned.apk', 'signed.apk'))
        try:
            preset.write_text(effective)
            with log.open('w') as output:
                result = subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--export-release', 'Android', str(unsigned)], stdout=output, stderr=subprocess.STDOUT)
            if result.returncode or 'ERROR:' in log.read_text():
                raise RuntimeError('Export failed. Inspect builds/android-export.log.')
        finally:
            preset.write_text(original)
        # Align uncompressed native libraries for devices using 16 KiB pages.
        subprocess.run([str(sdk / 'zipalign'), '-f', '-P', '16', '4', str(unsigned), str(aligned)], check=True)
        environment = dict(os.environ, RESCENE_APK_KEY_PASSWORD=key['password'])
        subprocess.run([str(sdk / 'apksigner'), 'sign', '--ks', str(private / 'release.keystore'), '--ks-key-alias', key['alias'], '--ks-pass', 'env:RESCENE_APK_KEY_PASSWORD', '--key-pass', 'env:RESCENE_APK_KEY_PASSWORD', '--out', str(signed), str(aligned)], env=environment, check=True)
        verification = subprocess.check_output([str(sdk / 'apksigner'), 'verify', '--print-certs', str(signed)], text=True)
        subprocess.run([str(sdk / 'zipalign'), '-c', '-P', '16', '4', str(signed)], check=True)
        # Check catalog/menu audio survived export. Duplicates remain on disk.
        with ZipFile(signed) as archive:
            entries = archive.namelist()
            policies = ROOT / 'assets/legal/policies.json'
            if archive.read('assets/assets/legal/policies.json') != policies.read_bytes():
                raise RuntimeError('Exported registration policies are missing or stale.')
            # Every launcher variant must replace the template's stock Godot art.
            # Adaptive/themed launchers use separate images from the legacy icon.
            with ZipFile(template) as stock:
                icon_paths = [entry for entry in stock.namelist() if
                              (entry.startswith('res/mipmap') and entry.endswith('.webp'))
                              or entry == 'res/drawable/splash_icon.webp']
                if len(icon_paths) < 25:
                    raise RuntimeError('Unexpected Android template icon layout.')
                for entry in icon_paths:
                    if entry not in entries or archive.read(entry) == stock.read(entry):
                        raise RuntimeError(f'Export still contains a stock Android icon: {entry}')
            architectures = sorted({entry.split('/')[1] for entry in entries if entry.startswith('lib/')})
            if architectures != (['x86_64'] if args.emulator else ['arm64-v8a']):
                raise RuntimeError(f'Unexpected APK architectures: {architectures}')
            for path in referenced:
                imported = (ROOT / (path + '.import')).read_text()
                resource = re.search(r'^path="res://([^"]+)"', imported, re.MULTILINE)
                if not resource or 'assets/' + resource.group(1) not in entries:
                    raise RuntimeError(f'Export omitted required audio: {path}')
            for path in unused:
                if 'assets/' + path + '.import' in entries:
                    raise RuntimeError(f'Export bundled unused audio: {path}')
        digest = hashlib.sha256(signed.read_bytes()).hexdigest()
        manifest = {
            'file': release.name,
            'version': version,
            'version_code': version_code,
            'release_notes': json.loads((ROOT / 'infra/android/release-notes.json').read_text()).get(version, ''),
            'sha256': digest,
            'bytes': signed.stat().st_size,
            'api': 'https://api.remineph.online',
            'signing_certificate_sha256': next(line.split(': ', 1)[1] for line in verification.splitlines() if 'certificate SHA-256 digest:' in line),
            'chain': 'Elysium Mainnet (99901)',
            'physical_device_test': 'pending',
            'engine_template': json.loads((template.parent / 'build.json').read_text()),
            'included_audio_tracks': len(referenced),
            'excluded_unused_audio': unused,
            'architectures': architectures,
        }
        signed.replace(release)
        signature = signed.with_suffix('.apk.idsig')
        if signature.exists():
            signature.replace(release.with_suffix('.apk.idsig'))
        (builds / ('emulator-release.json' if args.emulator else 'release.json')).write_text(json.dumps(manifest, indent=2) + '\n')
        print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
