import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/journal_evidence/posted_journal_controller.dart';
import 'package:jentra_desktop/src/features/journal_evidence/posted_journal_screen.dart';

Map<String, Object?> journalResponse({int count = 2, int after = 0}) => {
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'branch_id': 'b',
  'journal_id': 'j',
  'after_line': after,
  'journal': {
    'id': 'j',
    'tenant_id': 't',
    'legal_entity_id': 'e',
    'branch_id': 'source-b',
    'branch_name': 'Historical branch',
    'branch_status': 'inactive',
    'document_number': 'J-001',
    'posting_date': '2026-09-20',
    'fiscal_period_id': 'p',
    'status': 'posted',
    'currency_code': 'USD',
    'base_currency_code': 'LKR',
    'exchange_rate': '1.2345678912',
    'rule_version': 1,
    'source_type': 'manual_journal',
    'source_id': 'source',
    'command_id': 'command',
    'request_id': 'request',
    'correlation_id': 'correlation',
    'created_by': 'actor',
    'created_at': '2026-09-20T00:00:00Z',
    'base_debit': '900719925474.099999',
    'base_credit': '900719925474.099999',
    'transaction_debit': '123.456789',
    'transaction_credit': '123.456789',
    'line_count': count,
    'label_basis': 'current_catalogue',
    'stock_cost_access_required': false,
  },
  'items': [
    for (var i = after + 1; i <= count && i <= after + 50; i++)
      {
        'id': 'line-$i',
        'tenant_id': 't',
        'legal_entity_id': 'e',
        'branch_id': 'source-b',
        'journal_entry_id': 'j',
        'line_number': i,
        'account_id': 'account-$i',
        'account_code': '100$i',
        'account_name': 'Accrued freight',
        'account_status': 'retired',
        'currency_code': 'USD',
        'posting_date': '2026-09-20',
        'party_id': null,
        'source_line_id': 'source-line-$i',
        'base_debit': i.isOdd
            ? (count == 2 ? '900719925474.099999' : '0.000001')
            : '0.000000',
        'base_credit': i.isEven
            ? (count == 2 ? '900719925474.099999' : '0.000001')
            : '0.000000',
        'transaction_debit': i.isOdd ? '123.456789' : '0.000000',
        'transaction_credit': i.isEven ? '123.456789' : '0.000000',
        'cost_centre_id': null,
        'project_id': null,
        'dimension_snapshot': null,
      },
  ],
  'next_cursor': count > after + 50 ? after + 50 : null,
};

