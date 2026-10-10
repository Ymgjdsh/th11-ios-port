"""Export native sources and build tools; exclude private resources and machines."""
import argparse
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = ('ios', 'portable', 'th11_web/cpp')
BLOCKED = {'.local', 'artifacts', 'node_modules', '__pycache__', '.git',
           'build', 'dist', 'validation'}
ALLOWED = {'.c', '.cpp', '.h', '.hpp', '.inc', '.mm', '.m', '.py', '.sh',
           '.in', '.md', '.txt', '.json', '.plist', '.storyboard', '.cmake',
           '.LICENSE'}
EXTRA_FILES = (
    'README.md', '.gitignore', '.gitattributes',
    'LICENSE-launcher.txt', 'THIRD-PARTY-NOTICES.txt',
    'th11_web/scripts/prepare-fonts.mjs',
    'th11_web/scripts/native/font-oracle.mjs',
    'th11_web/scripts/package.json', 'th11_web/scripts/package-lock.json',
)


def source_files(root=ROOT):
    files = {root / name for name in EXTRA_FILES}
    for base in SOURCE_ROOTS:
        for path in (root / base).rglob('*'):
            relative = path.relative_to(root)
            if (path.is_file() and not path.is_symlink()
                    and not any(part in BLOCKED for part in relative.parts)
                    and '.local.' not in path.name
                    and (path.suffix in ALLOWED or path.name.startswith('LICENSE'))):
                files.add(path)
    missing = sorted(str(p.relative_to(root)) for p in files if not p.is_file())
    if missing:
        raise FileNotFoundError('Source export inputs missing: ' + ', '.join(missing))
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    files = source_files()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, 'w:gz', format=tarfile.PAX_FORMAT) as archive:
        for path in files:
            archive.add(path, arcname=path.relative_to(ROOT).as_posix(), recursive=False)
    print(f'Packaged {len(files)} source files; assets and local configuration excluded')


if __name__ == '__main__':
    main()
