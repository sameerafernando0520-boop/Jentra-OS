import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';
import 'support/wave4_gateway_harness.dart';

Map<String, Object?> doc(
  String checksum, {
  String status = 'active',
  int recordVersion = 2,
}) => {
  'id': w4Id,
  'version': 1,
  'digest': 'a' * 64,
  'record_version': recordVersion,
  'status': status,
  'purpose': 'Synthetic private receipt',
  'mime': 'application/pdf',
  'byte_size': 4,
  'checksum': checksum,
  'policy_id': w4Revision,
  'retired_at': null,
  'purge_after': null,
  'hold_review_date': null,
};
void main() {
  late Wave4GatewayHarness h;
  late SupabaseExpenseEvidenceGateway gateway;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabaseExpenseEvidenceGateway(h.client);
  });
  tearDown(() => h.dispose());
  Map<String, Object?> reserve() => {
    'action': 'reserve',
    'id': w4Id,
    'project_id': w4Id,
    'expense_id': w4Revision,
    'purpose': 'Synthetic private receipt',
    'mime': 'application/pdf',
    'byte_size': 4,
    'checksum': 'b' * 64,
  };
  CommandEnvelope<Map<String, Object?>> command(
    Map<String, Object?> p,
    int version,
  ) => CommandEnvelope(
    commandId: w4Command,
    idempotencyKey: w4Command,
    context: w4Scope,
    clientTimestamp: DateTime.utc(2026, 10, 5),
    expectedEntityVersion: version,
    payload: p,
  );
  Map<String, Object?> answer(Map<String, Object?> p, int version) =>
      h.confirmed({
        ...h.scope(),
        'id': p['id'],
        'version': 1,
        'digest': 'a' * 64,
        'record_version': version,
        'status': 'reserved',
        'project_id': p['project_id'],
        'expense_id': p['expense_id'],
        'action': p['action'],
      });
  test('availability confirms full expense scope and current actor', () async {
    h.response = {
      ...h.scope(),
      'project_id': w4Id,
      'expense_id': w4Revision,
      'actor_id': w4Scope.actorId,
      'authorized': true,
      'available': false,
    };
    expect(
      await gateway.authorize(w4Scope, w4Id, w4Revision, expenseEvidenceView),
      false,
    );
    h.response = {...h.response as Map, 'expense_id': w4Id};
    await expectLater(
      gateway.authorize(w4Scope, w4Id, w4Revision, expenseEvidenceView),
      throwsFormatException,
    );
  });
  test(
    'policy command and own receipt accept only the scoped minimal confirmation',
    () async {
      final payload = <String, Object?>{
        'action': 'policy_create',
        'id': w4Id,
        'retention_days': 30,
        'purpose': 'Synthetic explicit entity policy',
      };
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 1,
        'action': 'policy_create',
      });
      expect((await gateway.command(command(payload, 0))).recordVersion, 1);
      expect((await gateway.receipt(w4Scope, w4Command))!.commandId, w4Command);
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 1,
        'action': 'policy_create',
        'expense_id': w4Revision,
      });
      await expectLater(
        gateway.command(command(payload, 0)),
        throwsFormatException,
      );
    },
  );
  test('metadata rejects storage paths and wrong expense envelope', () async {
    h.response = {
      ...h.scope(),
      'project_id': w4Id,
      'expense_id': w4Revision,
      'items': [
        {...doc('b' * 64), 'object_path': 'private'},
      ],
      'next_after': null,
    };
    await expectLater(
      gateway.documents(w4Scope, w4Id, w4Revision),
      throwsFormatException,
    );
    h.response = {
      ...h.scope(),
      'project_id': w4Id,
      'expense_id': w4Id,
      'items': [],
      'next_after': null,
    };
    await expectLater(
      gateway.documents(w4Scope, w4Id, w4Revision),
      throwsFormatException,
    );
  });
  test('paging rejects duplicate identities and forged cursors', () async {
    h.response = {
      ...h.scope(),
      'project_id': w4Id,
      'expense_id': w4Revision,
      'items': [doc('b' * 64), doc('b' * 64)],
      'next_after': null,
    };
    await expectLater(
      gateway.documents(w4Scope, w4Id, w4Revision),
      throwsFormatException,
    );
    h.response = {
      ...h.scope(),
      'project_id': w4Id,
      'expense_id': w4Revision,
      'items': [doc('b' * 64)],
      'next_after': w4Id,
    };
    await expectLater(
      gateway.documents(w4Scope, w4Id, w4Revision),
      throwsFormatException,
    );
  });
  test('command snapshots private metadata before awaited transport', () async {
    final p = reserve();
    h.gate = Completer<void>();
    h.response = answer(p, 1);
    final future = gateway.command(command(p, 0));
    p['checksum'] = 'c' * 64;
    p['purpose'] = 'changed';
    await Future<void>.delayed(Duration.zero);
    h.gate!.complete();
    await future;
    final wire = jsonDecode(h.requests.last.body) as Map;
    expect((wire['p_payload'] as Map)['checksum'], 'b' * 64);
    expect((wire['p_payload'] as Map)['purpose'], 'Synthetic private receipt');
  });
  test(
    'wrong confirmation preserves uncertainty and rejects unrelated proof state',
    () async {
      final p = reserve();
      h.response = answer(p, 2);
      await expectLater(
        gateway.command(command(p, 0)),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'binary delivery verifies exact checksum and passes export as separate operation',
    () async {
      final bytes = Uint8List.fromList([37, 80, 68, 70]),
          checksum = (await Sha256().hash(
            bytes,
          )).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      final d = ExpenseEvidenceDocument.fromJson(doc(checksum));
      h.onRequest = (r) async => http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
      expect(
        await gateway.document(w4Scope, w4Id, w4Revision, d, export: true),
        bytes,
      );
      final meta =
          jsonDecode(
                utf8.decode(
                  base64Decode(
                    h.requests.last.headers['x-jentra-expense-request']!,
                  ),
                ),
              )
              as Map;
      expect(meta['expense_id'], w4Revision);
      expect(meta['operation'], 'export');
      expect(meta.containsKey('object_path'), false);
      h.onRequest = (r) async => http.Response.bytes(
        [1, 2, 3, 4],
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
      await expectLater(
        gateway.document(w4Scope, w4Id, w4Revision, d),
        throwsFormatException,
      );
    },
  );
  test(
    'upload copies bytes before awaits and rejects caller scope injection',
    () async {
      final bytes = Uint8List.fromList([37, 80, 68, 70]),
          checksum = (await Sha256().hash(
            bytes,
          )).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      final d = ExpenseEvidenceDocument.fromJson(
        doc(checksum, status: 'reserved', recordVersion: 1),
      );
      final p = {
        'action': 'complete',
        'id': w4Id,
        'project_id': w4Id,
        'expense_id': w4Revision,
      };
      h.response = {
        ...answer(p, 2),
        'entity': {...answer(p, 2)['entity'] as Map, 'status': 'active'},
      };
      final future = gateway.upload(command(p, 1), d, bytes);
      bytes[0] = 0;
      await future;
      expect(h.requests.last.bodyBytes, [37, 80, 68, 70]);
    },
  );
  test(
    'private errors are sanitized and inactive bytes never reach transport',
    () async {
      h.status = 403;
      h.response = {'code': '42501', 'message': 'PRIVATE_RECEIPT_PATH'};
      await expectLater(
        gateway.documents(w4Scope, w4Id, w4Revision),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', 'PERMISSION_DENIED')
              .having(
                (e) => e.message.contains('PRIVATE_RECEIPT_PATH'),
                'private',
                false,
              ),
        ),
      );
      final calls = h.requests.length;
      await expectLater(
        gateway.document(
          w4Scope,
          w4Id,
          w4Revision,
          ExpenseEvidenceDocument.fromJson(doc('b' * 64, status: 'purged')),
        ),
        throwsFormatException,
      );
      expect(h.requests.length, calls);
    },
  );
}
