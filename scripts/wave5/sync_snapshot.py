"""Refresh source in the owned Wave 5 isolate, without reading local stores."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    target = Path(args.snapshot).resolve()
    evidence = (ROOT / args.evidence).resolve()
    if (target.parent != Path('C:/') or not target.name.startswith('jw4-wave5-')
            or not target.is_dir() or not evidence.is_relative_to(ROOT)):
        raise ValueError('Use the existing owned Wave 5 isolate and workspace evidence')
    spec = importlib.util.spec_from_file_location(
        'source_snapshot', ROOT / 'scripts/wave4/create_isolated_snapshot.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    selected = module.files()
    before = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in selected}
    for p in selected:
        destination = target / p.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, destination)
    copied = {name: hashlib.sha256((target / name).read_bytes()).hexdigest()
              for name in before}
    after = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in module.files()}
    stable = before == copied == after
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps({
        'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'workspace': str(ROOT), 'snapshot': str(target), 'source_stable': stable,
        'file_count': len(before), 'source_hashes': before, 'copied_hashes': copied,
        'source_hashes_after': after, 'excludes_local_stores_and_generated_builds': True
    }, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'source_stable': stable, 'file_count': len(before)}))
    return 0 if stable else 1


if __name__ == '__main__':
    raise SystemExit(main())
