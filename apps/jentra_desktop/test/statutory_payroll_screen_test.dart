import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_desktop/src/features/people/statutory_payroll_screen.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const setId = '40000000-0000-0000-0000-000000000001';

Map<String, Object?> setRow(String status) => {
  'id': setId,
  'country_code': 'LK',
  'effective_from': '2025-04-01',
  'effective_to_exclusive': '2027-04-01',
  'epf_employee_percent': '8.000000',
  'epf_employer_percent': '12.000000',
  'etf_employer_percent': '3.000000',
  'apit_table': 'LK_APIT_TABLE_01',
  'apit_bands': [
    {'upto': '150000', 'rate': '0', 'reduction': '0'},
    {'upto': null, 'rate': '36', 'reduction': '94000'},
  ],
  'sources': {'epf': 'https://epf.lk/?page_id=811'},
  'status': status,
  'proposed_by': '10000000-0000-0000-0000-000000000009',
  'approved_by': status == 'pending' ? null : scope.actorId,
};

final class FakeStatutory implements LkStatutoryPayrollRepository {
  String status = 'pending';
  final calls = <String>[];

  @override
  Future<List<LkStatutoryRuleSetRecord>> ruleSets(TenantContext scope) async =>
      [LkStatutoryRuleSetRecord.fromJson(setRow(status))];

  @override
  Future<LkStatutoryRuleSetRecord> proposeLk(
    TenantContext scope, {
    required String id,
    required String effectiveFrom,
    required String effectiveToExclusive,
  }) async {
    calls.add('propose $effectiveFrom $effectiveToExclusive');
    return LkStatutoryRuleSetRecord.fromJson(setRow('pending'));
  }

  @override
  Future<LkStatutoryRuleSetRecord> decide(
    TenantContext scope,
    String id,
    String action,
  ) async {
    calls.add('$action $id');
    status = action == 'approve' ? 'approved' : 'retired';
    return LkStatutoryRuleSetRecord.fromJson(setRow(status));
  }

  @override
  Future<List<LkComponentStatutoryRecord>> classifications(
    TenantContext scope,
  ) async => const [];

  @override
  Future<void> classify(
    TenantContext scope, {
    required String id,
    required String componentId,
    required bool epfLiable,
    required bool etfLiable,
    required bool apitRegularProfit,
    required String reason,
  }) async => calls.add(
    'classify $componentId $epfLiable $etfLiable $apitRegularProfit',
  );

  @override
  Future<LkEmployeeStatutoryDetails?> employee(
    TenantContext scope,
    String employeeId,
  ) async => null;

  @override
  Future<void> saveEmployee(
    TenantContext scope, {
    required String id,
    required String employeeId,
    required LkEmployeeStatutoryDetails details,
    required String reason,
  }) async => calls.add('employee $employeeId ${details.nic}');

  @override
  Future<LkEmployerRegistration?> employer(TenantContext scope) async => null;

  @override
  Future<void> saveEmployer(
    TenantContext scope, {
    required String id,
    required String epfEmployerNumber,
    required String etfEmployerNumber,
    required String reason,
  }) async => calls.add('employer $epfEmployerNumber $etfEmployerNumber');
}

Future<FakeStatutory> pump(
  WidgetTester tester, {
  Set<String> permissions = const {
    'people.payroll.view',
    'people.payroll.configure',
    'people.payroll.approve',
  },
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeStatutory();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatutoryPayrollWorkspace(
          scope: scope,
          permissions: permissions,
          repository: fake,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('approving rates needs the sources confirmation', (tester) async {
    final fake = await pump(tester);
    expect(find.textContaining('Pending approval'), findsOneWidget);
    await tester.tap(find.textContaining('2025-04-01 to 2027-04-01'));
    await tester.pumpAndSettle();
    expect(find.textContaining('epf: https://epf.lk'), findsOneWidget);
    await tester.tap(find.text('Approve rates'));
    await tester.pumpAndSettle();
    final approve = find.widgetWithText(FilledButton, 'Approve');
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(fake.calls, ['approve $setId']);
    expect(find.text('Rates approved.'), findsOneWidget);
    expect(find.textContaining('Approved ·'), findsOneWidget);
  });

  testWidgets('configurers propose the checked Sri Lanka periods', (
    tester,
  ) async {
    final fake = await pump(tester);
    await tester.tap(find.textContaining('Propose Sri Lanka rates'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['propose 2025-04-01 2027-04-01']);
  });

  testWidgets('viewers cannot propose or approve', (tester) async {
    await pump(tester, permissions: const {'people.payroll.view'});
    expect(find.textContaining('Propose Sri Lanka rates'), findsNothing);
    await tester.tap(find.textContaining('2025-04-01 to 2027-04-01'));
    await tester.pumpAndSettle();
    expect(find.text('Approve rates'), findsNothing);
  });

  test('every statutory blocker has its own explanation', () {
    const codes = [
      'STATUTORY_LKR_REQUIRED',
      'STATUTORY_INPUTS_MISSING',
      LkStatutoryBlocker.approvedRuleSetRequired,
      LkStatutoryBlocker.employeeDetailsRequired,
      LkStatutoryBlocker.nicRequired,
      LkStatutoryBlocker.coverageReviewRequired,
      LkStatutoryBlocker.epfMemberNumberRequired,
      LkStatutoryBlocker.apitOtherTableRequired,
      LkStatutoryBlocker.apitNonresidentReviewRequired,
      LkStatutoryBlocker.apitPrimaryDeclarationRequired,
      LkStatutoryBlocker.apitTable05Required,
      LkStatutoryBlocker.apitMonthlyPeriodRequired,
      LkStatutoryBlocker.earningsRequired,
      LkStatutoryBlocker.earningsUnclassified,
    ];
    final fallback = lkStatutoryBlockerMessage('UNKNOWN');
    final messages = {for (final c in codes) lkStatutoryBlockerMessage(c)};
    expect(messages, hasLength(codes.length));
    expect(messages, isNot(contains(fallback)));
  });

  test('NIC validation accepts old and new formats only', () {
    expect(LkEmployeeStatutoryDetails.validNic('901234567V'), isTrue);
    expect(LkEmployeeStatutoryDetails.validNic('199012345678'), isTrue);
    expect(LkEmployeeStatutoryDetails.validNic('12345'), isFalse);
  });

  test('rule versions with the statutory basis parse', () {
    final rule = PayrollRuleVersion.fromJson({
      'id': '50000000-0000-0000-0000-000000000001',
      'component_id': '50000000-0000-0000-0000-000000000002',
      'version': 1,
      'code': 'EPF_EE',
      'name': 'EPF employee',
      'classification': 'deduction',
      'basis': 'statutory',
      'proration': 'none',
      'rounding': 'half_away',
      'precision': 2,
      'amount': '0',
      'ratio_numerator': 1,
      'ratio_denominator': 1,
      'cap': null,
      'currency_code': 'LKR',
      'start_date': '2025-04-01',
      'end_date_exclusive': '2027-04-01',
      'reason': 'EPF employee contribution',
      'published_by': scope.actorId,
      'published_at': '2026-11-20T00:00:00Z',
      'expense_account_id': null,
      'liability_account_id': '50000000-0000-0000-0000-000000000003',
    });
    expect(rule.rule.basis, PayrollBasis.statutory);
  });
}
