"""Run a new source-bound gate without changing historical harness evidence."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scoped(name):
    path = (ROOT / name).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError('Evidence or source path leaves the workspace')
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--verify-report', action='store_true')
    args = parser.parse_args()
    manifest_path = scoped(args.manifest)
    manifest_hash = digest(manifest_path)
    runner_hash = digest(Path(__file__))
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    task = manifest['tasks'][args.task]
    commands = task['commands']
    names = task['sources']
    if not commands or not names or len(set(names)) != len(names):
        raise ValueError('A gate requires unique source paths and real commands')
    sources = {name: digest(scoped(name)) for name in names}
    report_path = manifest_path.parent / 'reports' / (args.task + '.json')

    def snapshot_matches():
        snapshot = task.get('snapshot')
        if snapshot is None:
            return all(scoped(c['cwd']).is_dir() for c in commands)
        target = Path(snapshot).resolve()
        if target.parent != Path('C:/') or not target.name.startswith('jw4-'):
            raise ValueError('Use an approved isolated Wave 4 source copy')
        # Bind every declared source that executes there, including exports,
        # shared dependencies, tests, fonts and native build configuration.
        return all((target / name).is_file() and digest(target / name) == value
                   for name, value in sources.items())

    if args.verify_report:
        report = json.loads(report_path.read_text(encoding='utf-8'))
        checks = report['checks']
        verified = (
            report['manifest_before'] == manifest_hash == report['manifest_after']
            and report['runner_before'] == runner_hash == report['runner_after']
            and report['sources_before'] == sources == report['sources_after']
            and report['snapshot_before'] and report['snapshot_after']
            and snapshot_matches()
            and len(checks) == len(commands)
            and all(check['exit_code'] == 0 and check['command'] == command
                    and digest(scoped(check['log'])) == check['log_hash']
                    for check, command in zip(checks, commands))
        )
        print(json.dumps({'task': args.task, 'verified': verified,
                          'report': str(report_path)}))
        return 0 if verified else 1

    snapshot_before = snapshot_matches()
    if not snapshot_before:
        raise ValueError('The isolated source does not match this gate')
    report_path.parent.mkdir(parents=True, exist_ok=True)
    checks = []
    for index, command in enumerate(commands, 1):
        argv = command['argv']
        if not isinstance(argv, list) or not argv or not all(isinstance(v, str) for v in argv):
            raise ValueError('Commands must contain explicit argument arrays')
        cwd = ((Path(task['snapshot']) / command['cwd']).resolve()
               if task.get('snapshot') else scoped(command['cwd']))
        if task.get('snapshot') and not cwd.is_relative_to(Path(task['snapshot']).resolve()):
            raise ValueError('Command directory leaves the isolated copy')
        log = report_path.parent / (args.task + '-' + str(index) + '.log')
        print(json.dumps({'task': args.task, 'check': index, 'command': command}), flush=True)
        with log.open('w', encoding='utf-8') as output:
            try:
                completed = subprocess.run(argv, cwd=cwd, stdout=output,
                    stderr=subprocess.STDOUT, timeout=command.get('timeout_seconds', 900),
                    check=False)
                code = completed.returncode
            except subprocess.TimeoutExpired:
                output.write('\nCHECK_TIMEOUT\n')
                code = 124
        checks.append({'command': command, 'exit_code': code,
            'log': log.relative_to(ROOT).as_posix(), 'log_hash': digest(log)})
        print(json.dumps({'task': args.task, 'check': index, 'exit_code': code}), flush=True)
        if code:
            break
    report = {
        'task': args.task, 'at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope': 'automated source checks only; manual acceptance gates remain open',
        'manifest_before': manifest_hash, 'manifest_after': digest(manifest_path),
        'runner_before': runner_hash, 'runner_after': digest(Path(__file__)),
        'sources_before': sources,
        'sources_after': {name: digest(scoped(name)) for name in names},
        'snapshot_before': snapshot_before, 'snapshot_after': snapshot_matches(),
        'checks': checks,
    }
    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    good = (len(checks) == len(commands) and all(c['exit_code'] == 0 for c in checks)
            and report['sources_before'] == report['sources_after']
            and report['manifest_before'] == report['manifest_after']
            and report['runner_before'] == report['runner_after']
            and report['snapshot_after'])
    return 0 if good else 1


if __name__ == '__main__':
    sys.exit(main())
