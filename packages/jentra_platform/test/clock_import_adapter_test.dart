import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'support/wave4_gateway_harness.dart';

const csv =
    'source_key,observed_utc\nSYN-1,2026-09-30T03:30:00Z\nSYN-2,2026-09-30T11:30:00Z';
void main() {
  late Wave4GatewayHarness h;
  late SupabaseWorkforceGateway gateway;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabaseWorkforceGateway(h.client);
  });
  tearDown(() => h.dispose());
  Future<Map<String, Object?>> payload() =>
      prepareClockBatch(w4Scope, w4Scope.actorId, 'Synthetic clock', csv);
  CommandEnvelope<Map<String, Object?>> command(Map<String, Object?> p) =>
      CommandEnvelope(
        commandId: w4Command,
        idempotencyKey: w4Command,
        context: w4Scope,
        payload: p,
        clientTimestamp: DateTime.utc(2026, 9, 30),
        expectedEntityVersion: 0,
      );
  Map<String, Object?> receipt(Map<String, Object?> p) => {
    ...h.scope(),
    'id': p['id'],
    'employee_id': p['employee_id'],
    'version': 1,
    'row_count': 2,
    'imported_count': 1,
    'reused_count': 1,
    'manifest_digest': p['manifest_digest'],
  };
  test(
    'row checksums match the PostgreSQL UTF-8 oracle and preserve event order',
    () async {
      final p = await payload();
      final rows = (p['records'] as List).cast<Map<String, Object?>>();
      expect(
        rows.first['checksum'],
        '67c172aa6330c5741e9d01b8ba3640bc365c9779250247752c65c6e73ad49703',
      );
      expect(rows.map((r) => r['source_key']), ['SYN-1', 'SYN-2']);
      expect(rows.map((r) => r['id']).toSet().length, 2);
      validateClockBatch(p);
      final other = await prepareClockBatch(
        w4Scope,
        w4Id,
        'Synthetic clock',
        csv,
      );
      expect(
        (other['records'] as List).first['checksum'],
        isNot(rows.first['checksum']),
      );
      expect(other['manifest_digest'], isNot(p['manifest_digest']));
    },
  );
  test('named batch RPC accepts conserved minimal confirmation', () async {
    final p = await payload();
    h.response = h.confirmed(receipt(p));
    final result = await gateway.execute(
      WorkforceCommandKind.attendance,
      command(p),
    );
    expect(result['imported_count'], 1);
    expect(
      h.requests.last.url.path,
      endsWith('/people_attendance_clock_batch'),
    );
  });
  test(
    'forged counts, digests and private fields cannot confirm imports',
    () async {
      final p = await payload();
      for (final mutation in [
        {'imported_count': 2},
        {'manifest_digest': 'a' * 64},
        {'salary': '100'},
        {'employee_id': w4Revision},
        {'version': 2},
      ]) {
        h.response = h.confirmed({...receipt(p), ...mutation});
        await expectLater(
          gateway.execute(WorkforceCommandKind.attendance, command(p)),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'UNCERTAIN_RESULT',
            ),
          ),
        );
      }
    },
  );
  test(
    'changed duplicate is definite and contains no private server detail',
    () async {
      final p = await payload();
      h.status = 400;
      h.response = {
        'code': '55000',
        'message': 'CLOCK_SOURCE_CONFLICT',
        'details': 'private employee data',
      };
      await expectLater(
        gateway.execute(WorkforceCommandKind.attendance, command(p)),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', 'CLOCK_SOURCE_CONFLICT')
              .having((e) => e.message.contains('private'), 'leak', false),
        ),
      );
    },
  );
  test(
    'uncertain batch freezes nested row evidence before awaiting transport',
    () async {
      final p = await payload();
      h.response = h.confirmed(receipt(p));
      h.gate = Completer<void>();
      final sending = gateway.execute(
        WorkforceCommandKind.attendance,
        command(p),
      );
      while (h.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      (p['records'] as List).first['source_key'] = 'Changed after send';
      h.gate!.complete();
      await sending;
      final body = jsonDecode(h.requests.single.body) as Map;
      expect(body['p_payload']['records'][0]['source_key'], 'SYN-1');
    },
  );
  test(
    'batch history validates employee scope, ordered lineage and bounds',
    () async {
      final p = await payload();
      final batch = {
        'id': p['id'],
        'source_system': 'Synthetic clock',
        'row_count': 2,
        'imported_count': 1,
        'manifest_digest': p['manifest_digest'],
        'imported_by': w4Scope.actorId,
        'imported_at': '2026-09-30T00:00:00Z',
      };
      final rows = (p['records'] as List).cast<Map<String, Object?>>();
      final response = {
        ...h.scope(),
        'employee_id': w4Scope.actorId,
        'batch': batch,
        'rows': [
          for (final (index, row) in rows.indexed)
            {
              'position': index + 1,
              'event_id': row['id'],
              'source_key': row['source_key'],
              'observed_utc': row['observed_utc'],
              'checksum': row['checksum'],
              'reused': index == 0,
            },
        ],
        'next_position': null,
      };
      h.response = response;
      final detail = await gateway.clockBatchDetail(
        w4Scope,
        w4Scope.actorId,
        p['id'] as String,
      );
      expect(detail.rows.first.reused, isTrue);
      for (final mutation in [
        {'employee_id': w4Id},
        {'rows': []},
        {'next_position': 1},
        {
          'batch': {...batch, 'salary': '100'},
        },
      ]) {
        h.response = {...response, ...mutation};
        await expectLater(
          gateway.clockBatchDetail(w4Scope, w4Scope.actorId, p['id'] as String),
          throwsFormatException,
        );
      }
    },
  );
}
