"""Registered fishing source and evidence proof. Never captures or sends input."""
import ast
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from tools.sdlc import ROOT, FISHING, FISHING_CODE, GateError


def run(*command):
    subprocess.run(command, cwd=ROOT, check=True, timeout=300)  # build.sh compiles the helper and three tools


def main():
    for name in sorted(FISHING_CODE):
        path = ROOT / name
        if path.suffix == '.py':
            ast.parse(path.read_text(), filename=name)
        elif path.suffix == '.sh':
            run('sh', '-n', name)
    manifest = json.loads((ROOT / FISHING / 'evidence/shared-recordings.json').read_text())
    for item in manifest:
        path = Path(item['path'])
        if path.is_absolute() or '..' in path.parts or not str(path).startswith('data/001_wow_fishing/'):
            raise GateError('invalid shared recording path')
        content = (ROOT / path).read_bytes()
        if len(content) != item['bytes'] or hashlib.sha256(content).hexdigest() != item['sha256']:
            raise GateError('recording provenance mismatch: ' + str(path))
    for path in (ROOT / FISHING / 'evidence').rglob('*'):
        if path.suffix == '.json':
            json.loads(path.read_text())
        elif path.suffix == '.jsonl':
            for line in path.read_text().splitlines():
                if line.strip():
                    json.loads(line)
    run('sh', FISHING + 'test_core.sh')
    run('sh', FISHING + 'build.sh')
    run('sh', FISHING + 'setup_camera.sh', '--self-test')
    run('swiftc', '-parse-as-library', '-typecheck', FISHING + 'background.swift')
    probe = FISHING + 'probes/background-click/'
    run('swiftc', '-parse-as-library', '-typecheck', *[probe + name for name in
        ['Adapter.swift', 'NativeWindowServerPreparation.swift', 'NativeBackgroundClickTransport.swift', 'Probe.swift']])
    run('swiftc', '-parse-as-library', '-typecheck', 'data/001_wow_fishing/pilot_20260921/recorder.swift')
    print('Fishing source, retained-image regressions and shared recording checksums passed; zero live effects.')


if __name__ == '__main__':
    main()
