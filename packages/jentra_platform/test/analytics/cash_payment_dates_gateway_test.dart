import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'dated_cash_gateway_test.dart' show cashWire, id;

final scope = ProcessMetricScope(
  tenantId: id(1),
  legalEntityId: id(2),
  branchId: id(3),
);

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Map<String, Object?> dateRow({
  String kind = 'payroll_obligation',
  bool recovery = false,
}) => {
  'sourceKind': kind,
  'sourceId': id(20),
  'sourceHash': 'a' * 64,
  'branchId': id(3),
  'currency': 'LKR',
  'originalAmount': recovery ? '-2.000002' : '10.000001',
  'remainingAmount': recovery ? '-1.000001' : '7.000001',
  'inflow': recovery,
  'issueDate': '2026-09-29',
  'approved': null,
};
Future<Map<String, Object?>> fullWire({
  bool complete = true,
  bool falseProjectInflow = false,
}) async {
  final old = await cashWire();
  final data =
      jsonDecode(old['canonicalText'] as String) as Map<String, dynamic>;
  data['contractRevision'] = 3;
  data['definition'] = 'dated_transaction_cash_all_obligations.v3';
  (data['providerStatus'] as Map<String, dynamic>).addAll({
    'payroll': complete ? 'available' : 'missing_payment_date',
    'project_reimbursements': 'available',
  });
  (data['completeProviders'] as List).addAll([
    if (complete) 'payroll',
    'project_reimbursements',
  ]);
  for (final row in data['obligations'] as List) {
    row['inflow'] = row['provider'] == 'receivables';
  }
  (data['obligations'] as List).addAll([
    if (complete)
      {
        'id': id(30),
        'branchId': id(3),
        'currency': 'LKR',
        'dueDate': '2026-10-02',
        'version': '2',
        'amount': '7.000001',
        'provider': 'payroll',
        'inflow': false,
      },
    if (complete)
      {
        'id': id(31),
        'branchId': id(3),
        'currency': 'LKR',
        'dueDate': '2026-10-02',
        'version': '1',
        'amount': '2.000002',
        'provider': 'payroll',
        'inflow': true,
      },
    {
      'id': id(32),
      'branchId': id(3),
      'currency': 'LKR',
      'dueDate': '2026-10-02',
      'version': '1',
      'amount': '4.000000',
      'provider': 'project_reimbursements',
      'inflow': falseProjectInflow,
    },
  ]);
  data['exclusions'] = ['overdue_before_horizon', 'unallocated_credits'];
  final canonical = jsonEncode(data);
  return {
    'canonicalText': canonical,
    'sourceHash': await ProcessMetricSha256Hasher().sha256(
      utf8.encode(canonical),
    ),
  };
}

