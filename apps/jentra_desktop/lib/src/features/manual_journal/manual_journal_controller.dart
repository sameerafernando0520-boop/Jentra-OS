import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';

final manualJournalGatewayProvider = Provider<ManualJournalGateway?>(
  (ref) => null,
);
final manualJournalControllerProvider =
    Provider.autoDispose<ManualJournalController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(manualJournalGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('finance.view') ?? false)) {
        return null;
      }
      final c = ManualJournalController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        permissions: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class ManualJournalController extends ChangeNotifier {
  ManualJournalController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.permissions,
    required this.online,
  });
  final TenantContext scope;
  final ManualJournalGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  static const slot = 'manual-journal-editor';
  bool online, busy = false, accessDenied = false, _disposed = false;
  String? error, message, cursor;
  String baseCurrency = '';
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  List<Map<String, Object?>> items = [];
  bool get canManage => permissions.contains('finance.journals.post');
  bool get locked => busy || accessDenied || local?.pending != null;
  bool get editable => !locked && canManage && form?['status'] == 'draft';
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool v) {
    online = v;
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
      if (e is DomainError && e.code == 'PERMISSION_DENIED') {
        accessDenied = true;
        items = [];
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Encrypted work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    form = local?.form;
    if ((form?['attachment_ids'] as List? ?? []).isNotEmpty &&
        !permissions.contains('core.files.view')) {
      accessDenied = true;
    }
    if (online) await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    final r = await gateway.options(
      scope,
      'reports',
      after: more ? cursor : null,
    );
    if (accessDenied && (form?['attachment_ids'] as List? ?? []).isNotEmpty) {
      await gateway.options(scope, 'attachments');
    }
    if (_disposed) return;
    items = [
      if (more) ...items,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursor = r['next_cursor'] as String?;
    baseCurrency = r['base_currency_code'] as String? ?? '';
    accessDenied = false;
  }

  Future<void> refresh({bool more = false}) => run(() async {
    if (online) await _refresh(more: more);
  });
  Future<void> _save() async {
    if (form != null) {
      if (local?.pending != null) return;
      await drafts.save(
        scope,
        slot,
        form!,
        expectedVersion: form!['version'] as int? ?? 0,
      );
      local = await drafts.load(scope, slot);
    }
  }

  Future<void> saveLocal() => run(_save);
  Future<bool> canLeave() async {
    if (form == null) return true;
    var ok = false;
    await run(() async {
      await _save();
      ok = true;
    });
    return ok;
  }

  Future<void> create() => run(() async {
    if (!canManage || form != null || accessDenied) return;
    form = {
      'id': const Uuid().v4(),
      'status': 'draft',
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'currency_code': baseCurrency,
      'reason': '',
      'description': '',
      'lines': <Object?>[],
      'attachment_ids': <String>[],
      'attachments': <Object?>[],
    };
    await _save();
  });
  Future<void> open(String id) => run(() async {
    if (form != null || !online || accessDenied) return;
    form = await gateway.detail(scope, id);
    await _save();
  });
  Future<void> close() => run(() async {
    if (local?.pending != null) {
      throw const FormatException('Resolve the pending command first.');
    }
    await drafts.discard(scope, slot);
    form = null;
    local = null;
  });
  Future<void> openLinked(String id) => run(() async {
    if (form?['status'] != 'posted' ||
        local?.pending != null ||
        accessDenied ||
        !online) {
      return;
    }
    final detail = await gateway.detail(scope, id);
    form = detail;
    await _save();
  });
  Future<void> reverse() => run(() async {
    if (form?['status'] != 'posted' ||
        form?['reversal_of_id'] != null ||
        !permissions.contains('finance.reversals.post') ||
        local?.pending != null ||
        accessDenied) {
      return;
    }
    final original = form!;
    await drafts.discard(scope, slot);
    local = null;
    form = {
      ...original,
      'id': const Uuid().v4(),
      'version': null,
      'status': 'draft',
      'reversal_of_id': original['id'],
      'journal_entry_id': null,
      'ledger_lines': <Object?>[],
      'document_number': null,
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'reason': '',
      'description': 'Reversal: ${original['description']}',
      'lines': [
        for (final raw in original['lines'] as List)
          {...raw as Map, 'debit': raw['credit'], 'credit': raw['debit']},
      ],
      'attachment_ids': <String>[],
      'attachments': <Object?>[],
      '_dirty': true,
    };
    await _save();
  });
  void update(String key, Object? value) {
    if (!editable) return;
    form = {...form!, key: value, '_dirty': true};
    emit();
  }

  void addAccount(Map<String, Object?> account) {
    if (!editable || form?['reversal_of_id'] != null) return;
    update('lines', [
      ...form!['lines'] as List,
      {
        'line_id': const Uuid().v4(),
        'account_id': account['id'],
        'account_code': account['code'],
        'account_name': account['name'],
        'debit': '0',
        'credit': '0',
        'description': '',
        'cost_center': '',
        'project': '',
      },
    ]);
  }

  void line(int i, String key, String value) {
    if (!editable || form?['reversal_of_id'] != null) return;
    final rows = [...form!['lines'] as List];
    rows[i] = {...rows[i] as Map, key: value};
    update('lines', rows);
  }

  void removeLine(int i) {
    if (!editable || form?['reversal_of_id'] != null) return;
    final rows = [...form!['lines'] as List]..removeAt(i);
    update('lines', rows);
  }

  void attachment(Map<String, Object?> file) {
    if (!editable) return;
    final ids = [...form!['attachment_ids'] as List];
    if (ids.contains(file['id'])) return;
    form = {
      ...form!,
      'attachment_ids': [...ids, file['id']],
      'attachments': [...form!['attachments'] as List, file],
      '_dirty': true,
    };
    emit();
  }

  void removeAttachment(String id) {
    if (!editable) return;
    form = {
      ...form!,
      'attachment_ids': [
        for (final x in form!['attachment_ids'] as List)
          if (x != id) x,
      ],
      'attachments': [
        for (final x in form!['attachments'] as List)
          if ((x as Map)['id'] != id) x,
      ],
      '_dirty': true,
    };
    emit();
  }

  Future<Map<String, Object?>> options(
    String resource, {
    String? after,
    String search = '',
  }) async {
    try {
      return await gateway.options(
        scope,
        resource,
        after: after,
        search: search,
      );
    } on DomainError catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        accessDenied = true;
        items = [];
        emit();
      }
      rethrow;
    }
  }

  Future<void> act(String verb, {String note = ''}) => run(() async {
    if (!online || form == null || accessDenied) return;
    var pending = local?.pending;
    if (pending == null) {
      final f = form!;
      if (verb != 'save' && (f['_dirty'] == true || f['version'] == null)) {
        throw const FormatException('Save journal changes before this action.');
      }
      if (verb == 'save') {
        if (!canManage || f['status'] != 'draft') return;
        final date = (f['document_date'] as String? ?? '').trim(),
            parsed = DateTime.tryParse(
              (f['document_date'] as String? ?? '').trim(),
            );
        if (parsed == null ||
            parsed.toIso8601String().substring(0, 10) != date ||
            (f['reason'] as String? ?? '').trim().length < 3 ||
            (f['description'] as String? ?? '').trim().length < 3) {
          throw const FormatException(
            'Enter a valid date, description and reason.',
          );
        }
        if (f['reversal_of_id'] == null) {
          final lines = f['lines'] as List;
          var deb = BigInt.zero, cred = BigInt.zero;
          if (lines.length < 2 || lines.length > 200) {
            throw const FormatException('Use 2–200 journal lines.');
          }
          for (final raw in lines) {
            final l = raw as Map,
                a = SupabaseManualJournalGateway.decimal(l['debit']),
                b = SupabaseManualJournalGateway.decimal(l['credit']);
            if ((a > BigInt.zero) == (b > BigInt.zero)) {
              throw const FormatException(
                'Enter either a positive debit or credit per line.',
              );
            }
            deb += a;
            cred += b;
          }
          if (deb != cred) {
            throw const FormatException(
              'Debits and credits must balance exactly.',
            );
          }
        }
      } else if (['approve', 'reject'].contains(verb)) {
        if (!permissions.contains('workflow.approvals.decide')) return;
      } else if (!canManage) {
        return;
      }
      if (['recall', 'cancel', 'reject'].contains(verb) &&
          note.trim().length < 3) {
        throw const FormatException('Enter a reason.');
      }
      final payload = verb == 'save'
          ? <String, Object?>{
              for (final k in [
                'id',
                'document_date',
                'description',
                'reason',
                'currency_code',
                'exchange_rate_id',
                'reversal_of_id',
                'lines',
                'attachment_ids',
              ])
                k: f[k],
            }
          : <String, Object?>{
              'document_id': f['id'],
              if (['approve', 'reject'].contains(verb))
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
        expectedVersion: f['version'] as int? ?? 0,
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
    message = 'Journal action confirmed.';
    try {
      await _save();
      if (result['status'] == 'posted') {
        form = await gateway.detail(scope, result['id'] as String);
        await _save();
      }
      await _refresh();
    } catch (e) {
      if (e is DomainError && e.code == 'PERMISSION_DENIED') {
        accessDenied = true;
        items = [];
      }
      error =
          'Action confirmed. Retry saving locally or refreshing before leaving.';
    }
  });
}
