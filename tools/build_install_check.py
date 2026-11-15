#!/usr/bin/env python3
"""Build a small offline installer diagnostic using the Android SDK, not Godot."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = Path.home() / 'Android/Sdk'
TOOLS = SDK / 'build-tools/36.1.0'
ANDROID = SDK / 'platforms/android-36/android.jar'
JDK = Path('/usr/lib/jvm/java-17-temurin-jdk')
SOURCE = ROOT / 'infra/android/install-check'


def run(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    release = json.loads((ROOT / 'builds/release.json').read_text())
    key = json.loads((ROOT / 'backend/data/android-signing/credentials.json').read_text())
    output = ROOT / 'builds/RESCENE-Install-Check-v1.apk'
    with tempfile.TemporaryDirectory(prefix='install-check-', dir=ROOT / 'builds') as directory:
        temp = Path(directory)
        source = (SOURCE / 'InstallCheckActivity.java').read_text()
        for name, value in {'@GAME_SHA256@': release['sha256'], '@GAME_BYTES@': str(release['bytes']),
                            '@GAME_VERSION@': release['version'], '@GAME_DOWNLOAD@': 'https://api.remineph.online/updates/android/' + release['version'] + '/' + release['file']}.items():
            source = source.replace(name, value)
        java = temp / 'InstallCheckActivity.java'; java.write_text(source)
        classes = temp / 'classes'; classes.mkdir()
        res = temp / 'res/drawable'; res.mkdir(parents=True)
        shutil.copy2(ROOT / 'assets/branding/launcher.png', res / 'icon.png')
        compiled = temp / 'resources.zip'
        run([TOOLS / 'aapt2', 'compile', '--dir', temp / 'res', '-o', compiled])
        unsigned = temp / 'unsigned.apk'
        run([TOOLS / 'aapt2', 'link', '-o', unsigned, '--manifest', SOURCE / 'AndroidManifest.xml', '-I', ANDROID, compiled])
        run([JDK / 'bin/javac', '-source', '8', '-target', '8', '-classpath', ANDROID, '-d', classes, java])
        dex = temp / 'dex'; dex.mkdir()
        run([TOOLS / 'd8', '--release', '--min-api', '26', '--lib', ANDROID, '--output', dex, *classes.rglob('*.class')])
        with zipfile.ZipFile(unsigned, 'a') as apk:
            apk.write(dex / 'classes.dex', 'classes.dex', compress_type=zipfile.ZIP_STORED)
        aligned = temp / 'aligned.apk'
        run([TOOLS / 'zipalign', '-f', '4', unsigned, aligned])
        env = dict(os.environ, RESCENE_APK_KEY_PASSWORD=key['password'])
        run([TOOLS / 'apksigner', 'sign', '--ks', ROOT / 'backend/data/android-signing/release.keystore', '--ks-key-alias', key['alias'], '--ks-pass', 'env:RESCENE_APK_KEY_PASSWORD', '--key-pass', 'env:RESCENE_APK_KEY_PASSWORD', '--out', output, aligned], env=env)
        run([TOOLS / 'apksigner', 'verify', output])
    metadata = {'file': output.name, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                'bytes': output.stat().st_size, 'game_version': release['version'], 'game_sha256': release['sha256']}
    (ROOT / 'builds/install-check.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
