import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_asset_equipment.dart';
import 'package:jentra_platform/jentra_asset_equipment_platform.dart';

import '../../app_providers.dart';
import 'service_controller.dart';

final assetEquipmentRepositoryProvider = Provider<AssetEquipmentRepository?>(
  (ref) => null,
);
final assetEquipmentControllerProvider =
    Provider.autoDispose<AssetEquipmentController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          repo = ref.watch(assetEquipmentRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          repo == null ||
          caps.isLoading ||
          caps.hasError ||
          !{
            'service.view',
            'service.configure',
            'assets.view',
          }.every(caps.value!.contains)) {
        return null;
      }
      final draft = ScopedCommandDraftStore(
        ref.watch(encryptedDraftRepositoryProvider),
        entityType: 'service.asset_equipment.command',
        fields: AssetEquipmentCommands.fields,
        validate: AssetEquipmentCommands.validate,
        definiteFailures: {...serviceDefiniteFailures, 'STATE_CONFLICT'},
      );
      final c = AssetEquipmentController(
        scope: scope,
        repository: repo,
        draft: draft,
        permissions: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, state) =>
            c.service.setOnline(state.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class AssetEquipmentController extends ChangeNotifier {
  AssetEquipmentController({
    required TenantContext scope,
    required this.repository,
    required ScopedCommandDraftStore draft,
    required Set<String> permissions,
    required bool online,
    bool monitor = true,
  }) : service = ServiceController(
         scope: scope,
         repository: repository,
         drafts: {'equipment': draft},
         permissions: permissions,
         online: online,
         monitor: monitor,
       ) {
    service.kind = ServiceKind.equipment;
    service.addListener(_changed);
  }
  final AssetEquipmentRepository repository;
  final ServiceController service;
  List<AssetEquipmentSource> sources = [];
  String? next, error;
  AssetEquipmentSource? selected;
  AssetEquipmentLink? history;
  bool busy = false, _disposed = false;
  bool sourcesLoaded = false;
  bool get valid => !_disposed && service.current && service.online;
  int? _sourceEpoch, _sourceForm;
  void _changed() {
    if (!valid ||
        _sourceEpoch != service.accessEpoch ||
        _sourceForm != service.formEpoch) {
      sources = [];
      next = null;
      selected = null;
      history = null;
      sourcesLoaded = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    await service.initialize();
  }

  Future<void> begin() async {
    if (await service.begin('equipment')) {
      service.edit('kind', 'asset');
      service.edit('customer_id', null);
      service.edit('provider_id', null);
      _sourceEpoch = service.accessEpoch;
      _sourceForm = service.formEpoch;
      error = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadSources({bool more = false}) async {
    if (!valid || busy || service.form == null) return;
    final n = service.accessEpoch, f = service.formEpoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await repository.authorize(service.scope, 'service.configure');
      if (!valid || n != service.accessEpoch || f != service.formEpoch) return;
      final page = await repository.sources(
        service.scope,
        after: more ? next : null,
      );
      if (valid && n == service.accessEpoch && f == service.formEpoch) {
        sources = more ? [...sources, ...page.items] : page.items;
        next = page.nextCursor;
        _sourceEpoch = n;
        _sourceForm = f;
        sourcesLoaded = true;
      }
    } catch (e) {
      if (valid && n == service.accessEpoch && f == service.formEpoch) {
        error = e is DomainError
            ? e.message
            : 'The exact asset source could not be read.';
        await service.checkAccess();
      }
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void choose(AssetEquipmentSource source) {
    if (!valid ||
        service.locked ||
        _sourceEpoch != service.accessEpoch ||
        _sourceForm != service.formEpoch ||
        !sources.any((s) => identical(s, source))) {
      return;
    }
    selected = source;
    service.edit('provider_id', source.id);
    service.edit('provider_version', source.version);
    service.edit('provider_digest', source.digest);
    if ((service.form?['name'] as String? ?? '').isEmpty) {
      service.edit('name', source.name);
    }
    if ((service.form?['identity'] as String? ?? '').isEmpty) {
      service.edit('identity', source.code);
    }
    notifyListeners();
  }

  Future<void> inspect(String id) async {
    if (!valid || busy) return;
    final n = service.accessEpoch;
    busy = true;
    notifyListeners();
    try {
      final r = await repository.link(service.scope, id);
      if (valid && n == service.accessEpoch) history = r;
    } catch (e) {
      if (valid && n == service.accessEpoch) {
        error = e is DomainError
            ? e.message
            : 'The immutable link could not be read.';
        await service.checkAccess();
      }
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    service.removeListener(_changed);
    service.dispose();
    sources = [];
    selected = null;
    history = null;
    super.dispose();
  }
}
