import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/tenant/workspace_creation.dart';

final runtimeConfigProvider = Provider<RuntimeConfig>(
  (ref) => RuntimeConfig.fromEnvironment(),
);

final foundationGatewayProvider = Provider<SupabaseFoundationGateway?>(
  (ref) => null,
);

final stockOpeningAccessGatewayProvider = Provider<StockOpeningAccessGateway?>(
  (ref) => null,
);

final stockOpeningInvitationsProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
      final actor = await ref.watch(authenticatedActorProvider.future);
      if (actor == null) return const [];
      return await ref.watch(stockOpeningAccessGatewayProvider)?.pending() ??
          const [];
    });

final businessSetupGatewayProvider = Provider<SupabaseBusinessSetupGateway?>(
  (ref) => null,
);

final crmRepositoryProvider = Provider<CrmRepository?>((ref) => null);

final leadToCashRepositoryProvider = Provider<LeadToCashRepository?>(
  (ref) => null,
);
final quotationWorkspaceRepositoryProvider =
    Provider<QuotationWorkspaceRepository?>((ref) => null);
final salesOrderRepositoryProvider = Provider<SalesOrderWorkspaceRepository?>(
  (ref) => null,
);
final salesOrderDraftStoreProvider = Provider<QuotationDraftStore>(
  (ref) =>
      QuotationDraftStore.orders(ref.watch(encryptedDraftRepositoryProvider)),
);
final quotationReferenceRepositoryProvider =
    Provider<QuotationReferenceRepository?>((ref) => null);
final quotationDraftStoreProvider = Provider<QuotationDraftStore>(
  (ref) => QuotationDraftStore(ref.watch(encryptedDraftRepositoryProvider)),
);

// Actor changes must invalidate scope-bound state even when the tenant stays selected.
final authenticatedActorProvider = StreamProvider<String?>((ref) async* {
  final gateway = ref.watch(foundationGatewayProvider);
  if (gateway == null) {
    yield 'preview-actor';
    return;
  }
  yield gateway.currentUser?.id;
  await for (final _ in gateway.authChanges) {
    yield gateway.currentUser?.id;
  }
});

// MFA and token refresh can change authority without changing the actor ID.
// Keep a non-sensitive revision so capability reads react to every auth event.
final authSessionRevisionProvider = StreamProvider<int>((ref) async* {
  final gateway = ref.watch(foundationGatewayProvider);
  var revision = 0;
  yield revision;
  if (gateway == null) return;
  await for (final _ in gateway.authChanges) {
    yield ++revision;
  }
});

final sessionAssuranceProvider = Provider<MfaAssurance>((ref) {
  final revision = ref.watch(authSessionRevisionProvider);
  if (revision.isLoading || revision.hasError) {
    return MfaAssurance.unauthenticated;
  }
  return ref.watch(foundationGatewayProvider)?.currentAssurance() ??
      MfaAssurance.unauthenticated;
});

