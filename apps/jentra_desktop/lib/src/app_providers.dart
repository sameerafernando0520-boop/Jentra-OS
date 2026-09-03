import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

final runtimeConfigProvider = Provider<RuntimeConfig>(
  (ref) => RuntimeConfig.fromEnvironment(),
);

final foundationGatewayProvider = Provider<SupabaseFoundationGateway?>(
  (ref) => null,
);

final businessSetupGatewayProvider = Provider<SupabaseBusinessSetupGateway?>(
  (ref) => null,
);

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
    if (gateway.currentUser == null) return const [];
    return gateway.listMyTenants();
  }

  Future<void> createTenant({
    required String name,
    required String slug,
    required String legalEntityName,
    required String legalEntityCode,
    required String branchName,
    required String branchCode,
  }) async {
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await gateway.bootstrapTenant(
        name: name,
        slug: slug,
        legalEntityName: legalEntityName,
        legalEntityCode: legalEntityCode,
        branchName: branchName,
        branchCode: branchCode,
      );
      return gateway.listMyTenants();
    });
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
  @override
  Future<BusinessScopeState> build() async {
    final tenants = await ref.watch(tenantListProvider.future);
    if (tenants.isEmpty) {
      throw StateError('Create or join a business before selecting a scope.');
    }
    return _load(tenants, tenants.first.id);
  }

  Future<void> selectTenant(String tenantId) async {
    final current = state.value;
    if (current == null || current.tenantId == tenantId) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(current.tenants, tenantId));
  }

  Future<void> selectLegalEntity(String legalEntityId) async {
    final current = state.value;
    if (current == null || current.legalEntityId == legalEntityId) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final gateway = ref.read(foundationGatewayProvider);
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
  }

  void selectBranch(String branchId) {
    final current = state.value;
    if (current == null || current.branchId == branchId) return;
    state = AsyncData(
      BusinessScopeState(
        tenants: current.tenants,
        legalEntities: current.legalEntities,
        branches: current.branches,
        tenantId: current.tenantId,
        legalEntityId: current.legalEntityId,
        branchId: branchId,
      ),
    );
  }

  Future<BusinessScopeState> _load(
    List<TenantSummary> tenants,
    String tenantId,
  ) async {
    final gateway = ref.read(foundationGatewayProvider);
    final entities = gateway == null
        ? _previewEntities(tenantId)
        : await gateway.listLegalEntities(tenantId);
    final legalEntityId = entities.firstOrNull?.id;
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
      branchId: branches.firstOrNull?.id,
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
  final scope = ref.watch(businessScopeProvider).value;
  if (scope == null) return null;
  final actorId =
      ref.watch(foundationGatewayProvider)?.currentUser?.id ?? 'preview-actor';
  return scope.toContext(actorId);
});

final businessCapabilitiesProvider = FutureProvider<Set<String>>((ref) async {
  final context = ref.watch(activeTenantContextProvider);
  if (context == null) return const {};
  final gateway = ref.watch(foundationGatewayProvider);
  if (gateway != null) return gateway.getCapabilities(context.tenantId);
  return {
    for (final resource in BusinessSetupResource.values) ...{
      resource.viewPermission,
      resource.managePermission,
    },
  };
});
