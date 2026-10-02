import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_desktop/src/features/receivables/receivable_statement.dart';

import 'receivables_controller_test.dart' as f;

class StatementFake extends f.FakeReceivables {
  Completer<void>? statementPause, pagePause, referencePause, sourcePause;
  final entered = Completer<void>();
  int statementCalls = 0, allocationPages = 0;
  Object? readFailure;
  Future<void> pause(Completer<void>? hold) async {
    if (hold != null) {
      if (!entered.isCompleted) entered.complete();
      await hold.future;
    }
    if (readFailure != null) throw readFailure!;
  }

  @override
  Future<CursorPage<ReceivableDocument>> page(
    TenantContext scope,
    ReceivableKind kind, {
    String? cursor,
    String? status,
  }) async {
    await pause(pagePause);
    return super.page(scope, kind, cursor: cursor, status: status);
  }

  @override
  Future<ReceivableDocument> find(
    TenantContext scope,
    ReceivableKind kind,
    String id,
  ) async {
    await pause(sourcePause);
    return super.find(scope, kind, id);
  }

  @override
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext scope,
    String resource, {
    String? cursor,
    String? customerId,
    String? sourceId,
  }) async {
    await pause(referencePause);
    if (resource == 'parties') {
      return CursorPage(
        items: [
          {
            'id': '00000000-0000-4000-8000-000000000003',
            'code': 'CUS-1',
            'legal_name': 'Historical customer',
          },
        ],
        limit: 50,
      );
    }
    if (resource == 'open_item_allocations') {
      allocationPages++;
      return CursorPage(
        items: [
          {
            'posting_date': cursor == null ? '2026-09-20' : '2026-09-21',
            'transaction_amount': cursor == null ? '0.000001' : '2.000001',
            'source_open_item_id': 'receipt',
            'target_open_item_id': 'invoice',
            'exchange_difference': '0.000000',
            'discount_amount': '0.000000',
            'write_off': '0.000000',
            'reason': 'Linked historical settlement',
          },
        ],
        limit: 50,
        nextCursor: cursor == null ? 'next' : null,
      );
    }
    return super.references(
      scope,
      resource,
      cursor: cursor,
      customerId: customerId,
      sourceId: sourceId,
    );
  }

  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope,
    String customer,
    String currency,
    String asOf,
    List<int> buckets,
  ) async {
    statementCalls++;
    await pause(statementPause);
    return {
      'open_amount': '90071992547409.123456',
      'open_base_amount': '90071992547409.123456',
      'bucket_days': buckets,
      'aging': [
        {'bucket': -1, 'amount': '-0.000001'},
        {'bucket': 0, 'amount': '0.000001'},
        {'bucket': 1, 'amount': '2.000001'},
        {'bucket': 2, 'amount': '3.000001'},
        {'bucket': buckets.length + 1, 'amount': '4.000001'},
      ],
      'rows': [
        {
          'id': 'item',
          'document_number': 'INV-HIST',
          'source_type': 'sales_invoice',
          'source_id': doc.id,
          'posting_date': '2026-09-20',
          'due_date': '2026-09-25',
          'original_amount': '90071992547409.123456',
          'open_amount': '0.000001',
          'open_base_amount': '0.000001',
        },
      ],
    };
  }
}

