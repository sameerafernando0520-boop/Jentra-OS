import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
Future<Map<String, Object?>> cashWire({
  bool foreign = false,
  bool payableAccess = true,
}) async {
  final data = {
    'contractRevision': 2,
    'definition': 'dated_transaction_cash_ar_and_ap.v2',
    'scope': {
      'tenantId': foreign ? id(9) : id(1),
      'legalEntityId': id(2),
      'branchId': id(3),
    },
    'horizonStart': '2026-10-01',
    'horizonEnd': '2026-10-03',
    'recordedThrough': '2026-10-01T00:00:00Z',
    'completeProviders': [
      'bank_cash',
      'receivables',
      if (payableAccess) 'payables',
    ],
    'providerStatus': {
      'bank_cash': 'available',
      'receivables': 'available',
      'payables': payableAccess ? 'available' : 'permission_required',
      'payroll': 'missing_authoritative_due_date',
      'project_reimbursements': 'missing_authoritative_due_date',
    },
    'controls': [
      {
        'id': id(4),
        'accountId': id(5),
        'branchId': id(3),
        'currency': 'LKR',
        'version': '1',
        'amount': '10.000001',
      },
    ],
    'obligations': [
      {
        'id': id(6),
        'branchId': id(3),
        'currency': 'LKR',
        'dueDate': '2026-10-02',
        'version': '1',
        'amount': '5.000001',
        'provider': 'receivables',
      },
      if (payableAccess)
        {
          'id': id(7),
          'branchId': id(3),
          'currency': 'LKR',
          'dueDate': '2026-10-02',
          'version': '1',
          'amount': '2.000000',
          'provider': 'payables',
        },
    ],
    'sources': [],
    'exclusions': ['payroll', 'project_reimbursements'],
  };
  final text = jsonEncode(data);
  return {
    'canonicalText': text,
    'sourceHash': await ProcessMetricSha256Hasher().sha256(utf8.encode(text)),
  };
}

void main() {
  final scope = ProcessMetricScope(
    tenantId: id(1),
    legalEntityId: id(2),
    branchId: id(3),
  );
  test(
    'dated adapter projects exact cash, AR and authorized AP while reporting missing due-date providers',
    () async {
      final gateway = DatedCashGateway((_, _) => cashWire());
      final b = await gateway.read(
        scope,
        '2026-10-01',
        '2026-10-03',
        '2026-10-01T00:00:00Z',
      );
      final r = CashScenarioRevision(
        id: id(7),
        scope: scope,
        sourceHash: b.hash,
        horizonStart: b.start,
        horizonEnd: b.end,
        recordedThrough: b.recordedThrough,
        overrides: {},
      );
      expect(
        b
            .project(
              r,
              requiredProviders: {'bank_cash', 'receivables', 'payables'},
            )
            .buckets
            .last
            .exactBalance,
        '13.000002',
      );
      expect(
        b
            .project(
              r,
              requiredProviders: {
                'bank_cash',
                'receivables',
                'payables',
                'payroll',
              },
            )
            .available,
        isFalse,
      );
    },
  );
  test(
    'unavailable AP permission never becomes an empty complete provider',
    () async {
      final b = await DatedCashGateway(
        (_, _) => cashWire(payableAccess: false),
      ).read(scope, '2026-10-01', '2026-10-03', '2026-10-01T00:00:00Z');
      expect(b.providerStatus['payables'], 'permission_required');
      expect(b.obligations.map((o) => o.provider), ['receivables']);
      final r = CashScenarioRevision(
        id: id(8),
        scope: scope,
        sourceHash: b.hash,
        horizonStart: b.start,
        horizonEnd: b.end,
        recordedThrough: b.recordedThrough,
        overrides: {},
      );
      expect(
        b
            .project(
              r,
              requiredProviders: {'bank_cash', 'receivables', 'payables'},
            )
            .available,
        isFalse,
      );
    },
  );
  test('foreign cash source and actor mismatch fail before recovery', () async {
    await expectLater(
      DatedCashGateway(
        (_, _) => cashWire(foreign: true),
      ).read(scope, '2026-10-01', '2026-10-03', '2026-10-01T00:00:00Z'),
      throwsFormatException,
    );
    await expectLater(
      DatedCashGateway((_, _) async => id(9)).authorize(scope, id(8)),
      throwsStateError,
    );
  });
}
