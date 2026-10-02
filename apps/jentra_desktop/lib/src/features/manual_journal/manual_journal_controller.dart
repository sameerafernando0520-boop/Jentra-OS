import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';

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

final class ManualJournalController extends ChangeNotifier
    implements OperationalReadAccess {
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
  int _epoch = 0;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) =>
      !_disposed && online && !accessDenied && epoch == _epoch;
  @override
  void denyReadAccess() {
    if (_disposed) return;
    accessDenied = true;
    _epoch++;
    clearReadEvidence();
    emit();
  }

  void clearReadEvidence() {
    items = [];
    cursor = null;
    baseCurrency = '';
    if (form != null) {
      form = form!['status'] == 'posted' ? null : recoveryForm(form!);
    }
  }

  static Map<String, Object?> recoveryForm(Map<String, Object?> source) => {
    for (final key in [
      'id',
      'status',
      'version',
      'document_date',
      'description',
      'reason',
      'currency_code',
      'exchange_rate_id',
      'reversal_of_id',
      'attachment_ids',
      '_dirty',
    ])
      if (source.containsKey(key)) key: source[key],
    'attachment_ids': source['attachment_ids'] ?? <String>[],
    'attachments': <Object?>[],
    'lines': [
      if (source['status'] != 'posted' && source['reversal_of_id'] == null)
        for (final raw in source['lines'] as List? ?? [])
          {
            for (final key in [
              'line_id',
              'account_id',
              'account_code',
              'account_name',
              'debit',
              'credit',
              'description',
              'cost_center',
              'project',
              'cost_centre_id',
              'project_id',
              'dimension_snapshot',
              'is_tax_control',
              'tax_control_movement',
              'tax_definition_id',
              'tax_definition_version',
              'tax_code',
              'tax_kind',
              'tax_rate',
              'tax_inclusive',
              'tax_rounding_scale',
              'taxable_amount',
            ])
              if ((raw as Map).containsKey(key)) key: raw[key],
          },
    ],
  };
  String? error, message, cursor;
  String baseCurrency = '';
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  List<Map<String, Object?>> items = [];
  bool get canManage => permissions.contains('finance.journals.post');
  bool get locked =>
      _disposed || busy || accessDenied || local?.pending != null;
  bool get editable => !locked && canManage && form?['status'] == 'draft';
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clearReadEvidence();
    notifyListeners();
    super.dispose();
  }

  void setOnline(bool v) {
    if (online != v) {
      online = v;
      _epoch++;
      clearReadEvidence();
    }
    emit();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        denyReadAccess();
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
    final epoch = _epoch;
    final recovered = await drafts.load(scope, slot);
    if (_disposed || epoch != _epoch) return;
    local = recovered;
    form = local == null ? null : recoveryForm(local!.form);
    if ((form?['attachment_ids'] as List? ?? []).isNotEmpty &&
        !permissions.contains('core.files.view')) {
      accessDenied = true;
    }
    if (online) {
      await _refresh();
      if (currentRead(epoch) && form?['status'] == 'posted') {
        final detail = await gateway.detail(scope, form!['id'] as String);
        if (currentRead(epoch)) form = detail;
      }
    } else if (form?['status'] == 'posted') {
      form = null;
    }
  });
  Future<void> _refresh({bool more = false}) async {
    if (!online || _disposed) return;
    final epoch = _epoch;
    final r = await gateway.options(
      scope,
      'reports',
      after: more ? cursor : null,
    );
    if (_disposed || !online || epoch != _epoch) return;
    if (accessDenied && (form?['attachment_ids'] as List? ?? []).isNotEmpty) {
      await gateway.options(scope, 'attachments');
    }
    if (_disposed || !online || epoch != _epoch) return;
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
      final epoch = _epoch;
      final input = recoveryForm(form!);
      final version = form!['version'] as int? ?? 0;
      await drafts.save(scope, slot, input, expectedVersion: version);
      final saved = await drafts.load(scope, slot);
      if (!_disposed && epoch == _epoch) local = saved;
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
    final epoch = _epoch;
    final detail = await gateway.detail(scope, id);
    if (!currentRead(epoch)) return;
    form = detail;
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
    final epoch = _epoch;
    final detail = await gateway.detail(scope, id);
    if (!currentRead(epoch)) return;
    form = detail;
    await _save();
  });
  Future<void> reverse() => run(() async {
    if (form?['status'] != 'posted' ||
        form?['reversal_of_id'] != null ||
        !permissions.contains('finance.reversals.post') ||
        local?.pending != null ||
        accessDenied ||
        !online) {
      return;
    }
    final epoch = _epoch;
    final original = form!;
    await drafts.discard(scope, slot);
    if (!currentRead(epoch)) return;
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
        if (account['is_tax_control'] == true) 'is_tax_control': true,
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

  void financialDimension(
    int index,
    String kind,
    Map<String, Object?>? choice,
  ) {
    if (!editable ||
        !online ||
        _disposed ||
        form?['reversal_of_id'] != null ||
        !{'cost_centre', 'project'}.contains(kind)) {
      return;
    }
    if (choice != null &&
        (choice['status'] != 'active' ||
            choice['kind'] != kind ||
            choice['tenant_id'] != scope.tenantId ||
            choice['legal_entity_id'] != scope.legalEntityId ||
            choice['dimension_branch_id'] != null &&
                choice['dimension_branch_id'] != scope.branchId)) {
      return;
    }
    final rows = [...form!['lines'] as List];
    if (index < 0 || index >= rows.length) return;
    final row = (rows[index] as Map).cast<String, Object?>();
    final basis = {...(row['dimension_snapshot'] as Map? ?? {})}..remove(kind);
    if (choice != null) {
      basis[kind] = {
        for (final k in [
          'id',
          'tenant_id',
          'legal_entity_id',
          'kind',
          'version',
          'code',
          'name',
        ])
          k: choice[k],
        'branch_id': choice['dimension_branch_id'],
      };
    }
    rows[index] = {
      ...row,
      '${kind}_id': choice?['id'],
      'dimension_snapshot': basis.isEmpty ? null : basis,
      kind == 'cost_centre' ? 'cost_center' : 'project': choice == null
          ? ''
          : "${choice['code']} · ${choice['name']}",
    };
    update('lines', rows);
  }

  void taxDefinition(int i, Map<String, Object?>? definition) {
    if (!editable || form?['reversal_of_id'] != null) return;
    final rows = [...form!['lines'] as List];
    final row = (rows[i] as Map).cast<String, Object?>();
    rows[i] = {
      for (final entry in row.entries)
        if (!entry.key.startsWith('tax_') &&
            entry.key != 'taxable_amount' &&
            entry.key != 'expected_tax_base')
          entry.key: entry.value,
      if (definition != null) ...{
        'tax_definition_id': definition['id'],
        'tax_definition_version': definition['version'],
        'tax_code': definition['code'],
        'tax_kind': definition['kind'],
        'tax_rate': definition['rate'],
        'tax_inclusive': definition['inclusive'],
        'tax_rounding_scale': definition['rounding_scale'],
        'taxable_amount': row['taxable_amount'] ?? '',
      },
    };
    update('lines', rows);
  }

  void taxControlMovement(int i, String? movement) {
    if (!editable || form?['reversal_of_id'] != null) return;
    final rows = [...form!['lines'] as List];
    final row = (rows[i] as Map).cast<String, Object?>();
    if (row['is_tax_control'] != true ||
        movement != null &&
            !const [
              'settlement',
              'adjustment',
              'transfer',
            ].contains(movement)) {
      return;
    }
    rows[i] = {
      for (final entry in row.entries)
        if (!entry.key.startsWith('tax_') &&
            entry.key != 'taxable_amount' &&
            entry.key != 'expected_tax_base')
          entry.key: entry.value,
      'tax_control_movement': ?movement,
    };
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
    final epoch = _epoch;
    if (!currentRead(epoch)) {
      throw const DomainError(
        code: 'ACCESS_DENIED',
        message: 'Recheck current journal access.',
      );
    }
    try {
      final result = await gateway.options(
        scope,
        resource,
        after: after,
        search: search,
        documentDate: resource == 'taxes'
            ? (form?['document_date'] as String?)
            : null,
      );
      if (!currentRead(epoch)) {
        throw const DomainError(
          code: 'ACCESS_DENIED',
          message: 'Journal access changed. Reopen the selector.',
        );
      }
      if (resource != 'taxes') return result;
      return {
        ...result,
        'items': [
          for (final row in result['items'] as List)
            {...row as Map, 'rounding_scale': result['rounding_scale']},
        ],
      };
    } on DomainError catch (e) {
      if (currentRead(epoch) &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        denyReadAccess();
      }
      rethrow;
    }
  }

  Future<void> act(String verb, {String note = ''}) => run(() async {
    if (!online || form == null || accessDenied) return;
    final epoch = _epoch;
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
            if (l['tax_control_movement'] != null &&
                (l['is_tax_control'] != true ||
                    l['tax_definition_id'] != null ||
                    !const [
                      'settlement',
                      'adjustment',
                      'transfer',
                    ].contains(l['tax_control_movement']))) {
              throw const FormatException(
                'Choose a governed movement on a proven tax-control account.',
              );
            }
            if (l['tax_definition_id'] != null) {
              final basis = SupabaseManualJournalGateway.decimal(
                l['taxable_amount'],
              );
              final rate = SupabaseManualJournalGateway.decimal(l['tax_rate']);
              final scale = l['tax_rounding_scale'];
              if (scale is! int ||
                  scale < 0 ||
                  scale > 6 ||
                  basis <= BigInt.zero ||
                  rate <= BigInt.zero ||
                  rate > BigInt.from(100000000)) {
                throw const FormatException(
                  'Select an effective tax definition and enter its taxable basis.',
                );
              }
              final divisor = BigInt.from(10).pow(14 - scale);
              final tax = (basis * rate + divisor ~/ BigInt.two) ~/ divisor;
              if (tax * BigInt.from(10).pow(6 - scale) != (a - b).abs() ||
                  (a - b).sign != (l['tax_kind'] == 'input' ? 1 : -1)) {
                throw const FormatException(
                  'Tax amount and debit or credit must match the selected treatment and exact taxable basis.',
                );
              }
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
      final sealed = await drafts.load(scope, slot);
      if (currentRead(epoch)) local = sealed;
    }
    if (!currentRead(epoch)) return;
    Map<String, Object?> result;
    try {
      result = await gateway.execute(
        pending.verb == 'accept' ? 'post' : pending.verb,
        pending.envelope,
      );
      await drafts.confirm(
        scope,
        slot,
        pending.envelope.commandId,
        form: recoveryForm(result),
        expectedVersion: result['version'] as int?,
      );
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      final retained = await drafts.load(scope, slot);
      if (currentRead(epoch)) local = retained;
      rethrow;
    }
    if (_disposed) return;
    final confirmed = await drafts.load(scope, slot);
    // This exact command is durably acknowledged. Keep stale presentation from
    // restoring private input/result evidence while clearing its obsolete retry.
    if (local?.pending?.envelope.commandId == pending.envelope.commandId) {
      local = null;
    }
    if (!currentRead(epoch)) {
      return;
    }
    local = confirmed;
    form = result;
    message = 'Journal action confirmed.';
    try {
      await _save();
      if (result['status'] == 'posted') {
        final detail = await gateway.detail(scope, result['id'] as String);
        if (!currentRead(epoch)) return;
        form = detail;
        await _save();
      }
      if (currentRead(epoch)) await _refresh();
    } catch (e) {
      if (!currentRead(epoch)) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        denyReadAccess();
      }
      error =
          e is DomainError && (isLocalDraftStorageFailure(e) || accessDenied)
          ? e.message
          : 'Action confirmed. Retry saving locally or refreshing before leaving.';
    }
  });
}