class JournalFake implements PostedJournalGateway {
  final cursors = <int>[];
  Completer<Map<String, Object?>>? held;
  Object? failure;
  int count = 2;
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id, {
    int afterLine = 0,
  }) async {
    cursors.add(afterLine);
    if (held != null) return held!.future;
    if (failure != null) throw failure!;
    return journalResponse(count: count, after: afterLine);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'actor',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const target = (tenantId: 't', entityId: 'e', branchId: 'b', journalId: 'j');
  late JournalFake gateway;
  late PostedJournalController c;
  bool disposed = false;
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  setUp(() {
    disposed = false;
    gateway = JournalFake();
    c = PostedJournalController(
      scope: scope,
      gateway: gateway,
      target: target,
      online: true,
    );
  });
  tearDown(() {
    if (!disposed) c.dispose();
  });

  test(
    'paging keeps only the current fifty rows with reversible cursors',
    () async {
      gateway.count = 102;
      await c.refresh();
      expect(c.rows.length, 50);
      await c.next();
      expect(c.rows.length, 50);
      expect(c.rows.first['line_number'], 51);
      await c.next();
      expect(c.rows.length, 2);
      expect(c.nextCursor, isNull);
      await c.previous();
      expect(c.rows.first['line_number'], 51);
      await c.previous();
      expect(c.rows.first['line_number'], 1);
      expect(gateway.cursors, [0, 50, 100, 50, 0]);
    },
  );
  test(
    'revoked permission and MFA clear previous evidence and paging',
    () async {
      for (final code in ['PERMISSION_DENIED', 'MFA_REQUIRED']) {
        gateway.failure = null;
        await c.refresh();
        expect(c.verified, isTrue);
        gateway.failure = DomainError(code: code, message: 'Access changed');
        await c.refresh();
        expect(c.verified, isFalse);
        expect(c.journal, isEmpty);
        expect(c.rows, isEmpty);
        expect(c.previousPages, isEmpty);
      }
    },
  );
  test(
    'failed refresh clears stale money and cannot retry a page with old access',
    () async {
      await c.refresh();
      gateway.failure = Exception('transport');
      await c.refresh();
      expect(c.rows, isEmpty);
      expect(c.journal, isEmpty);
      await c.next();
      expect(gateway.cursors, [0, 0]);
    },
  );
  test('disconnect clears evidence before late read success', () async {
    await c.refresh();
    final held = gateway.held = Completer();
    final reading = c.refresh();
    c.setOnline(false);
    expect(c.journal, isEmpty);
    expect(c.rows, isEmpty);
    held.complete(journalResponse());
    await reading;
    expect(c.verified, isFalse);
    expect(c.rows, isEmpty);
  });
  test('obsolete failure cannot erase a later reconnect success', () async {
    final held = gateway.held = Completer();
    final old = c.refresh();
    c.setOnline(false);
    c.setOnline(true);
    gateway.held = null;
    await c.refresh();
    expect(c.verified, isTrue);
    held.completeError(
      const DomainError(code: 'PERMISSION_DENIED', message: 'old denial'),
    );
    await old;
    expect(c.verified, isTrue);
    expect(c.error, isNull);
  });
  test('disposal suppresses late evidence and listener updates', () async {
    final held = gateway.held = Completer();
    final reading = c.refresh();
    c.dispose();
    disposed = true;
    held.complete(journalResponse());
    await reading;
    expect(c.journal, isEmpty);
    expect(c.verified, isFalse);
  });
  test('wrong tenant, entity or branch destination sends no read', () async {
    for (final destination in [
      (tenantId: 'other', entityId: 'e', branchId: 'b', journalId: 'j'),
      (tenantId: 't', entityId: 'other', branchId: 'b', journalId: 'j'),
      (tenantId: 't', entityId: 'e', branchId: 'other', journalId: 'j'),
    ]) {
      final wrong = PostedJournalController(
        scope: scope,
        gateway: gateway,
        target: destination,
        online: true,
      );
      await wrong.refresh();
      expect(wrong.verified, isFalse);
      expect(wrong.error, contains('unavailable'));
      wrong.dispose();
    }
    expect(gateway.cursors, isEmpty);
  });
  test('offline open waits for an explicit fresh permission read', () async {
    c.setOnline(false);
    await c.refresh();
    expect(gateway.cursors, isEmpty);
    c.setOnline(true);
    expect(c.verified, isFalse);
    await c.refresh();
    expect(c.verified, isTrue);
  });
  testWidgets('journal link binds original context and exact identity', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: PostedJournalLink(scope: scope, journalId: 'j'),
          ),
        ),
        GoRoute(
          path: '/finance/journal-evidence',
          builder: (_, s) => Scaffold(body: Text(s.uri.query)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open posted journal'));
    await tester.pumpAndSettle();
    expect(find.text('tenant=t&entity=e&branch=b&journal=j'), findsOneWidget);
  });
  testWidgets('disabled link has no navigation action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostedJournalLink(scope: scope, journalId: 'j', enabled: false),
        ),
      ),
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });
  for (final dark in [false, true]) {
    testWidgets('journal evidence ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      await c.refresh();
      c.rows.first['dimension_snapshot'] = {
        'cost_centre': {
          'id': 'centre-id',
          'code': 'CC-DIST',
          'name': 'Original distribution centre',
          'version': 1,
        },
      };
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const Key('journal-golden'),
            child: Scaffold(body: PostedJournalWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('journal-golden')),
        matchesGoldenFile(
          'goldens/journal_evidence_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      await tester.scrollUntilVisible(
        find.text('1. 1001 · Accrued freight'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('1. 1001 · Accrued freight'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('journal-golden')),
        matchesGoldenFile(
          'goldens/journal_lines_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      expect(find.textContaining('900719925474.099999'), findsWidgets);
    });
  }
}
