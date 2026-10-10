"""Read and symbolicate this project's latest macOS integration crash."""
import json
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[2]
report = max((Path.home() / 'Library/Logs/DiagnosticReports').glob('native-game*.ips'), key=lambda p: p.stat().st_mtime)
data = json.loads(report.read_text().split('\n', 1)[1])
print(report.name, data['exception'], flush=True)
frames = data['threads'][data['faultingThread']]['frames']
native = data['usedImages'][0]
addresses = [hex(native['base'] + f['imageOffset']) for f in frames if f['imageIndex'] == 0]
subprocess.run(['atos', '-o', str(root / '.local/native-checks/native-game'), '-l', hex(native['base']), *addresses], check=True)
