"""Validator tests are synthetic fixtures, not real contention or load evidence."""
import unittest
import copy
from datetime import datetime, timedelta, timezone
from evaluate_runtime_evidence import RACES, evaluate, latency_family, race_observation


def family(kind='read'):
    return {'name': 'directory', 'kind': kind,
        'warmup': [{'id': 'w' + str(i), 'elapsed_ms': '1', 'outcome': 'success'} for i in range(20)],
        'measured': [{'id': 'm' + str(i), 'elapsed_ms': str(i + 1), 'outcome': 'success'} for i in range(100)]}


def race():
    return {'name': 'employee_code', 'direction': 'forward',
        'session_a': {'pid': 101, 'command_id': 'a', 'started': '2026-10-05T00:00:00Z',
            'finished': '2026-10-05T00:00:01Z', 'committed': '2026-10-05T00:00:03Z'},
        'session_b': {'pid': 102, 'command_id': 'b', 'started': '2026-10-05T00:00:02Z',
            'finished': '2026-10-05T00:00:04Z', 'committed': '2026-10-05T00:00:05Z'},
        'observer': {'pid': 103, 'observed_at': '2026-10-05T00:00:02.5Z',
            'waiting_pid': 102, 'blocking_pids': [101], 'wait_event_type': 'Lock'},
        'postconditions': [{'query': 'select count(*) from synthetic_results', 'result': 1, 'passed': True}]}


class RuntimeEvidenceTests(unittest.TestCase):
    def test_nearest_rank_is_observation_95(self):
        self.assertEqual(latency_family(family())['p95_ms'], '95')

    def test_fractional_observations_are_exact(self):
        value = family()
        for sample in value['measured']:
            sample['elapsed_ms'] = '500.000000000000000001'
        self.assertFalse(latency_family(value)['observations_meet_target'])

    def test_failures_are_retained_and_block_target_claim(self):
        value = family()
        value['measured'][0]['outcome'] = 'failure'
        result = latency_family(value)
        self.assertEqual(result['count'], 100)
        self.assertEqual(result['failure_count'], 1)
        self.assertFalse(result['observations_meet_target'])

    def test_unavailable_is_never_latency_success(self):
        value = family()
        value['measured'][0]['outcome'] = 'unavailable'
        self.assertFalse(latency_family(value)['observations_meet_target'])

    def test_duplicate_samples_rejected(self):
        value = family()
        value['measured'][1]['id'] = value['measured'][0]['id']
        with self.assertRaises(ValueError):
            latency_family(value)

    def test_insufficient_measurements_rejected(self):
        value = family()
        value['measured'].pop()
        with self.assertRaises(ValueError):
            latency_family(value)

    def test_command_target_is_1500(self):
        self.assertEqual(latency_family(family('command'))['target_ms'], '1500')

    def test_insufficient_warmup_rejected(self):
        value = family()
        value['warmup'].pop()
        with self.assertRaises(ValueError):
            latency_family(value)

    def test_genuine_three_session_overlap_is_consistent(self):
        self.assertTrue(race_observation(race())['actual_overlap_recorded'])

    def test_sequential_calls_rejected(self):
        value = race()
        value['session_b']['started'] = '2026-10-05T00:00:03Z'
        with self.assertRaises(ValueError):
            race_observation(value)

    def test_reused_backend_rejected(self):
        value = race()
        value['observer']['pid'] = 101
        with self.assertRaises(ValueError):
            race_observation(value)

    def test_missing_real_blocker_rejected(self):
        value = race()
        value['observer']['blocking_pids'] = []
        with self.assertRaises(ValueError):
            race_observation(value)

    def test_naive_timezone_rejected(self):
        value = race()
        value['observer']['observed_at'] = '2026-10-05T00:00:02.5'
        with self.assertRaises(ValueError):
            race_observation(value)

    def test_no_observations_never_complete(self):
        context = {key: 'documented synthetic fixture' for key in
            ('tenant_id', 'legal_entity_id', 'branch_id', 'workload', 'dataset', 'actor_basis')}
        context.update(source_snapshot_sha256='a' * 64, installed_ledger_sha256='b' * 64)
        result = evaluate({'context': context})
        self.assertFalse(result['supplied_latency_meets_targets'])
        self.assertFalse(result['supplied_contention_matrix_complete'])
        self.assertFalse(result['wave4_complete'])
        self.assertEqual(len(result['missing_races']), 34)

    def test_failed_postcondition_retained(self):
        value = race()
        value['postconditions'][0]['passed'] = False
        self.assertFalse(race_observation(value)['postconditions_passed'])

    def test_missing_query_result_rejected(self):
        value = race()
        del value['postconditions'][0]['result']
        with self.assertRaises(ValueError):
            race_observation(value)

    def test_non_string_command_identity_rejected(self):
        value = race()
        value['session_a']['command_id'] = 123
        with self.assertRaises(ValueError):
            race_observation(value)

    def test_cloned_overlap_cannot_fill_matrix(self):
        context = {key: 'documented synthetic fixture' for key in
            ('tenant_id', 'legal_entity_id', 'branch_id', 'workload', 'dataset', 'actor_basis')}
        context.update(source_snapshot_sha256='a' * 64, installed_ledger_sha256='b' * 64)
        rows = []
        for name in RACES:
            for direction in ('forward', 'reversed'):
                value = copy.deepcopy(race())
                value.update(name=name, direction=direction)
                rows.append(value)
        with self.assertRaises(ValueError):
            evaluate({'context': context, 'races': rows})

    def test_relabelled_lock_observation_rejected_with_new_commands(self):
        context = {key: 'documented synthetic fixture' for key in
            ('tenant_id', 'legal_entity_id', 'branch_id', 'workload', 'dataset', 'actor_basis')}
        context.update(source_snapshot_sha256='a' * 64, installed_ledger_sha256='b' * 64)
        first, second = race(), race()
        second['direction'] = 'reversed'
        second['session_a']['command_id'] = 'new-a'
        second['session_b']['command_id'] = 'new-b'
        with self.assertRaises(ValueError):
            evaluate({'context': context, 'races': [first, second]})

    def test_distinct_full_matrix_consistent_without_wave_completion(self):
        context = {key: 'documented synthetic fixture' for key in
            ('tenant_id', 'legal_entity_id', 'branch_id', 'workload', 'dataset', 'actor_basis')}
        context.update(source_snapshot_sha256='a' * 64, installed_ledger_sha256='b' * 64)
        base = datetime(2026, 10, 5, tzinfo=timezone.utc)
        rows = []
        for name in RACES:
            for direction in ('forward', 'reversed'):
                value = copy.deepcopy(race())
                value.update(name=name, direction=direction)
                start = base + timedelta(seconds=len(rows) * 10)
                for session, seconds in (('session_a', (0, 1, 3)), ('session_b', (2, 4, 5))):
                    value[session]['command_id'] = name + direction + session
                    for key, offset in zip(('started', 'finished', 'committed'), seconds):
                        value[session][key] = (start + timedelta(seconds=offset)).isoformat()
                value['observer']['observed_at'] = (start + timedelta(seconds=2.5)).isoformat()
                rows.append(value)
        result = evaluate({'context': context, 'races': rows})
        self.assertTrue(result['supplied_contention_matrix_complete'])
        self.assertFalse(result['wave4_complete'])


if __name__ == '__main__':
    unittest.main()
