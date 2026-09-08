import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_screen.dart';
import 'package:jentra_desktop/src/features/sales/quotation_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as fixtures;

void main() {
  setUpAll(_fonts);
  testWidgets('AC-303 direct Sales workspace denies unauthorized reads', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessCapabilitiesProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: const Scaffold(body: QuotationScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Access is restricted'), findsOneWidget);
    expect(find.text('New quotation'), findsNothing);
  });

  testWidgets(
    'AC-303 renders exact saved offer and readable revision decisions',
    (tester) async {
      final harness = await _pump(tester, status: 'approved');
      expect(find.text('QUO-2026-0042'), findsNWidgets(2));
      expect(find.text('Server-calculated totals'), findsOneWidget);
      expect(find.text('118000.000000'), findsWidgets);
      await tester.tap(find.text('Revision & decision history'));
      await tester.pumpAndSettle();
      expect(find.text('Approved · Revision 1'), findsOneWidget);
      expect(find.text('Pricing and delivery approved.'), findsOneWidget);
      expect(find.text('2026-09-06T10:30:00Z'), findsOneWidget);
      expect(harness.repository.commands, isEmpty);
      await expectLater(
        find.byKey(const Key('quotation-golden')),
        matchesGoldenFile('goldens/quotation_history_1440_light.png'),
      );
    },
  );

  testWidgets(
    'AC-303 editor persists terms and sends server calculation request',
    (tester) async {
      final harness = await _pump(tester);
      await tester.enterText(
        find.byKey(const Key('quote-delivery_terms')),
        'Delivery within 14 days',
      );
      await _flush(tester, harness);
      final local = await tester.runAsync(
        () =>
            harness.store.load(fixtures.scope, 'quotation:${fixtures.quoteId}'),
      );
      expect(local!.form['delivery_terms'], 'Delivery within 14 days');
      expect(
        find.text('Local edits · last saved server totals remain unchanged'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save & calculate'));
      await _flush(tester, harness);
      expect(
        (harness.repository.commands.single['payload']
            as Map)['delivery_terms'],
        'Delivery within 14 days',
      );
      expect(find.text('Quotation saved and recalculated.'), findsOneWidget);
    },
  );

  testWidgets(
    'AC-303 bounded picker chooses governed customer and clears dependent contact',
    (tester) async {
      final harness = await _pump(tester);
      await tester.tap(find.byKey(const Key('pick-customer_id')));
      await tester.pumpAndSettle();
      expect(find.text('CUST-002 · Lotus Trading'), findsOneWidget);
      await tester.tap(find.text('CUST-002 · Lotus Trading'));
      await _flush(tester, harness);
      expect(harness.value.form!['customer_id'], 'customer-2');
      expect(harness.value.form!['contact_id'], isNull);
      expect(harness.value.form!['payment_terms_days'], 45);
      expect(
        harness.references.queries.any(
          (query) => query.limit == 25 && query.id == null,
        ),
        true,
      );
      expect(
        harness.references.queries.every((query) => query.limit <= 25),
        true,
      );
    },
  );

  testWidgets(
    'AC-303 unknown result exposes retry UI with stable durable envelope',
    (tester) async {
      final harness = await _pump(tester);
      harness.repository.onCommand = (_) async =>
          throw TimeoutException('uncertain');
      await tester.tap(find.text('Save & calculate'));
      await _flush(tester, harness);
      expect(find.text('Retry saved request'), findsOneWidget);
      final first = harness.repository.commands.single;
      harness.repository.onCommand = (_) async => CommandResult.success(
        requestId: 'replay',
        entity: harness.repository.detail.quotation,
      );
      await tester.tap(find.text('Retry saved request'));
      await _flush(tester, harness);
      expect(harness.repository.commands.last, first);
      expect(find.text('Retry saved request'), findsNothing);
    },
  );

  testWidgets(
    'AC-303 explicit conflict comparison retains reviewed local fields',
    (tester) async {
      final harness = await _pump(tester);
      await tester.enterText(
        find.byKey(const Key('quote-delivery_terms')),
        'Local delivery',
      );
      await _flush(tester, harness);
      harness.repository.onCommand = (_) async => CommandResult.failure(
        requestId: 'conflict',
        error: const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Quotation changed.',
        ),
      );
      await tester.tap(find.text('Save & calculate'));
      await _flush(tester, harness);
      harness.repository.detail = _detail(
        version: 8,
        delivery: 'Server delivery',
      );
      await tester.tap(find.text('Compare & resolve'));
      await _flush(tester, harness);
      expect(find.text('Resolve quotation conflict'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('quotation-golden')),
        matchesGoldenFile('goldens/quotation_conflict_1440_light.png'),
      );
      await tester.tap(find.text('Keep local edits for review'));
      await _flush(tester, harness);
      expect(harness.value.form!['delivery_terms'], 'Local delivery');
      expect(harness.value.localDraft!.expectedVersion, 8);
      expect(harness.repository.commands, hasLength(1));
    },
  );

  testWidgets(
    'AC-303 lifecycle action records reason without bypassing workflow',
    (tester) async {
      final harness = await _pump(tester, status: 'pending_approval');
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm reject'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('quotation-action-reason')),
        'Please revise the delivery terms.',
      );
      await tester.pump();
      await tester.tap(find.text('Confirm reject'));
      await _flush(tester, harness);
      expect(
        (harness.repository.commands.single['payload'] as Map)['note'],
        'Please revise the delivery terms.',
      );
      expect(
        (harness.repository.commands.single['payload'] as Map)['decision'],
        'rejected',
      );
    },
  );

  testWidgets(
    'AC-303 offline existing draft is discoverable and recoverable after restart',
    (tester) async {
      final harness = await _pump(tester, offline: true, select: false);
      await tester.runAsync(
        () => harness.store.save(
          fixtures.scope,
          'quotation:${fixtures.quoteId}',
          _detail().draft.toJson()..['delivery_terms'] = 'Recovered offline',
          expectedVersion: 7,
        ),
      );
      await tester.tap(find.text('Recover local draft'));
      await _flush(tester, harness);
      await tester.tap(find.text('Quotation ${fixtures.quoteId}'));
      await _flush(tester, harness);
      expect(harness.value.form!['delivery_terms'], 'Recovered offline');
      expect(harness.value.recovered, true);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save & calculate'),
            )
            .onPressed,
        isNull,
      );
      expect(harness.repository.commands, isEmpty);
    },
  );

  testWidgets('AC-303 stale modal hides private fields on actor change', (
    tester,
  ) async {
    final harness = await _pump(tester, status: 'pending_approval');
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quotation-action-reason')),
      'Private decision',
    );
    harness.container.updateOverrides(harness.overrides(actor: 'other'));
    await tester.pumpAndSettle();
    expect(find.text('Private decision'), findsNothing);
    expect(find.text('Business scope or access changed'), findsOneWidget);
    expect(harness.repository.commands, isEmpty);
  });

  for (final recovery in [false, true]) {
    testWidgets(
      'AC-303 ${recovery ? 'recovery' : 'picker'} hides data when permission refresh fails',
      (tester) async {
        final harness = await _pump(tester);
        final privateLabel = recovery
            ? 'Private recovered offer'
            : 'CUST-002 · Lotus Trading';
        if (recovery) {
          await tester.runAsync(
            () => harness.store.save(
              fixtures.scope,
              'quotation:${fixtures.quoteId}',
              _detail().draft.toJson()..['_document_number'] = privateLabel,
              expectedVersion: 7,
            ),
          );
          await tester.tap(find.text('Recover local draft'));
          await _flush(tester, harness);
        } else {
          await tester.tap(find.byKey(const Key('pick-customer_id')));
          await tester.pumpAndSettle();
        }
        expect(find.text(privateLabel), findsOneWidget);
        harness.capabilityError = StateError('Permission service unavailable');
        harness.container.invalidate(businessCapabilitiesProvider);
        await tester.runAsync(() async {
          await expectLater(
            harness.container.read(businessCapabilitiesProvider.future),
            throwsStateError,
          );
        });
        await tester.pumpAndSettle();
        expect(find.text(privateLabel), findsNothing);
        expect(harness.repository.commands, isEmpty);
      },
    );
  }

  for (final (name, size, dark, scale) in [
    ('1440_light', const Size(1440, 1000), false, 1.0),
    ('1440_dark', const Size(1440, 1000), true, 1.0),
    ('1024_text200', const Size(1024, 900), false, 2.0),
  ]) {
    testWidgets('AC-303 editor visual and accessible state $name', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        size: size,
        dark: dark,
        textScale: scale,
      );
      if (scale > 1) {
        await tester.scrollUntilVisible(
          find.text('Customer & terms'),
          350,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('quotation-golden')),
        matchesGoldenFile('goldens/quotation_editor_$name.png'),
      );
      expect(harness.value.canEditForm, true);
    });
  }

  testWidgets(
    'AC-303 line editing preserves exact conversion and discount choice',
    (tester) async {
      final harness = await _pump(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('quote-line:quantity')),
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('quotation-detail-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        find.byKey(const Key('quote-line:quantity')),
        '3.000001',
      );
      await _flush(tester, harness);
      expect(
        (harness.value.form!['lines'] as List).single['base_quantity'],
        '3.000001',
      );
      await tester.tap(find.text('Unit conversion'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('quote-line:conversion_numerator')),
      );
      await tester.enterText(
        find.byKey(const Key('quote-line:conversion_numerator')),
        '2',
      );
      await _flush(tester, harness);
      expect(
        (harness.value.form!['lines'] as List).single['base_quantity'],
        '6.000002',
      );
      await tester.ensureVisible(
        find.byKey(const Key('quote-line:unit_price')),
      );
      await tester.enterText(
        find.byKey(const Key('quote-line:unit_price')),
        '90071992547409.123456',
      );
      await _flush(tester, harness);
      expect(
        (harness.value.form!['lines'] as List).single['unit_price'],
        '90071992547409.123456',
      );
      await expectLater(
        find.byKey(const Key('quotation-golden')),
        matchesGoldenFile('goldens/quotation_line_1440_light.png'),
      );
    },
  );

  testWidgets(
    'AC-303 submit approval and acceptance controls follow refreshed server status',
    (tester) async {
      final harness = await _pump(tester);
      harness.repository.onCommand = (wire) async {
        final payload = wire['payload'] as Map;
        final status = payload['action'] == 'submit'
            ? 'pending_approval'
            : payload['action'] == 'accept'
            ? 'accepted'
            : 'approved';
        harness.repository.detail = _detail(
          status: status,
          version: harness.repository.detail.quotation.version + 1,
        );
        return CommandResult.success(
          requestId: 'server',
          entity: harness.repository.detail.quotation,
        );
      };
      for (final action in ['Submit', 'Approve', 'Accept']) {
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm ${action.toLowerCase()}'));
        await _flush(tester, harness);
      }
      expect(harness.value.detail!.quotation.status, 'accepted');
      expect(
        harness.repository.commands.map(
          (wire) => wire['expected_entity_version'],
        ),
        [7, 8, 9],
      );
      expect(find.text('Create revision'), findsNothing);
      expect(find.text('Save & calculate'), findsNothing);
    },
  );

  testWidgets('AC-303 loaded workspace has labelled accessible controls', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(tester, status: 'approved');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });
}

