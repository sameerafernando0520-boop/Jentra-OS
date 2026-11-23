import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_tax_lk.dart';
import 'package:jentra_platform/jentra_finance_platform.dart'
    show ReportExportFiles;
import 'package:jentra_desktop/src/features/financial_statements/lk_tax_schedules_screen.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const vat18 = '60000000-0000-0000-0000-000000000018';
const mappingId = '70000000-0000-0000-0000-000000000001';

final class FakeFiles implements ReportExportFiles {
  final written = <String, Uint8List>{};

  @override
  Future<String?> choose(String fileName) async => 'C:\\tax\\$fileName';

  @override
  Future<void> write(String path, Uint8List bytes, String mimeType) async =>
      written[path] = bytes;
}

final class FakeTax implements LkTaxRepository {
  bool pending = false;
  String ssclStatus = 'none';
  final calls = <String>[];

  Map<String, Object?> _settings(String status) => {
    'id': '80000000-0000-0000-0000-000000000001',
    'effective_from': '2026-04-01',
    'effective_to_exclusive': '2027-04-01',
    'rate_percent': '2.500000',
    'liable_portion_percent': '50.000000',
    'include_zero_rated': false,
    'include_exempt': false,
    'activity': 'Wholesale and retail',
    'status': status,
    'proposed_by': '10000000-0000-0000-0000-000000000009',
    'sources': {'ird': 'https://www.ird.gov.lk'},
  };

  @override
  Future<List<LkSsclSettings>> ssclSettings(TenantContext scope) async => [
    if (ssclStatus != 'none') LkSsclSettings.fromJson(_settings(ssclStatus)),
  ];

  @override
  Future<LkSsclSettings> proposeSsclSettings(
    TenantContext scope, {
    required String id,
    required String effectiveFrom,
    required String effectiveToExclusive,
    required String ratePercent,
    required String liablePortionPercent,
    required bool includeZeroRated,
    required bool includeExempt,
    required String activity,
    required String reason,
  }) async {
    calls.add(
      'sscl propose $effectiveFrom $effectiveToExclusive $ratePercent $liablePortionPercent $activity',
    );
    ssclStatus = 'pending';
    return LkSsclSettings.fromJson(_settings('pending'));
  }

  @override
  Future<LkSsclSettings> decideSsclSettings(
    TenantContext scope,
    String id,
    String action,
  ) async {
    calls.add('sscl $action');
    ssclStatus = action == 'approve' ? 'approved' : 'retired';
    return LkSsclSettings.fromJson(_settings(ssclStatus));
  }

  @override
  Future<LkSsclReturn> ssclReturn(
    TenantContext scope, {
    required String quarterStart,
  }) async {
    calls.add('sscl return $quarterStart');
    return LkSsclReturn.fromJson({
      'quarter_start': quarterStart,
      'quarter_end_exclusive': '2026-07-01',
      'turnover': {'standard_rated': '5600000.000000', 'untaxed': '0.000000'},
      'included_turnover': '5600000.000000',
      'liable_turnover': '2800000.000000',
      'sscl_due': '70000.000000',
      'settings': _settings('approved'),
      'blockers': const [],
    });
  }

  Map<String, Object?> _mapping(String status) => {
    'id': mappingId,
    'vat_line': 'standard_rated_supply',
    'reason': 'Standard rate',
    'status': status,
    'proposed_by': '10000000-0000-0000-0000-000000000009',
  };

  @override
  Future<List<LkVatMappingRow>> vatMappings(TenantContext scope) async => [
    LkVatMappingRow.fromJson({
      'tax_definition_id': vat18,
      'code': 'VAT18',
      'name': 'VAT 18 percent',
      'kind': 'output',
      'rate': '18.000000',
      'approved': null,
      'pending': pending ? [_mapping('pending')] : const [],
    }),
  ];

  @override
  Future<LkVatMapping> proposeVatMapping(
    TenantContext scope, {
    required String id,
    required String taxDefinitionId,
    required LkVatLine line,
    required String reason,
  }) async {
    calls.add('propose $taxDefinitionId ${line.wire} $reason');
    pending = true;
    return LkVatMapping.fromJson(_mapping('pending'));
  }

  @override
  Future<LkVatMapping> decideVatMapping(
    TenantContext scope,
    String id,
    String action,
  ) async {
    calls.add('$action $id');
    pending = false;
    return LkVatMapping.fromJson(_mapping('approved'));
  }