void main() {
  late JentraLocalDatabase db;
  late StatementFake repo;
  late ReceivablesController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repo = StatementFake();
    c = ReceivablesController(
      scope: f.scope,
      capabilities: f.permissions,
      repository: repo,
      drafts: ReceivableDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: f.MemoryKeys())),
      ),
      online: true,
    );
  });
  tearDown(() async {
    if (c.active) c.dispose();
    await db.close();
  });
  test('late register read cannot restore evidence after disconnect', () async {
    repo.pagePause = Completer<void>();
    final work = c.refresh();
    await repo.entered.future;
    c.setOnline(false);
    repo.pagePause!.complete();
    await work;
    expect(c.page.items, isEmpty);
    expect(c.document, isNull);
  });
  test('late document read cannot restore evidence after reconnect', () async {
    repo.sourcePause = Completer<void>();
    final work = c.open(repo.doc);
    await repo.entered.future;
    c.setOnline(false);
    c.setOnline(true);
    repo.sourcePause!.complete();
    await work;
    expect(c.document, isNull);
    expect(c.page.items, isEmpty);
  });
  test('posting receipt resolves original retry while offline without optional register read', () async {
    repo.doc = ReceivableDocument(f.snapshot(status: 'approved'));
    await c.open(repo.doc);
    repo.gate = Completer<void>();
    final work = c.action('post');
    while (repo.commands.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final slot = c.slot!;
    c.setOnline(false);
    repo.gate!.complete();
    await work;
    expect(c.pending, isFalse);
    expect(c.document, isNull);
    expect(c.page.items, isEmpty);
    expect(await c.drafts.load(c.scope, slot), isNull);
    expect(c.message, startsWith('Confirmed'));
    expect(repo.commands, hasLength(1));
  });
  Future<void> pumpStatement(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReceivableStatement(controller: c),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.text('Choose customer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUS-1 · Historical customer'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'exact statement aging and historical source/allocation pages remain accessible',
    (tester) async {
      await pumpStatement(tester);
      await choose(tester);
      await tester.tap(find.text('Run statement'));
      await tester.pumpAndSettle();
      expect(find.textContaining('90071992547409.123456 open'), findsOneWidget);
      expect(find.text('Unapplied credits · -0.000001'), findsOneWidget);
      expect(find.text('> 90 days · 4.000001'), findsOneWidget);
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(find.text('INV-0001'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allocations'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-20 · 0.000001'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-21 · 2.000001'), findsOneWidget);
      expect(repo.allocationPages, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('disconnect clears displayed statement and source selection', (
    tester,
  ) async {
    await pumpStatement(tester);
    await choose(tester);
    await tester.tap(find.text('Run statement'));
    await tester.pumpAndSettle();
    expect(find.textContaining('90071992547409.123456 open'), findsOneWidget);
    c.setOnline(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('90071992547409.123456'), findsNothing);
    expect(find.text('Choose customer'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Run statement'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('late statement after disconnect never restores amounts', (
    tester,
  ) async {
    await pumpStatement(tester);
    await choose(tester);
    repo.statementPause = Completer<void>();
    await tester.tap(find.text('Run statement'));
    await tester.pump();
    c.setOnline(false);
    repo.statementPause!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('90071992547409.123456'), findsNothing);
    expect(find.text('Source'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'offline root picker hides choices and does not revive them on reconnect',
    (tester) async {
      await pumpStatement(tester);
      await tester.tap(find.text('Choose customer').first);
      await tester.pumpAndSettle();
      expect(find.text('CUS-1 · Historical customer'), findsOneWidget);
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.text('CUS-1 · Historical customer'), findsNothing);
      expect(find.text('Connect to recheck access'), findsOneWidget);
      c.setOnline(true);
      await tester.pumpAndSettle();
      expect(find.text('CUS-1 · Historical customer'), findsNothing);
      expect(find.text('Business scope changed'), findsOneWidget);
    },
  );
  testWidgets('invalid dates and aging buckets never issue statement reads', (
    tester,
  ) async {
    await pumpStatement(tester);
    await tester.tap(find.text('Run statement'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a customer and valid as-of date.'),
      findsOneWidget,
    );
    await choose(tester);
    await tester.enterText(find.byType(TextFormField).at(2), '60,30');
    await tester.tap(find.text('Run statement'));
    await tester.pumpAndSettle();
    expect(find.text('Enter increasing positive bucket days.'), findsOneWidget);
    expect(repo.statementCalls, 0);
    await tester.enterText(find.byType(TextFormField).at(1), '2026-02-30');
    await tester.tap(find.text('Run statement'));
    await tester.pumpAndSettle();
    expect(repo.statementCalls, 0);
  });
  testWidgets('unknown read failure does not print raw transport text', (
    tester,
  ) async {
    await pumpStatement(tester);
    await choose(tester);
    repo.readFailure = StateError('SECRET bank data');
    await tester.tap(find.text('Run statement'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SECRET'), findsNothing);
    expect(
      find.text('Evidence could not be verified. Retry when connected.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'definite statement denial clears source evidence and exposes a fixed access state',
    (tester) async {
      await pumpStatement(tester);
      await choose(tester);
      repo.readFailure = const ReceivableFailure(
        'PERMISSION_DENIED',
        'Untrusted private server text',
      );
      await tester.tap(find.text('Run statement'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Untrusted private'), findsNothing);
      expect(
        find.text(
          'Evidence is unavailable with your current access. Recheck your role and scope.',
        ),
        findsOneWidget,
      );
      expect(find.text('Source'), findsNothing);
      expect(find.text('Choose customer'), findsOneWidget);
    },
  );
}
