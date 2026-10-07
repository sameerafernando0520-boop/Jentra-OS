"""Validate supplied runtime observations; never fabricate or execute acceptance."""
import argparse
from datetime import datetime
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
RACES = (
    'employee_code', 'employment_timeline', 'organization_cycle',
    'consumption_timeline', 'leave_balance', 'work_ownership', 'payroll_posting',
    'payroll_reversal', 'linked_source_correction', 'project_billing',
    'milestone_approval', 'service_dispatch', 'stock_parts', 'maintenance',
    'asset_capitalization', 'asset_depreciation_disposal', 'revoked_replay')


def instant(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError('Observation timestamps require explicit UTC offsets')
    return parsed


def milliseconds(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+(?:\.\d+)?', value):
        raise ValueError('Duration must be a nonnegative canonical decimal string')
    try:
        parsed = Decimal(value)
    except InvalidOperation as error:
        raise ValueError('Invalid observed duration') from error
    if not parsed.is_finite():
        raise ValueError('Duration must be finite')
    return parsed


def latency_family(family):
    kind = family['kind']
    if kind not in ('read', 'command'):
        raise ValueError('Only ordinary read/command targets are evaluated')
    warmup, measured = family['warmup'], family['measured']
    if len(warmup) < 20 or len(measured) < 100:
        raise ValueError('At least 20 warmup and 100 measured observations are required')
    ids = set()
    for sample in warmup + measured:
        if not isinstance(sample['id'], str) or not sample['id'] or sample['id'] in ids:
            raise ValueError('Each observation needs a unique nonempty identity')
        ids.add(sample['id'])
        milliseconds(sample['elapsed_ms'])
        if sample['outcome'] not in ('success', 'failure', 'unavailable'):
            raise ValueError('Every measured failure/unavailable result must be retained')
    durations = sorted(milliseconds(sample['elapsed_ms']) for sample in measured)
    # ceil(0.95*n), expressed as integers, avoiding percentile interpolation.
    rank = (95 * len(durations) + 99) // 100
    p95 = durations[rank - 1]
    failures = sum(sample['outcome'] == 'failure' for sample in measured)
    unavailable = sum(sample['outcome'] == 'unavailable' for sample in measured)
    target = Decimal(500 if kind == 'read' else 1500)
    return {'name': family['name'], 'kind': kind, 'count': len(measured),
        'warmup_count': len(warmup), 'nearest_rank': rank, 'p95_ms': str(p95),
        'target_ms': str(target), 'failure_count': failures,
        'unavailable_count': unavailable,
        'observations_meet_target': p95 <= target and not failures and not unavailable}


def race_observation(race):
    if race['name'] not in RACES:
        raise ValueError('Unknown Wave 4 race')
    if race.get('direction') not in ('forward', 'reversed'):
        raise ValueError('Record the forward or reversed actor/command ordering')
    a, b, observer = race['session_a'], race['session_b'], race['observer']
    pids = [session['pid'] for session in (a, b, observer)]
    if any(type(pid) is not int or pid <= 0 for pid in pids) or len(set(pids)) != 3:
        raise ValueError('Commands and lock observation require three distinct backend PIDs')
    if any(not isinstance(session.get('command_id'), str) or
           not session['command_id'].strip() for session in (a, b)) or a['command_id'] == b['command_id']:
        raise ValueError('Competing commands require distinct attributable identities')
    a_start, a_finish, a_commit = (instant(a[key]) for key in ('started', 'finished', 'committed'))
    b_start, b_finish, b_commit = (instant(b[key]) for key in ('started', 'finished', 'committed'))
    observed = instant(observer['observed_at'])
    if not (a_start <= a_finish <= a_commit and b_start <= b_finish <= b_commit):
        raise ValueError('Session chronology is inconsistent')
    if not (a_start <= b_start < a_commit and b_start <= observed < a_commit
            and observed <= b_finish):
        raise ValueError('Actual commands/lock observation do not overlap')
    if observer['waiting_pid'] != b['pid'] or a['pid'] not in observer['blocking_pids']:
        raise ValueError('The independent observation does not show B waiting on A')
    if observer['wait_event_type'] != 'Lock':
        raise ValueError('The observer must retain the actual lock wait')
    checks = race['postconditions']
    if not checks or any(type(check.get('passed')) is not bool or
                         not check.get('query') or 'result' not in check for check in checks):
        raise ValueError('Actual postcondition queries/results are required')
    return {'name': race['name'], 'direction': race['direction'],
        'pids': pids, 'actual_overlap_recorded': True,
        'postconditions_passed': all(check['passed'] for check in checks)}


def evaluate(evidence):
    context = evidence['context']
    for key in ('source_snapshot_sha256', 'installed_ledger_sha256'):
        if not re.fullmatch(r'[a-fA-F0-9]{64}', context.get(key, '')):
            raise ValueError('Current source and installed ledger fingerprints are required')
    for key in ('tenant_id', 'legal_entity_id', 'branch_id', 'workload', 'dataset', 'actor_basis'):
        if not context.get(key):
            raise ValueError('Missing documented runtime context: ' + key)
    families = [latency_family(family) for family in evidence.get('latency', [])]
    if len({family['name'] for family in families}) != len(families):
        raise ValueError('Latency families must have distinct names')
    raw_races = evidence.get('races', [])
    races = [race_observation(race) for race in raw_races]
    command_ids = set()
    observations = set()
    for race in raw_races:
        for session in (race['session_a'], race['session_b']):
            if session['command_id'] in command_ids:
                raise ValueError('A command observation cannot fill multiple race/order records')
            command_ids.add(session['command_id'])
        observer = race['observer']
        identity = (observer['pid'], instant(observer['observed_at']), observer['waiting_pid'],
                    tuple(sorted(observer['blocking_pids'])))
        if identity in observations:
            raise ValueError('An identical lock observation cannot fill multiple race/order records')
        observations.add(identity)
    seen = {(race['name'], race['direction']) for race in races}
    if len(seen) != len(races):
        raise ValueError('Each race and ordering requires its own distinct evidence')
    missing = [{'name': name, 'direction': direction} for name in RACES
        for direction in ('forward', 'reversed') if (name, direction) not in seen]
    return {'scope': 'structural and statistical review of supplied observations only',
        'latency': families, 'races': races, 'missing_races': missing,
        'supplied_latency_meets_targets': bool(families) and
            all(family['observations_meet_target'] for family in families),
        'supplied_contention_matrix_complete': not missing and
            all(race['postconditions_passed'] for race in races),
        'wave4_complete': False,
        'limitations': 'Input authenticity, installed behavior, authenticated native, Credential Manager restart and owner acceptance require independent evidence; passing this validator cannot close them.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    paths = [(ROOT / name).resolve() for name in (args.input, args.output)]
    if any(not path.is_relative_to(ROOT) for path in paths):
        raise ValueError('Runtime evidence paths must stay in this workspace')
    raw = paths[0].read_bytes()
    result = evaluate(json.loads(raw))
    result['input_sha256'] = hashlib.sha256(raw).hexdigest()
    result['validator_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    paths[1].write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'output': args.output, 'wave4_complete': False,
        'missing_races': len(result['missing_races'])}))


if __name__ == '__main__':
    main()
