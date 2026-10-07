"""Refresh declared modules and their Dart import closure in an isolated test copy."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = {
    'jentra_desktop': 'apps/jentra_desktop',
    'jentra_domain': 'packages/jentra_domain',
    'jentra_platform': 'packages/jentra_platform',
    'jentra_design_system': 'packages/jentra_design_system',
}
IMPORTS = re.compile(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source(name):
    path = (ROOT / name).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file() or path.is_symlink():
        raise ValueError('Only real workspace source files can be copied')
    if any(p in {'.git', '.dart_tool', 'build', 'ephemeral'} for p in path.relative_to(ROOT).parts):
        raise ValueError('Generated state and local stores are excluded')
    if path.name.startswith('.env') or path.suffix in {'.sqlite', '.db'}:
        raise ValueError('Secret configuration and local stores are excluded')
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--selection', required=True)
    parser.add_argument('--destination', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    target = Path(args.destination).resolve()
    if target.parent != Path('C:/') or not target.name.startswith('jw4-') or not target.is_dir():
        raise ValueError('Use an existing approved isolated Wave 4 copy')
    selection = json.loads(source(args.selection).read_text(encoding='utf-8-sig'))
    pending = [source(name) for name in selection['seeds']]
    selected = set()
    while pending:
        item = pending.pop()
        if item in selected:
            continue
        selected.add(item)
        if item.suffix != '.dart':
            continue
        for uri in IMPORTS.findall(item.read_text(encoding='utf-8')):
            if uri.startswith('dart:'):
                continue
            if uri.startswith('package:'):
                package, relative = uri[8:].split('/', 1)
                if package not in PACKAGES:
                    continue
                dependency = ROOT / PACKAGES[package] / 'lib' / relative
            else:
                dependency = item.parent / uri
            pending.append(source(dependency.relative_to(ROOT).as_posix()))
    names = sorted(item.relative_to(ROOT).as_posix() for item in selected)
    before = {name: digest(source(name)) for name in names}
    copied = {}
    for name in names:
        destination = target / name
        if destination.is_symlink() or not destination.resolve().is_relative_to(target):
            raise ValueError('The isolated copy contains an unexpected link')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source(name), destination)
        copied[name] = digest(destination)
    after = {name: digest(source(name)) for name in names}
    report = {
        'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'snapshot': str(target), 'selection': args.selection,
        'selection_hash': digest(source(args.selection)),
        'source_stable': before == copied == after,
        'file_count': len(names), 'source_hashes': before,
        'copied_hashes': copied, 'source_hashes_after': after,
        'scope': 'declared modules and Dart imports; not whole-app build proof',
    }
    evidence = (ROOT / args.evidence).resolve()
    if not evidence.is_relative_to(ROOT):
        raise ValueError('Evidence must stay in the workspace')
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'source_stable': report['source_stable'], 'file_count': len(names),
                      'evidence': str(evidence)}))
    return 0 if report['source_stable'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
