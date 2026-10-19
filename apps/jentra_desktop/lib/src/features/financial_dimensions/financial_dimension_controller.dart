import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final financialDimensionGatewayProvider = Provider<FinancialDimensionGateway?>(
  (ref) => null,
);
final financialDimensionControllerProvider =
    Provider.autoDispose<FinancialDimensionController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(financialDimensionGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !{
            'finance.view',
            'finance.dimensions.manage',
          }.every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = FinancialDimensionController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class FinancialDimensionController extends ChangeNotifier {
  FinancialDimensionController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  static const slot = 'financial-dimension-editor';
  final TenantContext scope;
  final FinancialDimensionGateway gateway;
  final QuotationDraftStore drafts;
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  int _epoch = 0;
  String kind = 'cost_centre', search = '';
  String? cursor, error, message;
  List<Map<String, Object?>> items = [];
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;
  bool get pending => local?.pending != null;
  bool get locked => busy || pending || denied || !verified;
  int get version => (form['version'] as int?) ?? 0;
  bool current(int epoch) => !_disposed && online && epoch == _epoch;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  void setOnline(bool v) {
    online = v;
    if (!v) {
      _epoch++;
      verified = false;
      items = [];
      cursor = null;
    }
    emit();
  }

  Future<void> run(Future<void> Function() f) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await f();
    } catch (e) {
      if (e is DomainError &&
          {'PERMISSION_DENIED', 'MFA_REQUIRED'}.contains(e.code)) {
        _epoch++;
        denied = true;
        verified = false;
        items = [];
        cursor = null;
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'The result is uncertain. Encrypted work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> persist() async {
    await drafts.save(scope, slot, form, expectedVersion: version);
    if (!_disposed) local = await drafts.load(scope, slot);
  }

  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form ?? {};
    kind = form['kind'] as String? ?? 'cost_centre';
    if (online) await read();
  });
  Future<void> read({bool more = false}) async {
    if (!online) return;
    final epoch = _epoch;
    final r = await gateway.page(
      scope,
      kind,
      after: more ? cursor : null,
      search: search,
      activeOnly: false,
    );
    if (!current(epoch)) return;
    denied = false;
    verified = true;
    items = [
      if (more) ...items,
      ...(r['items'] as List).map((v) => (v as Map).cast<String, Object?>()),
    ];
    cursor = r['next_cursor'] as String?;
  }

  Future<void> refresh() => run(() => read());
  Future<void> more() => run(() => read(more: true));
  Future<void> filter(String k, String term) => run(() async {
    if (pending || !{'cost_centre', 'project'}.contains(k)) return;
    kind = k;
    search = term;
    items = [];
    cursor = null;
    await read();
  });
  void create() {
    if (locked) return;
    form = {
      'id': const Uuid().v4(),
      'kind': kind,
      'code': '',
      'name': '',
      'status': 'active',
      'dimension_branch_id': null,
      'reason': '',
      'version': 0,
    };
    message = null;
    emit();
  }

  Future<void> open(Map<String, Object?> row) => run(() async {
    if (pending || denied || !verified) return;
    form = {...row};
    await persist();
  });
  void field(String k, Object? v) {
    if (locked ||
        !{
          'code',
          'name',
          'status',
          'reason',
          'dimension_branch_id',
        }.contains(k)) {
      return;
    }
    if (version > 0 && {'code', 'dimension_branch_id'}.contains(k)) return;
    form = {...form, k: v};
    emit();
  }

  Future<void> saveInputs() => run(() async {
    if (!pending && !denied && form.isNotEmpty) await persist();
  });
  Future<bool> canLeave() async {
    if (busy) return false;
    if (pending || denied || form.isEmpty) return true;
    await saveInputs();
    return error == null;
  }

  Map<String, Object?> payload() => {
    for (final k in [
      'id',
      'kind',
      'code',
      'name',
      'status',
      'reason',
      'dimension_branch_id',
    ])
      k: form[k],
  };
  void validate() {
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]{0,39}$')
            .hasMatch(form['code'] as String? ?? '') ||
        (form['name'] as String? ?? '').trim().length < 2 ||
        (form['name'] as String? ?? '').length > 160 ||
        (form['reason'] as String? ?? '').trim().length < 3 ||
        (form['reason'] as String? ?? '').length > 1000 ||
        !{'active', 'retired'}.contains(form['status']) ||
        form['dimension_branch_id'] != null &&
            form['dimension_branch_id'] != scope.branchId) {
      throw const FormatException(
        'Choose a valid code, name, scope and reason.',
      );
    }
  }

  Future<void> save() => run(() async {
    if (!online || denied || !verified) return;
    final epoch = _epoch;
    var sealed = local?.pending;
    if (sealed == null) {
      validate();
      await persist();
      sealed = await drafts.prepare(
        scope,
        slot,
        verb: 'save',
        expectedVersion: version,
        payload: payload(),
      );
      if (!_disposed) local = await drafts.load(scope, slot);
    }
    if (!current(epoch)) return;
    Map<String, Object?> result;
    try {
      result = await gateway.save(sealed.envelope);
      await drafts.confirm(
        scope,
        slot,
        sealed.envelope.commandId,
        form: result,
        expectedVersion: result['version'] as int,
      );
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: sealed.envelope.commandId,
      );
      if (!_disposed) local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = result;
    if (!current(epoch)) return;
    message = 'Dimension confirmed. Original posted and approved history is preserved.';
    try {
      await read();
    } catch (e) {
      if (e is DomainError &&
          {'PERMISSION_DENIED', 'MFA_REQUIRED'}.contains(e.code)) {
        rethrow;
      }
      error = 'Dimension confirmed. Refresh the catalog to view it.';
    }
  });
}