final localDatabaseProvider = Provider<JentraLocalDatabase>((ref) {
  final database = JentraLocalDatabase.open();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final draftCipherProvider = Provider<DraftCipher>(
  (ref) => DraftCipher(keyStore: WindowsCredentialKeyStore()),
);

final encryptedDraftRepositoryProvider = Provider<EncryptedDraftRepository>(
  (ref) => EncryptedDraftRepository(
    ref.watch(localDatabaseProvider),
    ref.watch(draftCipherProvider),
  ),
);

final referenceCacheRepositoryProvider =
    Provider<EncryptedReferenceCacheRepository>(
      (ref) => EncryptedReferenceCacheRepository(
        ref.watch(localDatabaseProvider),
        ref.watch(draftCipherProvider),
      ),
    );

final setupTabularCodecProvider = Provider<SetupTabularCodec>(
  (ref) => const SetupTabularCodec(),
);

final setupFileServiceProvider = Provider<SetupFileService>(
  (ref) => const SetupFileService(),
);

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

final connectivityStateProvider = StreamProvider<ConnectivityState>((ref) {
  if (!ref.watch(runtimeConfigProvider).isSupabaseConfigured) {
    return Stream.value(ConnectivityState.online);
  }
  final service = ref.watch(connectivityServiceProvider);
  return (() async* {
    yield await service.current();
    yield* service.watch();
  })();
});

final class AppPreferences {
  const AppPreferences({required this.themeMode, required this.density});

  final ThemeMode themeMode;
  final JentraDensity density;

  AppPreferences copyWith({ThemeMode? themeMode, JentraDensity? density}) =>
      AppPreferences(
        themeMode: themeMode ?? this.themeMode,
        density: density ?? this.density,
      );
}

final appPreferencesProvider =
    AsyncNotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

final class AppPreferencesController extends AsyncNotifier<AppPreferences> {
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<AppPreferences> build() async {
    final mode = await _store.getString('jentra.theme');
    final density = await _store.getString('jentra.density');
    return AppPreferences(
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == mode,
        orElse: () => ThemeMode.light,
      ),
      density: JentraDensity.values.firstWhere(
        (value) => value.name == density,
        orElse: () => JentraDensity.comfortable,
      ),
    );
  }

  Future<void> toggleTheme() async {
    final current = state.value;
    if (current == null) return;
    final next = current.copyWith(
      themeMode: current.themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark,
    );
    state = AsyncData(next);
    await _store.setString('jentra.theme', next.themeMode.name);
  }

  Future<void> toggleDensity() async {
    final current = state.value;
    if (current == null) return;
    final next = current.copyWith(
      density: current.density == JentraDensity.compact
          ? JentraDensity.comfortable
          : JentraDensity.compact,
    );
    state = AsyncData(next);
    await _store.setString('jentra.density', next.density.name);
  }
}

final tenantListProvider =
    AsyncNotifierProvider<TenantListController, List<TenantSummary>>(
      TenantListController.new,
    );

final class TenantListController extends AsyncNotifier<List<TenantSummary>> {
  @override
  Future<List<TenantSummary>> build() async {
    final gateway = ref.watch(foundationGatewayProvider);
    if (gateway == null) {
      return const [
        TenantSummary(
          id: 'preview-tenant',
          name: 'Jentra Holdings',
          slug: 'jentra-holdings',
          status: 'active',
          membershipStatus: 'active',
        ),
      ];
    }
    // Observe current stream data as well as initial readiness. A later account
    // must rebuild membership even when an earlier stream future has settled.
    final actor = ref.watch(authenticatedActorProvider);
    final actorId = actor.isLoading
        ? await ref.watch(authenticatedActorProvider.future)
        : actor.value;
    if (actorId == null) return const [];
    return gateway.listMyTenants();
  }

  Future<void> createTenant(WorkspaceCreationRequest request) async {
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null) {
      throw const WorkspaceCreationException(
        WorkspaceCreationFailure.unavailable,
      );
    }
    void requireActor() {
      if (!ref.mounted ||
          !identical(ref.read(foundationGatewayProvider), gateway) ||
          gateway.currentUser?.id != request.actorId) {
        throw const WorkspaceCreationException(
          WorkspaceCreationFailure.sessionChanged,
        );
      }
    }

    Future<List<TenantSummary>> loadMemberships() async {
      requireActor();
      try {
        final tenants = await gateway.listMyTenants();
        requireActor();
        return tenants;
      } on WorkspaceCreationException {
        rethrow;
      } on Object {
        throw const WorkspaceCreationException(
          WorkspaceCreationFailure.unconfirmed,
        );
      }
    }

    void publish(List<TenantSummary> tenants) {
      requireActor();
      state = AsyncData(tenants);
    }

    requireActor();
    Map<String, Object?> receipt;
    try {
      receipt = await gateway.bootstrapTenant(
        name: request.name,
        slug: request.slug,
        legalEntityName: request.legalEntityName,
        legalEntityCode: request.legalEntityCode,
        branchName: request.branchName,
        branchCode: request.branchCode,
        idempotencyKey: request.idempotencyKey,
      );
    } on TenantBootstrapException catch (error) {
      requireActor();
      if (error.failure == TenantBootstrapFailure.duplicate) {
        // A prior timed-out creation can commit while the same request retries.
        // Resolve its owner membership before allowing a new intent or key.
        final tenants = await loadMemberships();
        if (tenants.any(
          (tenant) =>
              tenant.slug == request.slug &&
              tenant.membershipStatus == 'active',
        )) {
          publish(tenants);
          return;
        }
        throw const WorkspaceCreationException(
          WorkspaceCreationFailure.duplicateSlug,
        );
      }
      throw WorkspaceCreationException(switch (error.failure) {
        TenantBootstrapFailure.invalidValues =>
          WorkspaceCreationFailure.invalidValues,
        TenantBootstrapFailure.accessDenied =>
          WorkspaceCreationFailure.accessDenied,
        _ => WorkspaceCreationFailure.unconfirmed,
      });
    } on Object {
      requireActor();
      throw const WorkspaceCreationException(
        WorkspaceCreationFailure.unconfirmed,
      );
    }
    final tenants = await loadMemberships();
    if (receipt['tenant_id'] is! String ||
        !tenants.any(
          (tenant) =>
              tenant.id == receipt['tenant_id'] &&
              tenant.slug == request.slug &&
              tenant.membershipStatus == 'active',
        )) {
      throw const WorkspaceCreationException(
        WorkspaceCreationFailure.unconfirmed,
      );
    }
    publish(tenants);
  }
}

