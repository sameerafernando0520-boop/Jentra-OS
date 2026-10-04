"""Copy reviewable source to a fresh short Windows build path without local stores."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ('apps/jentra_desktop', 'packages/jentra_design_system',
            'packages/jentra_domain', 'packages/jentra_platform')
TOP_FILES = ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
PACKAGE_FILES = ('pubspec.yaml', 'analysis_options.yaml', '.metadata')
EXCLUDED = {'.dart_tool', 'build', 'ephemeral', '.plugin_symlinks',
            'failures', '.git', 'node_modules'}
GENERATED_WINDOWS = {'generated_plugin_registrant.cc',
                     'generated_plugin_registrant.h', 'generated_plugins.cmake'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def files():
    result = [ROOT / name for name in TOP_FILES if (ROOT / name).is_file()]
    for package in PACKAGES:
        base = ROOT / package
        result.extend(base / name for name in PACKAGE_FILES
                      if (base / name).is_file())
        for directory in ('lib', 'test', 'assets', 'windows'):
            path = base / directory
            if not path.exists():
                continue
            for item in path.rglob('*'):
                if not item.is_file():
                    continue
                relative = item.relative_to(base)
                if any(part in EXCLUDED for part in relative.parts):
                    continue
                if item.name.startswith('.env') or item.name in GENERATED_WINDOWS:
                    continue
                if item.is_symlink() or not item.resolve().is_relative_to(ROOT):
                    raise ValueError('Source contains a link outside the allowed snapshot')
                result.append(item)
    return sorted(set(result))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    target = Path(args.destination).resolve()
    evidence = (ROOT / args.evidence).resolve()
    if not evidence.is_relative_to(ROOT):
        raise ValueError('Evidence must remain in this workspace')
    if target.exists() or target.is_relative_to(ROOT) or target.parent != Path('C:/'):
        raise ValueError('Use a new, absent directory directly under C:/')
    if not target.name.startswith('jw4-'):
        raise ValueError('Snapshot directory must use the jw4- prefix')
    selected = files()
    before = {item.relative_to(ROOT).as_posix(): sha(item.read_bytes())
              for item in selected}
    target.mkdir()
    copied = {}
    for item in selected:
        name = item.relative_to(ROOT).as_posix()
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(item, destination)
        copied[name] = sha(destination.read_bytes())
    after = {item.relative_to(ROOT).as_posix(): sha(item.read_bytes())
             for item in files()}
    stable = before == copied == after
    report = {'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'workspace': str(ROOT), 'snapshot': str(target),
              'source_stable': stable, 'file_count': len(before),
              'source_hashes': before, 'copied_hashes': copied,
              'source_hashes_after': after,
              'excludes_local_stores_and_generated_builds': True}
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'snapshot': str(target), 'source_stable': stable,
                      'file_count': len(before), 'evidence': str(evidence)}))
    return 0 if stable else 1


if __name__ == '__main__':
    raise SystemExit(main())
