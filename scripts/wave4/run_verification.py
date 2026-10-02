"""Run trusted repository checks and bind machine results to their exact source."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / '.agent-harness/wave4-20261002/checks.json'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def scoped(relative):
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError('Evidence path leaves the workspace')
    return path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--task', required=True)
    parser.add_argument('--verify-report', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    task = manifest['tasks'][args.task]
    report_path = scoped('.agent-harness/wave4-20261002/reports/' + args.task + '.json')
    sources = {name: digest(scoped(name)) for name in task['sources']}
    if args.verify_report:
        report = json.loads(report_path.read_text(encoding='utf-8'))
        good = (report['manifest_hash'] == digest(MANIFEST)
                and report['runner_hash'] == digest(Path(__file__))
                and report['sources_before'] == sources == report['sources_after']
                and len(report['checks']) == len(task['commands'])
                and all(result['exit_code'] == 0 and result['command'] == command
                        and digest(scoped(result['log'])) == result['log_hash']
                        for result, command in zip(report['checks'], task['commands'])))
        print(json.dumps({'task': args.task, 'verified': good, 'report': str(report_path)}))
        return 0 if good else 1
    report_path.parent.mkdir(parents=True, exist_ok=True)
    results = []
    for index, command in enumerate(task['commands']):
        log = report_path.parent / (args.task + '-' + str(index + 1) + '.log')
        print(json.dumps({'task': args.task, 'check': index + 1, 'command': command}), flush=True)
        with log.open('w', encoding='utf-8') as output:
            try:
                result = subprocess.run(command['argv'], cwd=scoped(command['cwd']),
                                        stdout=output, stderr=subprocess.STDOUT,
                                        timeout=command.get('timeout_seconds', 900),
                                        check=False)
                code = result.returncode
            except subprocess.TimeoutExpired:
                output.write('\nCHECK_TIMEOUT\n')
                code = 124
        results.append({'command': command, 'exit_code': code,
                        'log': log.relative_to(ROOT).as_posix(), 'log_hash': digest(log)})
        print(json.dumps({'check': index + 1, 'exit_code': code}), flush=True)
        if code:
            break
    report = {'task': args.task, 'at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'manifest_hash': digest(MANIFEST), 'runner_hash': digest(Path(__file__)),
              'sources_before': sources,
              'sources_after': {name: digest(scoped(name)) for name in task['sources']},
              'checks': results}
    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return 0 if len(results) == len(task['commands']) and all(r['exit_code'] == 0 for r in results) and report['sources_before'] == report['sources_after'] else 1

if __name__ == '__main__':
    sys.exit(main())