final class BusinessScopeState {
  const BusinessScopeState({
    required this.tenants,
    required this.legalEntities,
    required this.branches,
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
  });

  final List<TenantSummary> tenants;
  final List<LegalEntitySummary> legalEntities;
  final List<BranchSummary> branches;
  final String tenantId;
  final String? legalEntityId;
  final String? branchId;

  TenantSummary get tenant => tenants.firstWhere((item) => item.id == tenantId);

  LegalEntitySummary? get legalEntity => legalEntityId == null
      ? null
      : legalEntities.where((item) => item.id == legalEntityId).firstOrNull;

  BranchSummary? get branch => branchId == null
      ? null
      : branches.where((item) => item.id == branchId).firstOrNull;

  TenantContext toContext(String actorId) => TenantContext(
    tenantId: tenantId,
    actorId: actorId,
    legalEntityId: legalEntityId,
    branchId: branchId,
  );
}

final businessScopeProvider =
    AsyncNotifierProvider<BusinessScopeController, BusinessScopeState>(
      BusinessScopeController.new,
    );

final class BusinessScopeController extends AsyncNotifier<BusinessScopeState> {
  BusinessScopeState? _lastScope;
  SupabaseFoundationGateway? _lastGateway;
  String? _lastActor;
  int _selectionRevision = 0;

  String? _actor(SupabaseFoundationGateway? gateway) =>
      gateway == null ? 'preview-actor' : gateway.currentUser?.id;

  bool _isCurrent(
    SupabaseFoundationGateway? gateway,
    String? actor,
    int revision,
  ) =>
      ref.mounted &&
      identical(ref.read(foundationGatewayProvider), gateway) &&
      actor != null &&
      _actor(gateway) == actor &&
      revision == _selectionRevision;

  void _remember(
    BusinessScopeState scope,
    SupabaseFoundationGateway? gateway,
    String? actor,
  ) {
    _lastScope = scope;
    _lastGateway = gateway;
    _lastActor = actor;
  }

