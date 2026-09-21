import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';

final stockCountGatewayProvider = Provider<StockCountGateway?>((ref) => null);
final stockCountControllerProvider =
    Provider.autoDispose<StockCountController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(stockCountGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final permissions = caps.value ?? <String>{};
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !permissions.contains('inventory.cost.view') ||
          ![
            'inventory.adjustments.post',
            'workflow.approvals.decide',
          ].any(permissions.contains)) {
        return null;
      }
      final c = StockCountController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        permissions: permissions,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class StockCountController extends ChangeNotifier {
  StockCountController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    required this.permissions,
  });
  final TenantContext scope;
  final StockCountGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  static const slot = 'stock-count-editor';
  bool online, busy = false, _disposed = false;
  String? error, message, cursor;
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  List<Map<String, Object?>> items = [];
  bool get locked => busy || _disposed || local?.pending != null;
  bool get canManage => permissions.contains('inventory.adjustments.post');
  bool get editable => !locked && canManage && (form?['status'] == 'draft');
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    emit();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Saved work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form;
    if (online) await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    final r = await gateway.page(scope, after: more ? cursor : null);
    if (_disposed) return;
    items = [
      if (more) ...items,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursor = r['next_cursor'] as String?;
  }

  Future<void> refresh({bool more = false}) => run(() async {
    if (online) await _refresh(more: more);
  });
  Future<void> create() => run(() async {
    if (!canManage || form != null) return;
    form = {
      'id': const Uuid().v4(),
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'status': 'draft',
      'reason': '',
      'lines': <Map<String, Object?>>[],
    };
    await _save();
  });
  Future<void> open(Map<String, Object?> row) => run(() async {
    if (form != null) return;
    if (row['lines'] is! List && !online) {
      throw const FormatException(
        'Connect to load the selected count. Local drafts remain available offline.',
      );
    }
    final detail = row['lines'] is List
        ? row
        : await gateway.detail(scope, row['id'] as String);
    if (_disposed) return;
    form = {...detail};
    await _save();
  });
  Future<void> correct() => run(() async {
    final original = form;
    if (!canManage ||
        original?['status'] != 'posted' ||
        local?.pending != null) {
      return;
    }
    await drafts.discard(scope, slot);
    form = {
      'id': const Uuid().v4(),
      'corrects_count_id': original!['id'],
      'warehouse_id': original['warehouse_id'],
      'warehouse_name': original['warehouse_name'],
      'offset_account_id': original['offset_account_id'],
      'offset_account_name': original['offset_account_name'],
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'status': 'draft',
      'reason': '',
      'lines': [
        for (final raw in original['lines'] as List)
          {
            'line_id': const Uuid().v4(),
            'product_id': (raw as Map)['product_id'],
            'product_name': raw['product_name'],
            'counted_quantity': raw['counted_quantity'],
            'empty_unit_cost': raw['empty_unit_cost'],
          },
      ],
    };
    local = null;
    await _save();
  });
  Future<void> _save() async {
    if (_disposed || form == null) return;
    await drafts.save(
      scope,
      slot,
      form!,
      expectedVersion: form!['version'] as int?,
    );
    local = await drafts.load(scope, slot);
  }

  Future<void> saveLocal() => run(_save);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (form == null || local?.pending != null) return true;
    var ok = false;
    await run(() async {
      await _save();
      ok = true;
    });
    return ok;
  }

  void update(String key, Object? value) {
    if (!editable) return;
    form = {...form!, key: value, '_dirty': true};
    emit();
  }

  void updateLine(int i, String key, Object? value) {
    if (!editable || form?['version'] == null) return;
    final lines = [...form!['lines'] as List];
    lines[i] = {...lines[i] as Map, key: value};
    update('lines', lines);
  }

  void addProduct(Map<String, Object?> p) {
    if (!editable || form?['version'] != null) return;
    if ((form!['lines'] as List).any(
      (l) => (l as Map)['product_id'] == p['id'],
    )) {
      return;
    }
    update('lines', [
      ...form!['lines'] as List,
      {
        'line_id': const Uuid().v4(),
        'product_id': p['id'],
        'product_name': p['name'],
        'counted_quantity': p['on_hand_quantity'],
        'empty_unit_cost': '0',
      },
    ]);
  }

  void updateIdentity(int lineIndex, int identityIndex, String value) {
    if (!editable || form?['version'] == null) return;
    final lines = [...form!['lines'] as List];
    final line = {...lines[lineIndex] as Map};
    final identities = [...line['identities'] as List];
    identities[identityIndex] = {
      ...identities[identityIndex] as Map,
      'counted_quantity': value,
    };
    line['identities'] = identities;
    try {
      line['counted_quantity'] = stockCountIdentityTotal(
        identities.cast<Map>(),
        serial: line['tracking_mode'] == 'serial',
      );
    } on FormatException {
      line['counted_quantity'] = '';
    }
    lines[lineIndex] = line;
    update('lines', lines);
  }

  Future<void> close() => run(() async {
    if (local?.pending != null) {
      throw const FormatException('Resolve the pending command first.');
    }
    await drafts.discard(scope, slot);
    form = null;
    local = null;
  });
  Future<void> act(String verb, {String note = ''}) => run(() async {
    if (!online || form == null) return;
    var pending = local?.pending;
    if (pending == null) {
      final f = form!;
      if (verb != 'save' && (f['_dirty'] == true || f['version'] == null)) {
        throw const FormatException(
          'Save the count changes before submitting another action.',
        );
      }
      if (verb == 'save') {
        if (!canManage || f['status'] != 'draft') return;
        final date = f['document_date'] as String? ?? '';
        final parsed = DateTime.tryParse(date);
        if (parsed == null ||
            parsed.toIso8601String().substring(0, 10) != date) {
          throw const FormatException('Enter a valid YYYY-MM-DD date.');
        }
        if ((f['reason'] as String? ?? '').trim().length < 3 ||
            f['warehouse_id'] == null ||
            f['offset_account_id'] == null ||
            (f['lines'] as List).isEmpty) {
          throw const FormatException(
            'Select warehouse, variance account and products; enter a reason.',
          );
        }
        for (final raw in f['lines'] as List) {
          final l = raw as Map;
          if (l['identities'] is List) {
            stockCountIdentityTotal(
              (l['identities'] as List).cast<Map>(),
              serial: l['tracking_mode'] == 'serial',
            );
          }
          for (final key in ['counted_quantity', 'empty_unit_cost']) {
            final value = l[key];
            if (value is! String ||
                !RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(value)) {
              throw const FormatException(
                'Use nonnegative decimal strings with at most six decimal places.',
              );
            }
          }
        }
      } else if (verb == 'approve' || verb == 'reject') {
        if (!permissions.contains('workflow.approvals.decide')) return;
      } else if (!canManage) {
        return;
      }
      if (['recall', 'cancel', 'reject'].contains(verb) &&
          note.trim().isEmpty) {
        throw const FormatException('Enter a reason for this action.');
      }
      final payload = verb == 'save'
          ? <String, Object?>{
              for (final key in [
                'id',
                'document_date',
                'reason',
                'warehouse_id',
                'offset_account_id',
                'corrects_count_id',
              ])
                key: f[key],
              'capture_only': f['version'] == null,
              'lines': [
                for (final raw in f['lines'] as List)
                  {
                    for (final key in [
                      'line_id',
                      'product_id',
                      'counted_quantity',
                      'empty_unit_cost',
                    ])
                      key: (raw as Map)[key],
                    if ((raw as Map)['identities'] is List)
                      'identities': [
                        for (final identity in raw['identities'] as List)
                          {
                            'id': (identity as Map)['id'],
                            'counted_quantity': identity['counted_quantity'],
                          },
                      ],
                  },
              ],
            }
          : <String, Object?>{
              'document_id': f['id'],
              if (verb == 'approve' || verb == 'reject')
                'decision': verb == 'approve' ? 'approved' : 'rejected'
              else if (verb != 'post')
                'action': verb,
              'reason': note,
              'note': note,
            };
      await _save();
      pending = await drafts.prepare(
        scope,
        slot,
        verb: verb == 'post' ? 'accept' : verb,
        payload: payload,
        expectedVersion: f['version'] as int?,
      );
      local = await drafts.load(scope, slot);
    }
    Map<String, Object?> result;
    try {
      result = await gateway.execute(
        pending.verb == 'accept' ? 'post' : pending.verb,
        pending.envelope,
      );
      await drafts.complete(scope, slot, pending.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    form = result;
    local = null;
    message = 'Count action confirmed.';
    // The server receipt is authoritative even if local persistence or refresh fails.
    try {
      await _save();
      await _refresh();
    } catch (_) {
      error = 'Action confirmed. Retry local save or refresh before leaving.';
    }
  });
}
