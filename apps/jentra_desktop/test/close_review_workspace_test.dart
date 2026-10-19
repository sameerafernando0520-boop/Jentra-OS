import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/close_review/close_review_controller.dart';
import 'package:jentra_desktop/src/features/close_review/close_review_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> review(String id) => {
  'id': id,
  'entity_name': 'Jentra Trading',
  'scope': 'all_entity_branches',
  'status': 'blocked',
  'period_id': 'period',
  'period_name': 'September 2026',
  'period_state': 'open',
  'period_version': 2,
  'as_of': '2026-09-25',
  'branch_count': 2,
  'control_count': 4,
  'difference_count': 1,
  'blocker_count': 2,
  'currency_code': 'LKR',
  'generated_at': '2026-09-26 14:00 UTC',
};

class ReviewGateway implements CloseReviewGateway {
  String? failure, readFailure;
  bool failEvidence = false;
  Completer<void>? generationPause, pagePause, reportsPause;
  final generationEntered = Completer<void>(),
      pageEntered = Completer<void>(),
      reportsEntered = Completer<void>();
  final commands = <CommandEnvelope<Map<String, Object?>>>[],
      reads = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> reports(TenantContext s, {String? after}) async {
    if (!reportsEntered.isCompleted) reportsEntered.complete();
    await reportsPause?.future;
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Access needs rechecking');
    }
    return {
      'items': [review('old-review')],
    };
  }

  @override
  Future<Map<String, Object?>> periods(
    TenantContext s, {
    String? after,
  }) async => {
    'items': [
      {
        'id': 'period',
        'name': 'September 2026',
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
        'version': 2,
      },
    ],
  };
  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (!generationEntered.isCompleted) generationEntered.complete();
    await generationPause?.future;
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Review outcome needs retry');
    }
    if (failEvidence) readFailure = 'READ_FAILED';
    return review(c.payload['id'] as String);
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext s,
    String id,
    String section, {
    String? after,
    String? componentKey,
  }) async {
    if (!pageEntered.isCompleted) pageEntered.complete();
    await pagePause?.future;
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Access needs rechecking');
    }
    reads.add({
      'id': id,
      'section': section,
      'component': componentKey,
      'after': after,
    });
    return {
      'summary': review(id),
      'section': section,
      'component_key': componentKey,
      'items': [
        if (section == 'controls')
          {
            'id': 'GRNI:b',
            'component_key': 'GRNI:b',
            'kind': 'GRNI',
            'name': 'GRNI · Colombo',
            'status': 'difference',
            'currency_code': 'LKR',
            'subledger_value': '9007199254.740993',
            'gl_value': '9007199254.740990',
            'difference': '0.000003',
            'difference_count': 1,
            'accounts': [
              {
                'id': 'original-control',
                'code': '2300',
                'name': 'Original GRNI control',
              },
            ],
          },
        if (section == 'sources')
          {
            'id': 'bill-source',
            'component_key': 'GRNI:b',
            'origin': 'journal',
            'source_type': 'supplier_bill',
            'source_id': 'bill-0042',
            'journal_id': 'journal-0042',
            'command_id': 'command-0042',
            'receipt_id': 'receipt-0042',
            'value': '-0.730000',
            'posting_date': '2026-09-24',
          },
        if (section == 'blockers')
          {
            'id': 'issue-1',
            'code': 'GRNI_CONTROL_DIFFERENCE',
            'branch_id': 'Colombo',
            'count': 1,
            'difference': '0.000003',
          },
      ],
      'next_cursor': after == null ? '50' : null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late ReviewGateway gateway;
  late CloseReviewController c;
  var disposed = false;
  CloseReviewController make({TenantContext context = scope}) =>
      CloseReviewController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
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
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = ReviewGateway();
    c = make();
  });
  tearDown(() async {
    if (!disposed) c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    c.form = {...c.form, 'id': 'review-0042'};
    c.field('period_id', 'period');
    c.field('as_of', '2026-09-25');
  }

  test('navigation requires all four control and cost capabilities', () {
    expect(
      visibleJentraDestinations({'finance.view', 'finance.controls.reconcile'})
          .any((d) => d.path == '/finance/close-review'),
      isFalse,
    );
    expect(
      visibleJentraDestinations(
        CloseReviewController.requiredCapabilities.toSet(),
      ).any((d) => d.path == '/finance/close-review'),
      isTrue,
    );
  });
  test('generation seals entity cutoff and persists confirmed identity before evidence', () async {
    await ready();
    await c.generate();
    expect(c.error, isNull);
    expect(gateway.commands.single.payload, {
      'id': 'review-0042',
      'period_id': 'period',
      'as_of': '2026-09-25',
    });
    final local = await drafts.load(scope, CloseReviewController.slot);
    expect(local!.pending, isNull);
    expect(local.form['report_id'], 'review-0042');
  });
  test('invalid cutoff cannot create or send authoritative request', () async {
    await ready();
    c.field('as_of', '2026-08-31');
    await c.generate();
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('within it'));
  });
  test('uncertain retry preserves exact immutable command envelope', () async {
    await ready();
    gateway.failure = 'UNCERTAIN_RESULT';
    await c.generate();
    expect(c.pending, isTrue);
    c.field('as_of', '2026-09-24');
    expect(c.form['as_of'], '2026-09-25');
    gateway.failure = null;
    await c.generate();
    expect(gateway.commands.first.commandId, gateway.commands.last.commandId);
    expect(c.pending, isFalse);
  });
  test(
    'confirmed review survives optional evidence failure and can reopen',
    () async {
      await ready();
      gateway.failEvidence = true;
      await c.generate();
      expect(c.form['status'], 'confirmed');
      expect(c.pending, isFalse);
      expect(c.error, contains('Review confirmed'));
      gateway.readFailure = null;
      await c.initialize();
      expect(c.summary['id'], 'review-0042');
    },
  );
  test(
    'offline clears evidence and requires fresh access before generating',
    () async {
      await ready();
      await c.generate();
      c.setOnline(false);
      expect(c.summary, isEmpty);
      expect(c.reports, isEmpty);
      expect(c.periods, isEmpty);
      c.setOnline(true);
      expect(c.verified, isFalse);
      await c.initialize();
      expect(c.summary['id'], 'review-0042');
    },
  );
  test(
    'delayed page cannot restore evidence across disconnect and reconnect',
    () async {
      await ready();
      await c.generate();
      gateway.pagePause = Completer<void>();
      final task = c.select('sources', key: 'GRNI:b');
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      c.setOnline(true);
      gateway.pagePause!.complete();
      await task;
      expect(c.summary, isEmpty);
      expect(c.rows, isEmpty);
      expect(c.verified, isFalse);
    },
  );
  test('delayed access list cannot repopulate revoked offline state', () async {
    gateway.reportsPause = Completer<void>();
    final task = c.initialize();
    await gateway.reportsEntered.future;
    c.setOnline(false);
    c.setOnline(true);
    gateway.reportsPause!.complete();
    await task;
    expect(c.reports, isEmpty);
    expect(c.verified, isFalse);
  });
  test(
    'offline acknowledgement is persisted without exposing stale evidence',
    () async {
      await ready();
      gateway.generationPause = Completer<void>();
      final task = c.generate();
      await gateway.generationEntered.future;
      c.setOnline(false);
      gateway.generationPause!.complete();
      await task;
      expect(
        (await drafts.load(
          scope,
          CloseReviewController.slot,
        ))!.form['report_id'],
        'review-0042',
      );
      expect(c.summary, isEmpty);
    },
  );
  test(
    'disposed route still atomically confirms encrypted report identity',
    () async {
      await ready();
      gateway.generationPause = Completer<void>();
      final task = c.generate();
      await gateway.generationEntered.future;
      c.dispose();
      disposed = true;
      gateway.generationPause!.complete();
      await task;
      final local = await drafts.load(scope, CloseReviewController.slot);
      expect(local!.pending, isNull);
      expect(local.form['report_id'], 'review-0042');
    },
  );
  test(
    'failed encrypted confirmation retains exact request for safe retry',
    () async {
      await ready();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.generate();
      gateway.failure = null;
      await db.customStatement(
        "create trigger fail_review_confirmation before update on encrypted_drafts begin select raise(abort, 'CONFIRMATION_WRITE_FAILURE'); end;",
      );
      await c.generate();
      expect(
        (await drafts.load(scope, CloseReviewController.slot))!.pending,
        isNotNull,
      );
      await db.customStatement('drop trigger fail_review_confirmation');
      await c.generate();
      expect(gateway.commands.map((x) => x.commandId).toSet(), hasLength(1));
      expect(c.pending, isFalse);
    },
  );
  test(
    'MFA revocation hides saved evidence until authoritative recheck',
    () async {
      await ready();
      await c.generate();
      gateway.readFailure = 'MFA_REQUIRED';
      await c.refreshPage();
      expect(c.accessDenied, isTrue);
      expect(c.summary, isEmpty);
      expect(c.rows, isEmpty);
      expect(c.reports, isEmpty);
      gateway.readFailure = null;
      await c.initialize();
      expect(c.accessDenied, isFalse);
      expect(c.summary['id'], 'review-0042');
    },
  );
  test('encrypted report draft cannot cross actor or branch', () async {
    await ready();
    await c.save();
    expect(
      await drafts.load(
        const TenantContext(
          tenantId: 't',
          actorId: 'other',
          legalEntityId: 'e',
          branchId: 'b',
        ),
        CloseReviewController.slot,
      ),
      isNull,
    );
    expect(
      await drafts.load(
        const TenantContext(
          tenantId: 't',
          actorId: 'a',
          legalEntityId: 'e',
          branchId: 'other',
        ),
        CloseReviewController.slot,
      ),
      isNull,
    );
  });
  test('component drill and continuation keep server filter', () async {
    await ready();
    await c.generate();
    await c.select('sources', key: 'GRNI:b');
    await c.refreshPage(more: true);
    expect(gateway.reads.last, {
      'id': 'review-0042',
      'section': 'sources',
      'component': 'GRNI:b',
      'after': '50',
    });
  });
  Future<void> render(WidgetTester t, bool dark) async {
    t.view.physicalSize = const Size(1024, 1900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: CloseReviewWorkspace(controller: c)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'close review ${dark ? 'dark' : 'light'} 200 percent sources and blockers reachable',
      (t) async {
        await ready();
        await c.generate();
        await render(t, dark);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/close_review_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await t.scrollUntilVisible(
          find.text('Source evidence'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text('Source evidence'));
        await t.pumpAndSettle();
        expect(gateway.reads.last['component'], 'GRNI:b');
        expect(find.textContaining('bill-0042'), findsOneWidget);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/close_sources_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await c.select('blockers');
        await t.pumpAndSettle();
        expect(find.text('GRNI_CONTROL_DIFFERENCE'), findsOneWidget);
      },
    );
  }
}