class _Harness {
  _Harness(
    this.database,
    this.store,
    this.repository,
    this.references,
    this.offline,
  );
  final JentraLocalDatabase database;
  final QuotationDraftStore store;
  final _UiRepository repository;
  final _References references;
  final bool offline;
  Object? capabilityError;
  late ProviderContainer container;
  QuotationWorkspaceState get value =>
      container.read(quotationWorkspaceProvider).requireValue;
  List<Override> overrides({String actor = 'actor'}) => [
    activeTenantContextProvider.overrideWithValue(
      fixtures.scope.copyWith(actorId: actor),
    ),
    businessCapabilitiesProvider.overrideWith((ref) async {
      if (capabilityError != null) throw capabilityError!;
      return fixtures.permissions;
    }),
    connectivityStateProvider.overrideWith(
      (ref) => Stream.value(
        offline ? ConnectivityState.offline : ConnectivityState.online,
      ),
    ),
    quotationWorkspaceRepositoryProvider.overrideWithValue(repository),
    leadToCashRepositoryProvider.overrideWithValue(repository),
    quotationReferenceRepositoryProvider.overrideWithValue(references),
    quotationDraftStoreProvider.overrideWithValue(store),
  ];
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String status = 'draft',
  Size size = const Size(1440, 1000),
  bool dark = false,
  double textScale = 1,
  bool offline = false,
  bool select = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final database = JentraLocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final store = QuotationDraftStore(
    EncryptedDraftRepository(
      database,
      DraftCipher(keyStore: fixtures.MemoryKeys()),
    ),
  );
  final repository = _UiRepository(status: status);
  final harness = _Harness(database, store, repository, _References(), offline);
  await tester.pumpWidget(
    ProviderScope(
      retry: (count, error) => null,
      overrides: harness.overrides(),
      child: RepaintBoundary(
        key: const Key('quotation-golden'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: const Scaffold(body: QuotationScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  harness.container = ProviderScope.containerOf(
    tester.element(find.byType(QuotationScreen)),
  );
  await tester.runAsync(() async {
    await harness.container.read(quotationWorkspaceProvider.future);
    if (select) {
      await harness.container
          .read(quotationWorkspaceProvider.notifier)
          .selectQuotation(fixtures.quoteId);
    }
  });
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _flush(WidgetTester tester, _Harness harness) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final state = harness.container.read(quotationWorkspaceProvider).value;
      if (state != null &&
          !state.busy &&
          !state.savingLocal &&
          !state.loading) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return;
      }
    }
  });
  await tester.pumpAndSettle();
}

QuotationDetail _detail({
  String status = 'draft',
  int version = 7,
  String delivery = 'Within 7 working days',
}) {
  final snapshot = fixtures.snapshot(status: status, version: version);
  snapshot.addAll({
    'document_number': 'QUO-2026-0042',
    'customer_id': 'CUST-001 · Acme Distribution',
    'salesperson_id': 'Sales team member',
    'delivery_terms': delivery,
    'subtotal': '100000.000000',
    'tax_total': '18000.000000',
    'grand_total': '118000.000000',
    'base_total': '118000.000000',
    'notes': 'Thank you for considering our offer.',
  });
  final line = ((snapshot['lines'] as List).single as Map)
      .cast<String, Object?>();
  line.addAll({
    'description': 'Managed workplace installation',
    'quantity': '2.000000',
    'base_quantity': '2.000000',
    'unit_price': '50000.000000',
    'unit_id': 'EA · Each',
    'tax_definition_id': 'vat',
    'tax_name': 'VAT',
    'tax_code': 'VAT18',
    'tax_kind': 'vat',
    'tax_rate': '18.000000',
    'tax_inclusive': false,
    'tax_definition_version': 1,
    'line_discount_amount': '0.000000',
    'header_discount_amount': '0.000000',
    'tax_amount': '18000.000000',
    'line_total': '118000.000000',
  });
  return QuotationDetail.fromJson(snapshot);
}

class _UiRepository extends fixtures.FakeQuotations {
  _UiRepository({String status = 'draft'}) {
    detail = _detail(status: status);
    page = CursorPage(items: [detail.quotation], limit: 50);
  }
  @override
  Future<List<SalesQuotationRevision>> quotationRevisions({
    required TenantContext context,
    required String id,
    int beforeRevision = 2147483647,
  }) async => [
    SalesQuotationRevision(
      id: 'revision',
      tenantId: 'tenant',
      legalEntityId: 'entity',
      branchId: 'branch',
      quotationId: id,
      revisionNumber: 1,
      status: 'submitted',
      snapshot: detail.snapshot,
      createdBy: 'Sales team member',
      createdAt: DateTime.utc(2026, 9, 6, 9),
      reason: 'Initial customer offer',
    ),
  ];
  @override
  Future<List<Map<String, Object?>>> quotationDecisions({
    required TenantContext context,
    required String id,
    String? beforeId,
  }) async => [
    {
      'id': 'decision',
      'revision_number': 1,
      'decision': 'approved',
      'actor_id': 'Sales approver',
      'step_order': 1,
      'currency_code': 'LKR',
      'amount': '118000.000000',
      'note': 'Pricing and delivery approved.',
      'decided_at': '2026-09-06T10:30:00Z',
    },
  ];
}

class _References implements QuotationReferenceRepository {
  QuotationReferenceQuery? lastQuery;
  final queries = <QuotationReferenceQuery>[];
  @override
  Future<CursorPage<QuotationReference>> pageReferences({
    required TenantContext context,
    required QuotationReferenceKind kind,
    required QuotationReferenceQuery query,
  }) async {
    lastQuery = query;
    queries.add(query);
    return CursorPage(
      items: [
        QuotationReference(
          id: 'customer-2',
          label: 'CUST-002 · Lotus Trading',
          values: {'payment_terms_days': 45},
        ),
      ],
      limit: query.limit,
    );
  }
}

Future<void> _fonts() async {
  const root = 'packages/jentra_design_system/assets/fonts';
  await (FontLoader(JentraTypography.sansFamily)
        ..addFont(rootBundle.load('$root/Manrope-Regular.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-Medium.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-SemiBold.ttf')))
      .load();
  await (FontLoader(
    JentraTypography.monoFamily,
  )..addFont(rootBundle.load('$root/IBMPlexMono-Regular.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
