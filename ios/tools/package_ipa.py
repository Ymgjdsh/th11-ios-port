"""Verify an ARM64 iOS 14 bundle and package it for TrollStore."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
app, output = args.app.resolve(), args.output.resolve()
if output.exists():
    raise SystemExit('Output already exists; choose a new filename')
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'org.th11.native'
assert info['MinimumOSVersion'] == '14.0'
assert info['TH11Diagnostics'] == 'OFF'
assert info['UIRequiresFullScreen'] is True
assert 'UIInterfaceOrientationPortrait' in info['UISupportedInterfaceOrientations']
assert set(info['UIDeviceFamily']) == {1, 2}
for family in ('CFBundleIcons', 'CFBundleIcons~ipad'):
    icon = info[family]['CFBundlePrimaryIcon']
    assert icon['CFBundleIconName'] == 'AppIcon' and icon['CFBundleIconFiles']
assert (app / 'Assets.car').is_file()
executable = app / info['CFBundleExecutable']
assert executable.parent == app and executable.is_file()
assert run('xcrun', 'lipo', '-archs', str(executable)).split() == ['arm64']
commands = run('xcrun', 'otool', '-l', str(executable))
assert re.search(r'platform\s+(2|IOS)\b', commands), 'Not iphoneos Mach-O'
assert re.search(r'minos\s+14\.0\b', commands), 'Wrong deployment target'
assert not re.search(r'(WebKit|JavaScriptCore)\.framework', run('xcrun', 'otool', '-L', str(executable)))
for file in app.rglob('*'):
    assert file.suffix.lower() not in {'.exe', '.dll', '.wasm', '.html', '.js', '.mjs', '.rpy', '.rpyx', '.py', '.sh'}, file
    assert not (file.is_file() and file.name.lower().startswith('score') and file.suffix.lower() == '.dat'), file
manifest = json.loads((app / 'assets/manifest.json').read_text(encoding='utf-8'))
assert manifest['schema'] == 'th11-ios-assets/1' and manifest['language'] == 'ja'
required = {'game/th11.dat', 'music-verification.json', 'fonts/blend4444.bin', 'fonts/cp932.bin'}
required.update('fonts/font%d.bin' % i for i in range(4))
music = {name for name in manifest['files'] if name.startswith('music/') and name.endswith('.ogg')}
assert len(music) == 18
required.update(music)
assert set(manifest['files']) == required
actual_names = {p.relative_to(app / 'assets').as_posix() for p in (app / 'assets').rglob('*') if p.is_file()}
assert actual_names == required | {'manifest.json'}
assets = []
for name in sorted(required):
    file = app / 'assets' / name
    actual = {'bytes': file.stat().st_size, 'sha256': sha(file)}
    assert actual['bytes'] > 0 and actual == manifest['files'][name], name
    assets.append({'name': name, **actual})
for name in ('SDL.txt', 'SDL_ttf.txt', 'FreeType.txt', 'miniaudio.txt'):
    assert (app / 'licenses' / name).is_file(), name
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='th11-ipa-') as temp:
    staging = Path(temp)
    bundle = staging / 'Payload/th11.app'
    bundle.parent.mkdir()
    shutil.copytree(app, bundle)
    run('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(bundle))
    run('/usr/bin/codesign', '--verify', '--strict', str(bundle))
    partial = staging / 'TH11.ipa'
    with zipfile.ZipFile(partial, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in sorted(bundle.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(staging).as_posix())
    with zipfile.ZipFile(partial) as archive:
        assert archive.testzip() is None
    executable_sha = sha(bundle / info['CFBundleExecutable'])
    shutil.copyfile(partial, output)
report = {
    'artifact': output.name, 'sha256': sha(output), 'bytes': output.stat().st_size,
    'bundle_identifier': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'minimum_ios': '14.0', 'architecture': 'arm64', 'platform': 'iphoneos',
    'executable_sha256': executable_sha, 'signature': 'ad-hoc; TrollStore installation',
    'app_icon': 'Original th11.exe IDI_ICON3, compiled AppIcon',
    'language': 'Japanese game; Chinese native settings', 'music': manifest['music'],
    'scripted_diagnostic_inputs': False, 'assets': assets,
    'verification_scope': 'Bundle, resources, device architecture and signature; physical iOS 14 acceptance requires installation on the user device.'
}
output.with_suffix('.manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: v for k, v in report.items() if k != 'assets'}, ensure_ascii=False, indent=2))