  @override
  Future<BusinessScopeState> build() async {
    final gateway = ref.watch(foundationGatewayProvider);
    ref.watch(authenticatedActorProvider);
    final actor = _actor(gateway);
    final revision = ++_selectionRevision;
    final previous = identical(_lastGateway, gateway) && _lastActor == actor
        ? _lastScope
        : null;
    final tenants = await ref.watch(tenantListProvider.future);
    if (tenants.isEmpty) {
      throw StateError('Create or join a business before selecting a scope.');
    }
    final tenantId = tenants.any((item) => item.id == previous?.tenantId)
        ? previous!.tenantId
        : tenants.first.id;
    final scope = await _load(
      tenants,
      tenantId,
      gateway: gateway,
      preferredEntityId: tenantId == previous?.tenantId
          ? previous?.legalEntityId
          : null,
      preferredBranchId: tenantId == previous?.tenantId
          ? previous?.branchId
          : null,
    );
    if (_isCurrent(gateway, actor, revision)) {
      _remember(scope, gateway, actor);
    }
    return scope;
  }

  Future<void> selectTenant(String tenantId) async {
    final current = state.value;
    if (current == null ||
        current.tenantId == tenantId ||
        !current.tenants.any((item) => item.id == tenantId)) {
      return;
    }
    final gateway = ref.read(foundationGatewayProvider);
    final actor = _actor(gateway);
    final revision = ++_selectionRevision;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _load(current.tenants, tenantId, gateway: gateway),
    );
    if (!_isCurrent(gateway, actor, revision)) return;
    if (result case AsyncData(:final value)) {
      _remember(value, gateway, actor);
    }
    state = result;
  }

  Future<void> selectLegalEntity(String legalEntityId) async {
    final current = state.value;
    if (current == null ||
        current.legalEntityId == legalEntityId ||
        !current.legalEntities.any((item) => item.id == legalEntityId)) {
      return;
    }
    final gateway = ref.read(foundationGatewayProvider);
    final actor = _actor(gateway);
    final revision = ++_selectionRevision;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final branches = gateway == null
          ? _previewBranches(current.tenantId, legalEntityId)
          : await gateway.listBranches(
              tenantId: current.tenantId,
              legalEntityId: legalEntityId,
            );
      return BusinessScopeState(
        tenants: current.tenants,
        legalEntities: current.legalEntities,
        branches: branches,
        tenantId: current.tenantId,
        legalEntityId: legalEntityId,
        branchId: branches.firstOrNull?.id,
      );
    });
    if (!_isCurrent(gateway, actor, revision)) return;
    if (result case AsyncData(:final value)) {
      _remember(value, gateway, actor);
    }
    state = result;
  }

  void selectBranch(String branchId) {
    final current = state.value;
    if (current == null ||
        current.branchId == branchId ||
        !current.branches.any((item) => item.id == branchId)) {
      return;
    }
    final next = BusinessScopeState(
      tenants: current.tenants,
      legalEntities: current.legalEntities,
      branches: current.branches,
      tenantId: current.tenantId,
      legalEntityId: current.legalEntityId,
      branchId: branchId,
    );
    ++_selectionRevision;
    _remember(
      next,
      ref.read(foundationGatewayProvider),
      _actor(ref.read(foundationGatewayProvider)),
    );
    state = AsyncData(next);
  }

  Future<bool> selectPermittedContext({
    required String tenantId,
    required String legalEntityId,
    required String branchId,
    bool Function()? isCurrent,
  }) async {
    final current = state.value;
    if (isCurrent?.call() == false ||
        current == null ||
        !current.tenants.any((item) => item.id == tenantId)) {
      return false;
    }
    if (current.tenantId == tenantId &&
        current.legalEntityId == legalEntityId &&
        current.branchId == branchId) {
      return true;
    }
    final gateway = ref.read(foundationGatewayProvider);
    final actor = _actor(gateway);
    final revision = _selectionRevision;
    final entities = current.tenantId == tenantId
        ? current.legalEntities
        : gateway == null
        ? _previewEntities(tenantId)
        : await gateway.listLegalEntities(tenantId);
    if (!entities.any((item) => item.id == legalEntityId) ||
        isCurrent?.call() == false ||
        !_isCurrent(gateway, actor, revision) ||
        !identical(state.value, current)) {
      return false;
    }
    final branches =
        current.tenantId == tenantId && current.legalEntityId == legalEntityId
        ? current.branches
        : gateway == null
        ? _previewBranches(tenantId, legalEntityId)
        : await gateway.listBranches(
            tenantId: tenantId,
            legalEntityId: legalEntityId,
          );
    if (!branches.any((item) => item.id == branchId) ||
        isCurrent?.call() == false ||
        !_isCurrent(gateway, actor, revision) ||
        !identical(state.value, current)) {
      return false;
    }
    final next = BusinessScopeState(
      tenants: current.tenants,
      legalEntities: entities,
      branches: branches,
      tenantId: tenantId,
      legalEntityId: legalEntityId,
      branchId: branchId,
    );
    ++_selectionRevision;
    _remember(next, gateway, actor);
    state = AsyncData(next);
    return true;
  }

  Future<BusinessScopeState> _load(
    List<TenantSummary> tenants,
    String tenantId, {
    required SupabaseFoundationGateway? gateway,
    String? preferredEntityId,
    String? preferredBranchId,
  }) async {
    final entities = gateway == null
        ? _previewEntities(tenantId)
        : await gateway.listLegalEntities(tenantId);
    final legalEntityId = entities.any((item) => item.id == preferredEntityId)
        ? preferredEntityId
        : entities.firstOrNull?.id;
    final branches = legalEntityId == null
        ? const <BranchSummary>[]
        : gateway == null
        ? _previewBranches(tenantId, legalEntityId)
        : await gateway.listBranches(
            tenantId: tenantId,
            legalEntityId: legalEntityId,
          );
    return BusinessScopeState(
      tenants: tenants,
      legalEntities: entities,
      branches: branches,
      tenantId: tenantId,
      legalEntityId: legalEntityId,
      branchId: branches.any((item) => item.id == preferredBranchId)
          ? preferredBranchId
          : branches.firstOrNull?.id,
    );
  }

  static List<LegalEntitySummary> _previewEntities(String tenantId) => [
    LegalEntitySummary(
      id: 'preview-entity',
      tenantId: tenantId,
      name: 'Jentra Trading (Pvt) Ltd',
      code: 'JTPL',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ];

  static List<BranchSummary> _previewBranches(
    String tenantId,
    String legalEntityId,
  ) => [
    BranchSummary(
      id: 'preview-branch',
      tenantId: tenantId,
      legalEntityId: legalEntityId,
      name: 'Head Office',
      code: 'HQ',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
    BranchSummary(
      id: 'preview-branch-colombo',
      tenantId: tenantId,
      legalEntityId: legalEntityId,
      name: 'Colombo',
      code: 'CMB',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ];
}

final activeTenantContextProvider = Provider<TenantContext?>((ref) {
  final scopeState = ref.watch(businessScopeProvider);
  if (scopeState.isLoading || scopeState.hasError) return null;
  final scope = scopeState.value;
  if (scope == null) return null;
  final actorState = ref.watch(authenticatedActorProvider);
  if (actorState.isLoading || actorState.hasError) return null;
  final actorId = actorState.value;
  if (actorId == null) return null;
  return scope.toContext(actorId);
});

final businessCapabilitiesProvider = FutureProvider<Set<String>>((ref) async {
  final context = ref.watch(activeTenantContextProvider);
  if (context == null) return const {};
  final gateway = ref.watch(foundationGatewayProvider);
  if (gateway != null) {
    await ref.watch(authSessionRevisionProvider.future);
    return gateway.getCapabilities(context.tenantId);
  }
  return {
    // Preview navigation only; the quotation controller still requires a backend.
    'sales.quotations.view',
    for (final resource in BusinessSetupResource.values) ...{
      resource.viewPermission,
      resource.managePermission,
    },
  };
});
