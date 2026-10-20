import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_format.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_widgets.dart';
import 'package:jentra_domain/jentra_assurance.dart';

void main() {
  Future<void> pump(WidgetTester t, Widget child) => t.pumpWidget(
    MaterialApp(
      theme: JentraTheme.light(),
      home: Scaffold(body: ListView(children: [child])),
    ),
  );

  group('AuditDateField', () {
    Widget field(
      ValueNotifier<String?> value, {
      bool enabled = true,
      String? firstDate,
    }) => ValueListenableBuilder(
      valueListenable: value,
      builder: (_, v, _) => AuditDateField(
        label: 'Remediation due',
        value: v,
        enabled: enabled,
        firstDate: firstDate,
        onChanged: (iso) => value.value = iso,
      ),
    );

    testWidgets('shows the date in words and stores the picked civil date', (
      t,
    ) async {
      final value = ValueNotifier<String?>('2026-11-16');
      await pump(t, field(value));
      expect(find.text('16 Nov 2026'), findsOneWidget);
      expect(find.textContaining('YYYY'), findsNothing);
      expect(
        find.bySemanticsLabel('Remediation due, 16 Nov 2026'),
        findsOneWidget,
      );
      await t.tap(find.text('16 Nov 2026'));
      await t.pumpAndSettle();
      await t.tap(find.text('20'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(value.value, '2026-11-20');
      expect(find.text('20 Nov 2026'), findsOneWidget);
    });

    testWidgets('opens from the keyboard', (t) async {
      final value = ValueNotifier<String?>('2026-11-16');
      await pump(t, field(value));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(value.value, '2026-11-16');
    });

    testWidgets('an empty date says so and a locked one does not open', (
      t,
    ) async {
      final value = ValueNotifier<String?>('');
      await pump(t, field(value, enabled: false));
      expect(find.text('Not set'), findsOneWidget);
      await t.tap(find.text('Not set'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('nothing before the first date is offered', (t) async {
      final value = ValueNotifier<String?>('2026-03-01');
      await pump(t, field(value, firstDate: '2026-04-01'));
      await t.tap(find.text('1 Mar 2026'));
      await t.pumpAndSettle();
      final picker = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2026, 4, 1));
      expect(picker.initialDate, DateTime(2026, 4, 1));
    });
  });

  testWidgets('every audit screen header has a refresh button and sections', (
    t,
  ) async {
    var refreshed = 0;
    String? chosen;
    await pump(
      t,
      AuditScreenHeader(
        title: 'Audit planning',
        description: 'The audit universe and plans.',
        onRefresh: () => refreshed++,
        sections: const [('universe', 'Audit universe'), ('plans', 'Plans')],
        selected: 'universe',
        onSelect: (k) => chosen = k,
      ),
    );
    expect(find.text('Audit planning'), findsOneWidget);
    expect(find.text('The audit universe and plans.'), findsOneWidget);
    await t.tap(find.byTooltip('Refresh'));
    expect(refreshed, 1);
    expect(
      t
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Audit universe'))
          .selected,
      isTrue,
    );
    await t.tap(find.text('Plans'));
    expect(chosen, 'plans');
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.header ?? false),
      ),
      findsOneWidget,
    );
  });

  test('statuses carry one tone everywhere', () {
    expect(auditTone(FindingStatus.closed), JentraStatusTone.success);
    expect(auditTone(FindingStatus.issued), JentraStatusTone.warning);
    expect(auditTone(FindingStatus.remediating), JentraStatusTone.info);
    expect(auditTone(EvidenceRequestStatus.accepted), JentraStatusTone.success);
    expect(auditTone(ExceptionStatus.candidate), JentraStatusTone.warning);
    expect(auditTone(PlanStatus.approved), JentraStatusTone.success);
    expect(auditTone(PlanStatus.draft), JentraStatusTone.neutral);
    expect(auditTone(EngagementStatus.fieldwork), JentraStatusTone.info);
    expect(auditTone(AssuranceSeverity.critical), JentraStatusTone.danger);
    expect(auditTone(AssuranceSeverity.high), JentraStatusTone.warning);
    expect(auditTone(AssuranceSeverity.low), JentraStatusTone.neutral);
    expect(auditTone(TestProcedureStatus.reviewed), JentraStatusTone.success);
  });

  testWidgets('a status badge reads in words', (t) async {
    await pump(t, auditBadge(FindingStatus.riskAccepted));
    expect(find.text('Risk accepted'), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Risk accepted'), findsOneWidget);
  });

  testWidgets('an item panel shows title, status, details and actions', (
    t,
  ) async {
    var acted = 0;
    await pump(
      t,
      AuditItemPanel(
        title: 'TRS-SIGN · Bank signatories',
        badges: [auditBadge(EvidenceRequestStatus.submitted)],
        details: const ['due 25 Oct 2026', 'Signed bank letter.pdf'],
        digest: 'a' * 64,
        actions: [
          TextButton(onPressed: () => acted++, child: const Text('Review')),
        ],
      ),
    );
    expect(find.text('TRS-SIGN · Bank signatories'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(
      find.text('due 25 Oct 2026 · Signed bank letter.pdf'),
      findsOneWidget,
    );
    expect(find.text('SHA-256 aaaaaaaaaaaa…'), findsOneWidget);
    await t.tap(find.text('Review'));
    expect(acted, 1);
    expect(find.byType(JentraPanel), findsOneWidget);
  });

  testWidgets('an openable panel is one keyboard-reachable button', (t) async {
    var opened = 0;
    await pump(
      t,
      AuditItemPanel(
        title: 'FY27 Treasury',
        badges: [auditBadge(EngagementStatus.fieldwork)],
        details: const ['1 Apr 2026 → 31 Mar 2027'],
        onOpen: () => opened++,
        openLabel: 'Open FY27 Treasury',
      ),
    );
    await t.tap(find.text('FY27 Treasury'));
    expect(opened, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(opened, 2);
    expect(
      find.bySemanticsLabel(RegExp('^Open FY27 Treasury')),
      findsOneWidget,
    );
  });

  testWidgets('a notice wraps long text instead of cutting it', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    const long =
        'Offline — a saved response draft and any sealed request are retained. Reconnect and refresh access to read audit work.';
    await pump(t, const AuditNotice(long, tone: JentraStatusTone.warning));
    expect(t.takeException(), isNull);
    final text = t.widget<Text>(find.text(long));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  test('a picked date is stored as the civil ISO date', () {
    expect(auditIsoDate(DateTime(2026, 4, 1)), '2026-04-01');
    expect(auditIsoDate(DateTime(2027, 12, 31, 23, 59)), '2027-12-31');
  });
}
