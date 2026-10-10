"""Reuse platform probe results from the same SDK/architecture/dependencies."""
import argparse
import re
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('reference', type=Path)
p.add_argument('output', type=Path)
p.add_argument('sdk', choices=['iphoneos', 'iphonesimulator'])
args = p.parse_args()
entries = {}
for line in args.reference.read_text().splitlines():
    match = re.match(r'([^:#][^:]*):([^=]+)=(.*)$', line)
    if match:
        entries[match[1]] = (match[2], match[3])
assert entries['CMAKE_SYSTEM_NAME'][1] == 'iOS'
assert ('iPhoneOS.platform' if args.sdk == 'iphoneos' else 'iPhoneSimulator.platform') in entries['CMAKE_OSX_SYSROOT'][1]
assert entries['CMAKE_OSX_DEPLOYMENT_TARGET'][1] == '14.0'
lines = ['# Platform feature probes only; no compiler, source or build paths.']
for key, (kind, value) in sorted(entries.items()):
    if kind == 'INTERNAL' and key.startswith(('HAVE_', 'LIBC_')):
        assert value in ('', '0', '1', 'TRUE', 'FALSE'), (key, value)
        lines.append('set(%s "%s" CACHE INTERNAL "Verified same-SDK probe")' % (key, value))
args.output.write_text('\n'.join(lines) + '\n')
print('Prepared', len(lines) - 1, 'same-platform feature probes')
