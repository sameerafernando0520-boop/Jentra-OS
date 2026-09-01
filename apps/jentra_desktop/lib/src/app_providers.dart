import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

final runtimeConfigProvider = Provider<RuntimeConfig>(
  (ref) => RuntimeConfig.fromEnvironment(),
);

final foundationGatewayProvider = Provider<SupabaseFoundationGateway?>(
  (ref) => null,
);

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
