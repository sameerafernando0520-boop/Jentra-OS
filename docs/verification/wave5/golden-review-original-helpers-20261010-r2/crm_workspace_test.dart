import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/router.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

void main() {
  setUpAll(_loadTestFonts);

  test('CRM gating preserves the Operations navigation group — FR-383', () {
    final visible = visibleJentraDestinations(const {});

    expect(visible.any((item) => item.path == '/crm'), isFalse);
    expect(
      visible.firstWhere((item) => item.path == '/procurement').section,
      'OPERATIONS',
    );
  });

  testWidgets(
    'CRM direct route fails closed without a view capability — AC-322',
    (tester) async {
      await _pumpCrm(
        tester,
        repository: _FakeCrmRepository(),
        capabilities: {},
      );

      expect(find.text('Access is restricted'), findsOneWidget);
      expect(find.text('Pipeline control centre'), findsNothing);
    },
  );

  testWidgets('CRM exposes an accessible loading state — AC-321', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final completer = Completer<CursorPage<CrmPipelineEntry>>();
      final repository = _FakeCrmRepository(pipelineCompleter: completer);

      await _pumpCrm(
        tester,
        repository: repository,
        capabilities: _viewCapabilities,
        settle: false,
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Loading CRM pipeline'), findsOneWidget);

      completer.complete(_page());
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'CRM exposes retryable error and empty states — AC-321 / FR-395',
    (tester) async {
      final failed = _FakeCrmRepository(
        readError: const DomainError(
          code: 'NETWORK_ERROR',
          message: 'The development service is unavailable.',
          retryable: true,
        ),
      );
      await _pumpCrm(
        tester,
        repository: failed,
        capabilities: _viewCapabilities,
      );

      expect(find.text('CRM data unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await _pumpCrm(
        tester,
        repository: _FakeCrmRepository(),
        capabilities: _viewCapabilities,
      );
      expect(find.text('No pipeline records'), findsOneWidget);
      expect(find.text('New lead'), findsNothing);
    },
  );

  testWidgets(
    'CRM renders currency-separated pipeline, detail, and timeline — AC-302 / AC-321',
    (tester) async {
      await _pumpCrm(
        tester,
        repository: _FakeCrmRepository(populated: true),
        capabilities: _manageCapabilities,
      );

      expect(find.text('Pipeline control centre'), findsOneWidget);
      expect(find.text('As of 05 Sep 2026'), findsOneWidget);
      expect(find.text('LKR 1,500.100000'), findsOneWidget);
      expect(find.text('USD 500.000000'), findsOneWidget);
      expect(find.text('OPP-001'), findsOneWidget);
      expect(find.text('LEAD-001'), findsOneWidget);
      expect(find.text('Next action'), findsOneWidget);
      expect(find.text('Prepare proposal'), findsOneWidget);
      expect(find.text('Qualification call'), findsOneWidget);
      expect(
        find.text('Aging basis: created at · stale after 90 days'),
        findsOneWidget,
      );
    },
  );

  testWidgets('CRM search submits a bounded literal query — FR-389', (
    tester,
  ) async {
    final repository = _FakeCrmRepository(populated: true);
    await _pumpCrm(
      tester,
      repository: repository,
      capabilities: _viewCapabilities,
    );

    await tester.enterText(find.byKey(const Key('crm-search')), '  Acme%_  ');
    await tester.tap(find.byTooltip('Search pipeline'));
    await tester.pumpAndSettle();

    expect(repository.lastQuery?.normalizedSearch, 'Acme%_');
    expect(repository.lastQuery?.limit, 50);
  });

  testWidgets(
    'CRM creates a lead with stable command identities and exact value — AC-302',
    (tester) async {
      final repository = _FakeCrmRepository(populated: true);
      await _pumpCrm(
        tester,
        repository: repository,
        capabilities: _manageCapabilities,
      );

      await tester.tap(find.text('New lead'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crm-lead-code')),
        'lead-002',
      );
      await tester.enterText(
        find.byKey(const Key('crm-lead-name')),
        'Lanka Distribution',
      );
      await tester.enterText(
        find.byKey(const Key('crm-lead-source')),
        'Campaign',
      );
      await tester.enterText(
        find.byKey(const Key('crm-lead-value')),
        '2500.125000',
      );
      await tester.enterText(find.byKey(const Key('crm-lead-currency')), 'usd');
      await tester.enterText(
        find.byKey(const Key('crm-lead-close-date')),
        '2026-12-31',
      );
      await tester.tap(find.text('Save lead'));
      await tester.pumpAndSettle();

      final command = repository.lastLeadCommand;
      expect(command, isNotNull);
      expect(command!.commandId, isNotEmpty);
      expect(command.idempotencyKey, isNotEmpty);
      expect(command.payload.toJson(), containsPair('code', 'LEAD-002'));
      expect(
        command.payload.toJson(),
        containsPair('expected_value', '2500.125000'),
      );
      expect(command.payload.toJson(), containsPair('currency_code', 'USD'));
      expect(find.text('Lead saved.'), findsOneWidget);
    },
  );

  testWidgets('CRM remains reachable at 200% text scale — NFR-314 / NFR-315', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpCrm(
      tester,
      repository: _FakeCrmRepository(populated: true),
      capabilities: _manageCapabilities,
      size: const Size(1024, 720),
      density: JentraDensity.compact,
    );

    expect(find.text('Pipeline control centre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CRM desktop composition matches its approved visual contract — AC-321',
    (tester) async {
      await _pumpCrm(
        tester,
        repository: _FakeCrmRepository(populated: true),
        capabilities: _manageCapabilities,
      );

      await expectLater(
        find.byType(JentraApp),
        matchesGoldenFile('goldens/crm_1440_light_comfortable.png'),
      );
    },
  );
}

const _viewCapabilities = <String>{'crm.leads.view', 'crm.opportunities.view'};

const _manageCapabilities = <String>{
  'sales.quotations.view',
  'crm.leads.view',
  'crm.leads.manage',
  'crm.leads.convert',
  'crm.activities.manage',
  'crm.opportunities.view',
  'crm.opportunities.manage',
};

Future<void> _pumpCrm(
  WidgetTester tester, {
  required CrmRepository repository,
  required Set<String> capabilities,
  bool settle = true,
  Size size = const Size(1440, 900),
  JentraDensity density = JentraDensity.comfortable,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          const RuntimeConfig(
            environment: 'development',
            supabaseUrl: 'https://development.invalid',
            supabasePublishableKey: 'test-publishable-key',
          ),
        ),
        foundationGatewayProvider.overrideWithValue(null),
        crmRepositoryProvider.overrideWithValue(repository),
        activeTenantContextProvider.overrideWithValue(
          const TenantContext(
            tenantId: 'tenant-1',
            actorId: 'user-1',
            legalEntityId: 'entity-1',
            branchId: 'branch-1',
          ),
        ),
        businessCapabilitiesProvider.overrideWith((ref) async => capabilities),
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(ConnectivityState.online),
        ),
        appPreferencesProvider.overrideWithBuild(
          (ref, notifier) async =>
              AppPreferences(themeMode: ThemeMode.light, density: density),
        ),
        tenantListProvider.overrideWithBuild(
          (ref, notifier) async => const [
            TenantSummary(
              id: 'tenant-1',
              name: 'Jentra Holdings',
              slug: 'jentra-holdings',
              status: 'active',
              membershipStatus: 'active',
            ),
          ],
        ),
      ],
      child: const JentraApp(),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(JentraApp)),
  );
  container.read(routerProvider).go('/crm');
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

final class _FakeCrmRepository implements CrmRepository {
  _FakeCrmRepository({
    this.populated = false,
    this.readError,
    this.pipelineCompleter,
  });

  final bool populated;
  final DomainError? readError;
  final Completer<CursorPage<CrmPipelineEntry>>? pipelineCompleter;

  CrmPipelineQuery? lastQuery;
  CommandEnvelope<CrmLeadDraft>? lastLeadCommand;

  @override
  Future<CrmPipelineSummary> getPipelineSummary({
    required TenantContext context,
    required DateTime asOfDate,
  }) async {
    if (readError case final error?) throw error;
    return _summary();
  }

  @override
  Future<CursorPage<CrmPipelineEntry>> listPipeline({
    required TenantContext context,
    CrmPipelineQuery? query,
  }) async {
    if (readError case final error?) throw error;
    lastQuery = query;
    if (pipelineCompleter case final completer?) return completer.future;
    return _page(populated: populated);
  }

  @override
  Future<List<CrmActivity>> listActivities({
    required TenantContext context,
    required CrmAggregateType aggregateType,
    required String aggregateId,
    int limit = 50,
  }) async => populated ? [_activity()] : const [];

  @override
  Future<CrmLead?> findLead({
    required TenantContext context,
    required String id,
  }) async => populated && id == 'lead-1' ? _leadDetail() : null;

  @override
  Future<CrmOpportunity?> findOpportunity({
    required TenantContext context,
    required String id,
  }) async => populated && id == 'opportunity-1' ? _opportunityDetail() : null;

  @override
  Future<CommandResult<CrmLead>> upsertLead(
    CommandEnvelope<CrmLeadDraft> command,
  ) async {
    lastLeadCommand = command;
    return CommandResult.success(
      requestId: command.idempotencyKey,
      entity: _leadFrom(command.payload),
    );
  }

  @override
  Future<CommandResult<CrmLeadConversion>> convertLead(
    CommandEnvelope<CrmLeadConversionDraft> command,
  ) => throw UnimplementedError();

  @override
  Future<CommandResult<CrmActivity>> recordActivity(
    CommandEnvelope<CrmActivityDraft> command,
  ) => throw UnimplementedError();

  @override
  Future<CommandResult<CrmOpportunity>> upsertOpportunity(
    CommandEnvelope<CrmOpportunityDraft> command,
  ) => throw UnimplementedError();
}

CursorPage<CrmPipelineEntry> _page({bool populated = false}) => CursorPage(
  items: populated ? [_opportunityEntry(), _leadEntry()] : const [],
  limit: 50,
  filters: const {},
  sort: const ['id'],
);

CrmPipelineSummary _summary() => CrmPipelineSummary(
  asOfDate: DateTime.utc(2026, 9, 5),
  currencyTotals: [
    CrmCurrencyTotal(
      currencyCode: 'LKR',
      opportunityCount: 2,
      expectedValue: Money.parse('1500.100000', 'LKR'),
      weightedValue: Money.parse('950.200000', 'LKR'),
    ),
    CrmCurrencyTotal(
      currencyCode: 'USD',
      opportunityCount: 1,
      expectedValue: Money.parse('500.000000', 'USD'),
      weightedValue: Money.parse('125.000000', 'USD'),
    ),
  ],
  stageTotals: [
    CrmStageTotal(
      stage: 'submitted',
      total: CrmCurrencyTotal(
        currencyCode: 'LKR',
        opportunityCount: 2,
        expectedValue: Money.parse('1500.100000', 'LKR'),
        weightedValue: Money.parse('950.200000', 'LKR'),
      ),
    ),
  ],
  forecastTotals: [
    CrmForecastTotal(
      forecastBucket: 'pipeline',
      total: CrmCurrencyTotal(
        currencyCode: 'LKR',
        opportunityCount: 2,
        expectedValue: Money.parse('1500.100000', 'LKR'),
        weightedValue: Money.parse('950.200000', 'LKR'),
      ),
    ),
  ],
  conversion: CrmConversionMetrics(
    totalLeads: 4,
    convertedLeads: 1,
    rate: ExactDecimal.parse('25.000000', scale: 6),
  ),
  winLoss: CrmWinLossMetrics(won: 3, lost: 1, decided: 4),
  activityRecency: CrmActivityRecency(
    activityCount: 7,
    latestActivityAt: DateTime.utc(2026, 9, 5, 6, 15),
  ),
  aging: CrmAgingMetrics(
    ageBasis: 'created_at',
    staleAfterDays: 90,
    openOpportunityCount: 3,
    averageAgeDays: ExactDecimal.parse('12.666667', scale: 6),
    oldestAgeDays: 31,
    staleOpportunityCount: 0,
  ),
);

CrmPipelineEntry _opportunityEntry() => CrmPipelineEntry(
  entryType: CrmEntryType.opportunity,
  id: 'opportunity-1',
  tenantId: 'tenant-1',
  legalEntityId: 'entity-1',
  branchId: 'branch-1',
  code: 'OPP-001',
  name: 'Acme retail rollout',
  ownerId: 'user-1',
  stage: 'submitted',
  status: 'open',
  probability: ExactDecimal.parse('60.00', scale: 2),
  expectedValue: Money.parse('750.250000', 'LKR'),
  weightedValue: Money.parse('450.150000', 'LKR'),
  expectedCloseDate: DateTime.utc(2026, 10, 31),
  stageEnteredAt: DateTime.utc(2026, 9, 4),
  createdAt: DateTime.utc(2026, 9, 1),
  lastActivityAt: DateTime.utc(2026, 9, 5, 6, 15),
);

CrmPipelineEntry _leadEntry() => CrmPipelineEntry(
  entryType: CrmEntryType.lead,
  id: 'lead-1',
  tenantId: 'tenant-1',
  legalEntityId: 'entity-1',
  branchId: 'branch-1',
  code: 'LEAD-001',
  name: 'Lanka Distribution',
  ownerId: 'user-1',
  stage: 'draft',
  status: 'active',
  expectedValue: Money.parse('500.000000', 'USD'),
  expectedCloseDate: DateTime.utc(2026, 12, 31),
  stageEnteredAt: DateTime.utc(2026, 9, 5),
  createdAt: DateTime.utc(2026, 9, 5),
);

CrmActivity _activity() => CrmActivity(
  id: 'activity-1',
  tenantId: 'tenant-1',
  legalEntityId: 'entity-1',
  branchId: 'branch-1',
  aggregateType: CrmAggregateType.opportunity,
  aggregateId: 'opportunity-1',
  activityType: 'call',
  subject: 'Qualification call',
  ownerId: 'user-1',
  activityAt: DateTime.utc(2026, 9, 5, 6, 15),
  status: 'completed',
  completedAt: DateTime.utc(2026, 9, 5, 6, 45),
  outcome: 'Requirements confirmed',
  version: 1,
  createdAt: DateTime.utc(2026, 9, 5, 6, 45),
);

CrmLead _leadDetail() => CrmLead(
  id: 'lead-1',
  tenantId: 'tenant-1',
  legalEntityId: 'entity-1',
  branchId: 'branch-1',
  code: 'LEAD-001',
  leadType: 'organization',
  name: 'Lanka Distribution',
  source: 'campaign',
  ownerId: 'user-1',
  stage: 'draft',
  expectedValue: Money.parse('500.000000', 'USD'),
  expectedCloseDate: DateTime.utc(2026, 12, 31),
  status: 'active',
  version: 1,
  createdAt: DateTime.utc(2026, 9, 5),
  updatedAt: DateTime.utc(2026, 9, 5),
);

CrmOpportunity _opportunityDetail() => CrmOpportunity(
  id: 'opportunity-1',
  tenantId: 'tenant-1',
  legalEntityId: 'entity-1',
  branchId: 'branch-1',
  code: 'OPP-001',
  prospectName: 'Acme retail rollout',
  ownerId: 'user-1',
  stage: 'submitted',
  probability: ExactDecimal.parse('60.00', scale: 2),
  expectedValue: Money.parse('750.250000', 'LKR'),
  weightedValue: Money.parse('450.150000', 'LKR'),
  expectedCloseDate: DateTime.utc(2026, 10, 31),
  nextAction: 'Prepare proposal',
  forecastBucket: 'pipeline',
  status: 'open',
  version: 2,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 5),
);

CrmLead _leadFrom(CrmLeadDraft draft) => CrmLead(
  id: 'lead-2',
  tenantId: 'tenant-1',
  legalEntityId: 'entity-1',
  branchId: 'branch-1',
  code: draft.code.toUpperCase(),
  leadType: draft.leadType,
  name: draft.name,
  source: draft.source,
  ownerId: draft.ownerId,
  stage: draft.stage,
  expectedValue: draft.expectedValue,
  expectedCloseDate: draft.expectedCloseDate,
  status: draft.status,
  version: 1,
  createdAt: DateTime.utc(2026, 9, 5),
  updatedAt: DateTime.utc(2026, 9, 5),
);

Future<void> _loadTestFonts() async {
  const fontRoot = 'packages/jentra_design_system/assets/fonts';
  final sans = FontLoader(JentraTypography.sansFamily)
    ..addFont(rootBundle.load('$fontRoot/Manrope-Regular.ttf'))
    ..addFont(rootBundle.load('$fontRoot/Manrope-Medium.ttf'))
    ..addFont(rootBundle.load('$fontRoot/Manrope-SemiBold.ttf'));
  final mono = FontLoader(JentraTypography.monoFamily)
    ..addFont(rootBundle.load('$fontRoot/IBMPlexMono-Regular.ttf'));
  final sinhala = FontLoader(JentraTypography.fallbackFamilies.first)
    ..addFont(rootBundle.load('$fontRoot/NotoSansSinhala-Regular.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansSinhala-Medium.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansSinhala-SemiBold.ttf'));
  final tamil = FontLoader(JentraTypography.fallbackFamilies.last)
    ..addFont(rootBundle.load('$fontRoot/NotoSansTamil-Regular.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansTamil-Medium.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansTamil-SemiBold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await sans.load();
  await mono.load();
  await sinhala.load();
  await tamil.load();
  await materialIcons.load();
}