  @override
  Future<LkVatReturn> vatReturn(
    TenantContext scope, {
    required String from,
    required String toExclusive,
  }) async {
    calls.add('return $from $toExclusive');
    return LkVatReturn.fromJson({
      'from': from,
      'to_exclusive': toExclusive,
      'entity_tin': '114000001',
      'lines': [
        {
          'line': 'standard_rated_supply',
          'value': '1000000.000000',
          'tax': '180000.000000',
        },
      ],
      'output_tax': '180000.000000',
      'input_tax_claimable': '72000.000000',
      'net_payable': '108000.000000',
      'blockers': [
        {
          'reason': 'VAT_MAPPING_REQUIRED',
          'document_number': 'BILL-3',
          'tax_code': 'IN18',
        },
      ],
      'output_schedule': [
        {
          'line': 'standard_rated_supply',
          'source_type': 'sales_invoice',
          'posting_date': '2026-05-10',
          'document_number': 'INV-1',
          'counterparty_name': 'Lanka Traders',
          'counterparty_tin': '114567890',
          'tax_code': 'VAT18',
          'value': '1000000.000000',
          'tax': '180000.000000',
        },
      ],
      'input_schedule': const [],
    });
  }
}

Future<(FakeTax, FakeFiles)> pump(
  WidgetTester tester, {
  Set<String> permissions = const {
    'finance.view',
    'finance.reports.export',
    'finance.classifications.approve',
  },
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeTax(), files = FakeFiles();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LkTaxWorkspace(
          scope: scope,
          permissions: permissions,
          repository: fake,
          files: files,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, files);
}

void main() {
  testWidgets(
    'SSCL settings are proposed, approved with confirmation and used',
    (tester) async {
      final (fake, files) = await pump(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Liable portion %'),
        '50',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Business activity'),
        'Wholesale and retail',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason for the SSCL settings'),
        'SSCL at 2.5%',
      );
      await tester.tap(find.text('Propose SSCL settings'));
      await tester.pumpAndSettle();
      expect(fake.calls, [
        'sscl propose 2026-04-01 2027-04-01 2.5 50 Wholesale and retail',
      ]);
      await tester.tap(find.text('Approve SSCL'));
      await tester.pumpAndSettle();
      final approve = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Approve'),
      );
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'sscl approve');
      await tester.enterText(
        find.widgetWithText(TextField, 'Quarter start (YYYY-MM)'),
        '2026-05',
      );
      await tester.tap(find.text('Prepare SSCL workpaper'));
      await tester.pumpAndSettle();
      expect(find.textContaining('YYYY-01, YYYY-04'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Quarter start (YYYY-MM)'),
        '2026-04',
      );
      await tester.tap(find.text('Prepare SSCL workpaper'));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'sscl return 2026-04-01');
      expect(
        find.text('Liable turnover Rs 2800000.00 · SSCL due Rs 70000.00'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save SSCL CSV'));
      await tester.pumpAndSettle();
      final bytes = files.written[r'C:\tax\sscl-workpaper-2026-04.csv']!;
      expect(
        utf8.decode(bytes.skip(3).toList()),
        contains('Result,SSCL due,70000.00'),
      );
    },
  );

  testWidgets(
    'only suitable VAT lines are offered and proposing calls the server',
    (tester) async {
      final (fake, _) = await pump(tester);
      expect(find.text('Not mapped'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'Standard-rated supplies'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ChoiceChip, 'Input tax claimable'),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason for new mappings'),
        'Standard rate',
      );
      await tester.tap(
        find.widgetWithText(ChoiceChip, 'Standard-rated supplies'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propose'));
      await tester.pumpAndSettle();
      expect(fake.calls, [
        'propose $vat18 standard_rated_supply Standard rate',
      ]);
      expect(
        find.textContaining('Pending: Standard-rated supplies'),
        findsOneWidget,
      );
    },
  );

  testWidgets('approval needs the guidance confirmation', (tester) async {
    final (fake, _) = await pump(tester);
    fake.pending = true;
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    final approve = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Approve'),
    );
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(fake.calls, ['approve $mappingId']);
    expect(find.text('VAT18 mapping approved.'), findsOneWidget);
  });

  testWidgets('a quarterly workpaper shows the position and saves CSV', (
    tester,
  ) async {
    final (fake, files) = await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'First month (YYYY-MM)'),
      '2026-04',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quarter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare workpaper'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['return 2026-04-01 2026-07-01']);
    expect(find.text('Net payable Rs 108000.00'), findsOneWidget);
    expect(find.textContaining('1 lines need attention'), findsOneWidget);
    await tester.tap(find.text('Save CSV'));
    await tester.pumpAndSettle();
    final bytes = files.written[r'C:\tax\vat-workpaper-2026-04.csv']!;
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(
      utf8.decode(bytes.skip(3).toList()),
      contains('INV-1,Lanka Traders,114567890'),
    );
  });

  testWidgets('the workpaper is hidden without report export', (tester) async {
    await pump(tester, permissions: const {'finance.view'});
    expect(find.text('VAT workpaper'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
  });
}
