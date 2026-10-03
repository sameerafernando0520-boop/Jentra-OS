import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_controller.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_screen.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_controller.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_screen.dart';

import 'manual_journal_workspace_test.dart' show JournalGateway, journal;
import 'period_fx_workspace_test.dart' show PeriodFxFake;
import 'support/procurement_fakes.dart' show Keys;

const scope = TenantContext(
  tenantId: 't',
  actorId: 'a',
  legalEntityId: 'e',
  branchId: 'b',
);

class Choices extends JournalGateway {
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
    String? documentDate,
  }) async => resource == 'accounts'
      ? {
          'items': [
            {
              'id': 'private-account',
              'code': '5109',
              'name': 'Private account evidence',
            },
          ],
        }
      : await super.options(
          scope,
          resource,
          after: after,
          search: search,
          documentDate: documentDate,
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late Choices gateway;
  late PeriodFxFake fx;
  late ManualJournalController manual;
  late PeriodFxController period;
  var manualDisposed = false, periodDisposed = false;
  setUp(() {
    manualDisposed = periodDisposed = false;
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = Choices();
    fx = PeriodFxFake();
    manual = ManualJournalController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
      permissions: {'finance.view', 'finance.journals.post'},
    );
    period = PeriodFxController(
      scope: scope,
      gateway: fx,
      drafts: drafts,
      online: true,
      capabilities: {'finance.view', 'finance.period.close'},
    );
  });
  tearDown(() async {
    if (!manualDisposed) manual.dispose();
    if (!periodDisposed) period.dispose();
    await db.close();
  });

  Future<void> render(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> changeManual(WidgetTester tester, String kind) async {
    if (kind == 'dispose') {
      manual.dispose();
      manualDisposed = true;
    } else if (kind == 'denial') {
      manual.denyReadAccess();
    } else {
      manual.setOnline(false);
      if (kind == 'reconnect') manual.setOnline(true);
    }
    await tester.pumpAndSettle();
    if (kind == 'reconnect' || kind == 'denial') {
      await tester.runAsync(manual.refresh);
      await tester.pumpAndSettle();
    }
  }

  Future<void> changePeriod(WidgetTester tester, String kind) async {
    if (kind == 'dispose') {
      period.dispose();
      periodDisposed = true;
    } else if (kind == 'denial') {
      fx.readFailure = 'PERMISSION_DENIED';
      await tester.runAsync(period.refresh);
      fx.readFailure = null;
    } else {
      period.setOnline(false);
      if (kind == 'reconnect') period.setOnline(true);
    }
    await tester.pumpAndSettle();
    if (kind == 'reconnect' || kind == 'denial') {
      await tester.runAsync(period.refresh);
      await tester.pumpAndSettle();
    }
  }

  for (final kind in ['disconnect', 'reconnect', 'denial', 'dispose']) {
    testWidgets('journal picker hides loaded rows after $kind', (tester) async {
      await tester.runAsync(() async {
        await manual.initialize();
        manual.form = journal();
      });
      await render(tester, ManualJournalWorkspace(controller: manual));
      await tester.tap(find.text('Add account line'));
      await tester.pumpAndSettle();
      expect(find.text('5109 · Private account evidence'), findsOneWidget);
      await changeManual(tester, kind);
      expect(find.text('5109 · Private account evidence'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(gateway.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('journal confirmation cannot survive $kind', (tester) async {
      await tester.runAsync(() async {
        await manual.initialize();
        manual.form = journal(status: 'approved', version: 3);
      });
      await render(tester, ManualJournalWorkspace(controller: manual));
      await tester.ensureVisible(find.text('Post journal'));
      await tester.tap(find.text('Post journal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Post 123.456789 LKR'), findsOneWidget);
      await changeManual(tester, kind);
      expect(find.textContaining('Post 123.456789 LKR'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(gateway.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('period confirmation cannot survive $kind', (tester) async {
      await tester.runAsync(() async {
        await period.initialize();
        await period.selectPeriod('period');
        period.field('reason', 'Original scoped close');
        await period.save();
      });
      await render(tester, PeriodFxWorkspace(controller: period));
      await tester.tap(find.text('Soft lock'));
      await tester.pumpAndSettle();
      expect(find.text('Soft lock this period?'), findsOneWidget);
      await changePeriod(tester, kind);
      expect(find.text('Soft lock this period?'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(fx.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
