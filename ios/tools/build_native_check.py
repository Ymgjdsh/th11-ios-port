"""Incremental macOS integration check build, separate from the device app."""
import concurrent.futures
import hashlib
import json
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[2]
out = root / '.local/native-checks'
objects = out / 'objects'
objects.mkdir(parents=True, exist_ok=True)
flags = ['-std=c++17', '-O1', '-g', '-ffp-contract=off', '-fno-fast-math', '-fno-strict-aliasing', '-DTH_NATIVE_PLATFORM=1']
headers = hashlib.sha256(json.dumps(flags).encode())
for p in sorted((root / 'th11_web/cpp/game').glob('*.hpp')):
    headers.update(p.read_bytes())
for p in sorted((root / 'portable/graphics').glob('*.hpp')):
    headers.update(p.read_bytes())
header_hash = headers.digest()
sources = [root / 'ios/tests/native_game.cpp', *sorted((root / 'th11_web/cpp/game').glob('*.cpp'))]
def compile_source(source):
    obj = objects / (source.stem + '.o')
    stamp = obj.with_suffix('.sha256')
    extra = ['-DTH11_IOS=1'] if source.stem == 'TitleKeys' else []
    digest = hashlib.sha256(header_hash + ' '.join(extra).encode() + source.read_bytes()).hexdigest()
    if obj.exists() and stamp.exists() and stamp.read_text() == digest:
        return obj
    subprocess.run(['clang++', *flags, *extra, '-c', str(source), '-o', str(obj)], check=True)
    stamp.write_text(digest)
    return obj
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    compiled = list(pool.map(compile_source, sources))
binary = out / 'native-game'
subprocess.run(['clang++', *map(str, compiled), '-o', str(binary)], check=True)
print('Native integration executable ready:', len(compiled), 'source files', flush=True)