void main() {
  test(
    'v3 exact five-provider cash includes payroll recovery and reimbursements',
    () async {
      final b = await DatedCashGateway(
        (_, _) => fullWire(),
      ).read(scope, '2026-10-01', '2026-10-03', '2026-10-01T00:00:00Z');
      final r = CashScenarioRevision(
        id: id(40),
        scope: scope,
        sourceHash: b.hash,
        horizonStart: b.start,
        horizonEnd: b.end,
        recordedThrough: b.recordedThrough,
        overrides: {},
      );
      expect(b.contractRevision, 3);
      expect(b.requiredProviders.length, 5);
      expect(
        b
            .project(r, requiredProviders: b.requiredProviders)
            .buckets
            .last
            .exactBalance,
        '4.000003',
      );
    },
  );
  test(
    'v3 missing dates yield no projection instead of a partial complete result',
    () async {
      final b = await DatedCashGateway(
        (_, _) => fullWire(complete: false),
      ).read(scope, '2026-10-01', '2026-10-03', '2026-10-01T00:00:00Z');
      final r = CashScenarioRevision(
        id: id(40),
        scope: scope,
        sourceHash: b.hash,
        horizonStart: b.start,
        horizonEnd: b.end,
        recordedThrough: b.recordedThrough,
        overrides: {},
      );
      final result = b.project(r, requiredProviders: b.requiredProviders);
      expect(result.available, false);
      expect(result.buckets, isEmpty);
      expect(result.unavailableProviders, ['payroll']);
    },
  );
  test(
    'reimbursement inflow and mismatched date source families fail closed',
    () async {
      await expectLater(
        DatedCashGateway(
          (_, _) => fullWire(falseProjectInflow: true),
        ).read(scope, '2026-10-01', '2026-10-03', '2026-10-01T00:00:00Z'),
        throwsFormatException,
      );
      expect(
        () => CashPaymentDateSource(dateRow(), 'project_reimbursement'),
        throwsFormatException,
      );
      expect(
        () => CashPaymentDateSource(
          dateRow(recovery: true),
          'payroll_obligation',
        ),
        throwsFormatException,
      );
      final recovery = CashPaymentDateSource(
        dateRow(kind: 'payroll_correction', recovery: true),
        'payroll_correction',
      );
      expect(recovery.inflow, true);
      expect(recovery.remaining, BigInt.from(-1000001));
    },
  );
  test(
    'wrong branch, duplicate cursor and foreign source responses are rejected',
    () async {
      for (final rows in [
        [
          {...dateRow(), 'branchId': id(4)},
        ],
        [dateRow(), dateRow()],
      ]) {
        final gateway = CashPaymentDatesGateway(
          (_, _) async => {'rows': rows, 'next': null},
        );
        await expectLater(
          gateway.sources(scope, 'payroll_obligation'),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'date authority captures exact source version and validates command receipt identity',
    () async {
      final envelope = <String, Object?>{
        'commandId': id(42),
        'idempotencyKey': id(43),
        'clientTimestamp': '2026-10-01T00:00:00Z',
        'action': 'approve',
        'payload': {'id': id(44), 'proposalHash': 'b' * 64},
      };
      final gateway = CashPaymentDatesGateway((name, params) async {
        expect(name, 'wave5_cash_date_command');
        expect(params['p_command_id'], id(42));
        return {
          'entity': {
            'id': id(45),
            'proposalHash': 'b' * 64,
            'version': '1',
            'status': 'approved',
          },
        };
      });
      await expectLater(
        gateway.command(scope, envelope),
        throwsFormatException,
      );
    },
  );
  test(
    'original date command survives encrypted database restart; source namespace and revocation isolate it',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'jentra-w5-date-restart-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/owned-test.sqlite'), keys = Keys();
      var allowed = true;
      Future<void> authorize(ProcessMetricScope s, String actor) async {
        if (!allowed || actor != id(50)) throw StateError('revoked');
      }

      var db = JentraLocalDatabase(NativeDatabase(file));
      var drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
      final original = <String, Object?>{
        'commandId': id(51),
        'idempotencyKey': id(52),
        'clientTimestamp': '2026-10-01T00:00:00Z',
        'action': 'prepare',
        'payload': {
          'id': id(53),
          'sourceKind': 'payroll_obligation',
          'sourceId': id(20),
          'sourceHash': 'a' * 64,
          'dueDate': '2026-10-02',
          'reasonCode': 'payroll_calendar',
          'expectedVersion': '1',
        },
      };
      await Wave5CommandStore(
        drafts,
        authorize,
        namespace: 'cash_dates_payroll_obligation',
      ).save(scope, id(50), original);
      final cipher =
          (await db.select(db.encryptedDrafts).get()).single.encryptedPayload;
      expect(String.fromCharCodes(cipher), isNot(contains('payroll_calendar')));
      await db.close();
      db = JentraLocalDatabase(NativeDatabase(file));
      addTearDown(db.close);
      drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
      final store = Wave5CommandStore(
        drafts,
        authorize,
        namespace: 'cash_dates_payroll_obligation',
      );
      expect(await store.restore(scope, id(50)), original);
      expect(
        await Wave5CommandStore(
          drafts,
          authorize,
          namespace: 'cash_dates_project_reimbursement',
        ).restore(scope, id(50)),
        isNull,
      );
      allowed = false;
      await expectLater(store.restore(scope, id(50)), throwsStateError);
    },
  );
}
