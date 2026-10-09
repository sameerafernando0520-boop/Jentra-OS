"""Hash final compilation evidence without opening a desktop or acceptance store."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot-evidence', required=True)
    parser.add_argument('--build-log', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    paths = [(ROOT / p).resolve() for p in (args.snapshot_evidence, args.build_log, args.output)]
    if not all(p.is_relative_to(ROOT) for p in paths):
        raise ValueError('Evidence must remain inside this workspace')
    snap = json.loads(paths[0].read_text(encoding='utf-8'))
    isolate = Path(snap['snapshot']).resolve()
    source_module = ROOT / 'scripts/wave4/create_isolated_snapshot.py'
    spec = importlib.util.spec_from_file_location('w5_snapshot_source', source_module)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    current = {p.relative_to(ROOT).as_posix(): digest(p) for p in module.files()}
    copied_now = {p: digest(isolate / p) for p in snap['source_hashes']}
    source_match = current == copied_now == snap['source_hashes'] and snap['source_stable']
    release = isolate / 'apps/jentra_desktop/build/windows/x64/runner/Release'
    files = sorted(p for p in release.rglob('*') if p.is_file())
    if any(not p.resolve().is_relative_to(release.resolve()) for p in files):
        raise ValueError('Release bundle contains an unexpected external link')
    binary = release / 'jentra_desktop.exe'
    built = binary.is_file() and 'Built build' in paths[1].read_text(encoding='utf-8')
    report = {
        'capturedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'snapshot': str(isolate), 'snapshotEvidence': args.snapshot_evidence,
        'buildLog': args.build_log, 'buildLogSha256': digest(paths[1]),
        'buildSucceeded': built, 'current_source_match': source_match,
        'sourceFileCount': len(current), 'sourceHashes': current,
        'isolatedSourceHashes': copied_now,
        'executable': str(binary), 'executableSha256': digest(binary) if built else None,
        'releaseFileCount': len(files),
        'releaseHashes': {p.relative_to(release).as_posix(): digest(p) for p in files},
        'sourceChangesSinceSnapshot': sorted(set(current) ^ set(snap['source_hashes']) |
            {p for p in current if current[p] != snap['source_hashes'].get(p)}),
        'nativeLaunched': False, 'authenticatedAcceptance': False,
        'localStoresIncluded': False, 'installerCreated': False,
    }
    paths[2].write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('buildSucceeded', 'current_source_match',
        'sourceFileCount', 'releaseFileCount', 'executableSha256', 'sourceChangesSinceSnapshot')}))
    return 0 if built and source_match else 1

if __name__ == '__main__':
    raise SystemExit(main())
