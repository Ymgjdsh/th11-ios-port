"""Private local transfer package; contains licensed resources, never publish."""
from pathlib import Path
import tarfile
root=Path(__file__).resolve().parents[2]
output=root/'.local/build-inputs.tar.gz'
with tarfile.open(output,'w:gz',compresslevel=3) as archive:
    for directory in ['ios','portable','th11_web/cpp','.local/assets','.local/app-icon/Assets.xcassets']:
        for p in sorted((root/directory).rglob('*')):
            if p.is_file() and '__pycache__' not in p.parts:
                archive.add(p,arcname=p.relative_to(root).as_posix(),recursive=False)
print(output.name,output.stat().st_size)
