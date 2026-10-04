import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'payroll_controller.dart';

final payrollCorrectionRepositoryProvider =
    Provider<PayrollCorrectionRepository?>((ref) {
      final base = ref.watch(payrollRepositoryProvider);
      return base is SupabasePayrollGateway
          ? SupabasePayrollCorrectionGateway(base.client)
          : null;
    });
final payrollCorrectionControllerProvider =
    Provider.autoDispose<PayrollCorrectionController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          repo = ref.watch(payrollCorrectionRepositoryProvider),
          base = ref.watch(payrollRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          repo == null ||
          base == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('people.payroll.view') ?? false)) {
        return null;
      }
      final c = PayrollCorrectionController(
        scope: scope,
        repository: repo,
        base: base,
        drafts: SensitivePayrollCorrectionDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
          repo.authorize,
        ),
        permissions: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, next) => c.online = next.value == ConnectivityState.online,
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class PayrollCorrectionController extends ChangeNotifier {
  PayrollCorrectionController({
    required this.scope,
    required this.repository,
    required this.base,
    required this.drafts,
    required this.permissions,
    required this.online,
    bool monitor = true,
  }) {
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final PayrollCorrectionRepository repository;
  final PayrollRepository base;
  final SensitivePayrollCorrectionDraftStore drafts;
  final Set<String> permissions;
  static const _uuid = Uuid();
  Timer? _timer;
  bool busy = false, online, denied = false, _disposed = false;
  int _epoch = 0, expectedVersion = 0;
  String? error, message, cursor, originalCursor, sourceCursor;
  List<Map<String, Object?>> rows = [],
      originals = [],
      sources = [],
      banks = [];
  List<SensitivePayrollCorrectionRecovery> recovery = [];
  final creditChoices = <String, List<Map<String, Object?>>>{};
  final creditCursors = <String, String?>{};
  Map<String, Object?>? selected, detail, original, form, confirmed, comparison;
  SensitivePayrollCorrectionDraft? local;
  PayrollCorrectionCommandKind kind = PayrollCorrectionCommandKind.correction;
  bool get locked => busy || local?.pending != null || confirmed != null;
  bool has(String cap) => permissions.contains(cap);
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';
  String get action => form?['action'] as String? ?? '';
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _clear();
    super.dispose();
  }

  void _clear() {
    creditChoices.clear();
    creditCursors.clear();
    rows = [];
    originals = [];
    sources = [];
    banks = [];
    recovery = [];
    selected = null;
    detail = null;
    original = null;
    form = null;
    local = null;
    confirmed = null;
    comparison = null;
  }

  Future<void> _run(Future<void> Function(int) work) async {
    if (busy || _disposed || denied) {
      return;
    }
    busy = true;
    error = null;
    final epoch = _epoch;
    _notify();
    try {
      await work(epoch);
    } on DomainError catch (e) {
      if ({
        'PERMISSION_DENIED',
        'AUTHENTICATION_REQUIRED',
        'FEATURE_NOT_ENTITLED',
      }.contains(e.code)) {
        denied = true;
        _epoch++;
        _clear();
      }
      error = e.message;
    } catch (_) {
      error = 'Payroll correction data could not be verified. Retry the current scope.';
    } finally {
      busy = false;
      _notify();
    }
  }

  bool _current(int epoch) => !_disposed && !denied && epoch == _epoch;
  Future<void> checkAccess() async {
    if (busy || _disposed || denied) {
      return;
    }
    final epoch = _epoch;
    if (local != null && !local!.expiresAt.isAfter(drafts.clock())) {
      form = null;
      local = null;
      confirmed = null;
      comparison = null;
      original = null;
      sources = [];
      banks = [];
      creditChoices.clear();
      creditCursors.clear();
      message = 'Private correction fields expired. Resolve its encrypted minimal receipt.';
      try {
        final saved = await drafts.recovery(scope);
        if (!_current(epoch)) {
          return;
        }
        recovery = saved;
      } catch (_) {}
      _notify();
    }
    try {
      await repository.authorize(scope, 'people.payroll.view');
    } catch (_) {
      if (_current(epoch)) {
        denied = true;
        _epoch++;
        _clear();
        _notify();
      }
    }
  }

  Future<void> initialize() => _run((e) async {
    final page = await repository.corrections(scope);
    if (!_current(e)) {
      return;
    }
    rows = page.items;
    cursor = page.nextCursor;
    final saved = await drafts.recovery(scope);
    if (_current(e)) {
      recovery = saved;
    }
  });
  Future<void> refresh({bool more = false}) => _run((e) async {
    final page = await repository.corrections(
      scope,
      after: more ? cursor : null,
    );
    if (!_current(e)) {
      return;
    }
    rows = [if (more) ...rows, ...page.items];
    cursor = page.nextCursor;
  });
  Future<void> credits(String sourceRevision, {bool more = false}) => _run((
    e,
  ) async {
    final page = await repository.correctionCredits(
      scope,
      sourceRevision,
      after: more ? creditCursors[sourceRevision] : null,
    );
    if (!_current(e)) {
      return;
    }
    creditChoices[sourceRevision] = [
      if (more)
        ...(creditChoices[sourceRevision] ?? const <Map<String, Object?>>[]),
      ...page.items,
    ];
    creditCursors[sourceRevision] = page.nextCursor;
  });
  Future<void> open(
    Map<String, Object?> row,
    String section, {
    bool more = false,
  }) => _run((e) async {
    final data = await repository.correctionDetail(
      scope,
      row['id'] as String,
      section,
      after: more ? (detail?['next_cursor'] as String?) : null,
    );
    if (!_current(e)) {
      return;
    }
    selected = workforceMap(data['correction']);
    detail = {
      ...data,
      'items': [
        if (more) ...(detail!['items'] as List),
        ...(data['items'] as List),
      ],
    };
  });
  Future<void> beginPrepare({bool more = false}) => _run((e) async {
    if (!has('people.payroll.correction.prepare')) {
      return;
    }
    if (local?.pending != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve the saved correction first.',
      );
    }
    final page = await repository.correctionOriginals(
      scope,
      after: more ? originalCursor : null,
    );
    if (!_current(e)) {
      return;
    }
    originals = [if (more) ...originals, ...page.items];
    originalCursor = page.nextCursor;
    if (more) {
      return;
    }
    form = {
      'action': 'prepare',
      'id': _uuid.v4(),
      'original_calculation_id': null,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      'replacements': <Map<String, Object?>>[],
      'reason': '',
    };
    expectedVersion = 0;
    kind = PayrollCorrectionCommandKind.correction;
    confirmed = null;
    local = null;
  });
  Future<void> selectOriginal(Map<String, Object?> row, {bool more = false}) =>
      _run((e) async {
        if (local?.pending != null || confirmed != null) {
          return;
        }
        final page = await repository.correctionSources(
          scope,
          row['id'] as String,
          after: more ? sourceCursor : null,
        );
        if (!_current(e)) {
          return;
        }
        original = row;
        sources = [if (more) ...sources, ...page.items];
        sourceCursor = page.nextCursor;
        if (!more) {
          form = {
            ...form!,
            'original_calculation_id': row['id'],
            'posting_date': row['end_date_exclusive'],
            'replacements': <Map<String, Object?>>[],
          };
        }
      });
  void replaceSource(
    Map<String, Object?> source,
    int seconds, {
    Map<String, Object?>? impact,
  }) {
    if (locked || action != 'prepare') {
      return;
    }
    final replacements = (form!['replacements'] as List)
        .map(workforceMap)
        .where((r) => r['seal_id'] != source['seal_id'])
        .toList();
    replacements.add({
      'seal_id': source['seal_id'],
      'before_revision_id': source['revision_id'],
      'expected_version': source['version'],
      'paid_seconds': seconds,
      'impact': ?impact,
    });
    form = {...form!, 'replacements': replacements};
    _notify();
  }

  void update(String key, Object? value) {
    if (locked ||
        form == null ||
        {
          'id',
          'action',
          'digest',
          'correction_id',
          'original_calculation_id',
        }.contains(key)) {
      return;
    }
    form = {...form!, key: value};
    _notify();
  }

  Future<void> beginAction(String action, {Map<String, Object?>? settlement}) =>
      _run((e) async {
        if (selected == null || !canAction(action, settlement: settlement)) {
          return;
        }
        if (local?.pending != null) {
          throw const DomainError(
            code: 'COMMAND_PENDING',
            message: 'Resolve the saved correction first.',
          );
        }
        confirmed = null;
        local = null;
        comparison = null;
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (action == 'record' || action == 'settlement_reverse') {
          kind = PayrollCorrectionCommandKind.settlement;
          form = {
            'action': action == 'record' ? 'record' : 'reverse',
            'id': settlement?['id'] ?? _uuid.v4(),
            'correction_id': selected!['id'],
            'posting_date': today,
            'reason': '',
            if (action == 'record') ...{
              'bank_id': null,
              'bank_version': null,
              'direction': 'pay',
              'evidence_reference': '',
              'allocations': <Map<String, Object?>>[],
            },
          };
          expectedVersion = settlement?['version'] as int? ?? 0;
          if (action == 'record') {
            final page = await base.accounts(scope, 'bank');
            if (!_current(e)) {
              return;
            }
            banks = page.items;
            final data = await repository.correctionDetail(
              scope,
              selected!['id'] as String,
              'balances',
            );
            if (!_current(e)) {
              return;
            }
            detail = data;
          }
        } else {
          kind = PayrollCorrectionCommandKind.correction;
          expectedVersion = selected!['version'] as int;
          form = {
            'action': action,
            'id': selected!['id'],
            'digest': selected!['digest'],
            'reason': '',
            if (action == 'reverse') ...{
              'posting_date': today,
              'current_billing_impacts': <Map<String, Object?>>[],
            },
          };
          if (action == 'reverse') {
            final page = await repository.correctionSources(
              scope,
              selected!['original_calculation_id'] as String,
            );
            if (!_current(e)) return;
            sources = page.items;
            sourceCursor = page.nextCursor;
          }
        }
      });
  Future<void> reverseSourcesMore() => _run((e) async {
    if (kind != PayrollCorrectionCommandKind.correction ||
        action != 'reverse' ||
        sourceCursor == null) {
      return;
    }
    final page = await repository.correctionSources(
      scope,
      selected!['original_calculation_id'] as String,
      after: sourceCursor,
    );
    if (!_current(e)) return;
    sources = [...sources, ...page.items];
    sourceCursor = page.nextCursor;
  });
  void currentBillingCredits(
    Map<String, Object?> source,
    Set<String> ids, {
    Map<String, Object?>? allocation,
  }) {
    if (locked ||
        kind != PayrollCorrectionCommandKind.correction ||
        action != 'reverse') {
      return;
    }
    final op = workforceMap(source['operational']);
    final rows = (form!['current_billing_impacts'] as List? ?? const [])
        .map(workforceMap)
        .toList();
    final prior = rows
        .where((row) => row['seal_id'] == source['seal_id'])
        .firstOrNull;
    rows.removeWhere((row) => row['seal_id'] == source['seal_id']);
    final credits = (prior?['allocation_credits'] as List? ?? const [])
        .map(workforceMap)
        .toList();
    if (allocation != null) {
      final before = workforceMap(allocation['before']);
      final entry =
          allocation['entry_id'] ?? before['entry_id'] ?? before['id'];
      credits.removeWhere((row) => row['entry_id'] == entry);
      credits.add({
        'entry_id': entry,
        'source_revision_id': allocation['source_id'],
        'expected_source_version': allocation['source_version'],
        'billing_credit_line_ids': ids.toList(),
      });
    }
    rows.add({
      'seal_id': source['seal_id'],
      'source_revision_id': op['source_id'],
      'expected_source_version': op['source_version'],
      'billing_credit_line_ids': allocation == null
          ? ids.toList()
          : prior?['billing_credit_line_ids'] ?? <String>[],
      'allocation_credits': credits,
    });
    form = {...form!, 'current_billing_impacts': rows};
    _notify();
  }

  bool canAction(String action, {Map<String, Object?>? settlement}) {
    final s = selected;
    if (s == null) {
      return false;
    }
    if (action == 'record' || action == 'settlement_reverse') {
      return has('people.payroll.settle') &&
          s['status'] == 'posted' &&
          (action == 'record' || settlement?['status'] == 'recorded');
    }
    if (!has(
      PayrollCorrectionCommands.capability(
        PayrollCorrectionCommandKind.correction,
        action,
      ),
    )) {
      return false;
    }
    return switch (action) {
      'approve' || 'reject' =>
        s['status'] == 'prepared' && s['prepared_by'] != scope.actorId,
      'post' => s['status'] == 'approved',
      'reverse' => s['status'] == 'posted',
      _ => false,
    };
  }

  void allocate(String id, String amount) {
    if (locked ||
        kind != PayrollCorrectionCommandKind.settlement ||
        action != 'record') {
      return;
    }
    final rows = (form!['allocations'] as List)
        .map(workforceMap)
        .where((r) => r['balance_id'] != id)
        .toList();
    if (amount.isNotEmpty) {
      rows.add({'balance_id': id, 'amount': amount});
    }
    update('allocations', rows);
  }

  Future<void> save() => _run((e) async {
    if (form == null || confirmed != null) {
      return;
    }
    await drafts.save(
      scope,
      kind,
      form!['id'] as String,
      action,
      form!,
      expectedVersion,
    );
    final value = await drafts.load(scope, kind, form!['id'] as String);
    if (_current(e)) {
      local = value;
      message = 'Encrypted correction saved for 24 hours.';
    }
  });
  Future<void> submit() => _run((e) async {
    if (!online) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Reconnect to submit the saved correction.',
      );
    }
    if (form == null || confirmed != null) {
      return;
    }
    if (local != null && !local!.expiresAt.isAfter(drafts.clock())) {
      form = null;
      local = null;
      sources = [];
      banks = [];
      creditChoices.clear();
      creditCursors.clear();
      throw const DomainError(
        code: 'PRIVATE_DRAFT_EXPIRED',
        message: 'Private correction fields expired. Resolve the minimal encrypted receipt.',
      );
    }
    final id = form!['id'] as String,
        pending =
            local?.pending ??
            await drafts.prepare(
              scope,
              kind,
              id,
              action,
              form!,
              expectedVersion,
            );
    if (!_current(e)) {
      return;
    }
    local = await drafts.load(scope, kind, id);
    if (!_current(e)) {
      return;
    }
    try {
      final response = await repository.executeCorrection(
        kind,
        pending.envelope,
      );
      if (!_current(e)) {
        return;
      }
      // A verified response is retained before optional disk cleanup or reads.
      confirmed = response;
      message = 'Correction command confirmed.';
      _notify();
      try {
        await drafts.complete(
          scope,
          kind,
          id,
          pending.envelope.commandId,
          response,
        );
        if (_current(e)) {
          local = null;
        }
      } catch (_) {
        if (_current(e)) {
          message = 'Command confirmed. Saved receipt cleanup needs retry.';
        }
      }
    } on DomainError catch (error) {
      try {
        await drafts.failure(
          scope,
          kind,
          id,
          pending.envelope.commandId,
          error,
        );
        if (_current(e)) {
          local = await drafts.load(scope, kind, id);
        }
      } catch (_) {}
      rethrow;
    }
  });
  Future<void> resume(SensitivePayrollCorrectionRecovery saved) =>
      _run((e) async {
        if (saved.expired) {
          final done = await drafts.reconcileExpired(
            scope,
            saved.kind,
            saved.id,
            repository,
          );
          if (_current(e)) {
            message = done
                ? 'Expired correction receipt confirmed.'
                : 'No receipt yet. The minimal encrypted receipt is retained.';
          }
          return;
        }
        final value = await drafts.load(scope, saved.kind, saved.id);
        if (!_current(e) || value == null) {
          return;
        }
        local = value;
        kind = value.kind;
        expectedVersion = value.version;
        form = value.form;
        confirmed = null;
        if (value.action == 'prepare') {
          final page = await repository.correctionSources(
            scope,
            value.form['original_calculation_id'] as String,
          );
          if (_current(e)) {
            sources = page.items;
            sourceCursor = page.nextCursor;
          }
        } else if (value.kind == PayrollCorrectionCommandKind.correction &&
            value.action == 'reverse') {
          final data = await repository.correctionDetail(
            scope,
            value.form['id'] as String,
            'calculation',
          );
          if (!_current(e)) {
            return;
          }
          selected = workforceMap(data['correction']);
          final page = await repository.correctionSources(
            scope,
            selected!['original_calculation_id'] as String,
          );
          if (!_current(e)) {
            return;
          }
          sources = page.items;
          sourceCursor = page.nextCursor;
        } else if (value.kind == PayrollCorrectionCommandKind.settlement) {
          final data = await repository.correctionDetail(
            scope,
            value.form['correction_id'] as String,
            value.action == 'record' ? 'balances' : 'settlements',
          );
          if (!_current(e)) {
            return;
          }
          selected = workforceMap(data['correction']);
          detail = data;
          if (value.action == 'record') {
            final page = await base.accounts(scope, 'bank');
            if (!_current(e)) {
              return;
            }
            banks = page.items;
          }
        }
      });
  Future<void> compare() => _run((e) async {
    if (!conflict || form == null) {
      return;
    }
    if (kind == PayrollCorrectionCommandKind.correction &&
        action == 'prepare') {
      final all = <Map<String, Object?>>[];
      String? after;
      do {
        final page = await repository.correctionSources(
          scope,
          form!['original_calculation_id'] as String,
          after: after,
        );
        if (!_current(e)) {
          return;
        }
        all.addAll(page.items);
        after = page.nextCursor;
        if (all.length >= 2000 && after != null) {
          throw const DomainError(
            code: 'PAGE_LIMIT',
            message: 'Source comparison exceeds its bound.',
          );
        }
      } while (after != null);
      if (_current(e)) {
        sources = all;
        comparison = {'sources': all, 'version': 0};
      }
      return;
    }
    final data = await repository.correctionDetail(
      scope,
      (form!['correction_id'] ?? form!['id']) as String,
      kind == PayrollCorrectionCommandKind.settlement
          ? action == 'record'
                ? 'balances'
                : 'settlements'
          : 'calculation',
    );
    if (!_current(e)) {
      return;
    }
    if (kind == PayrollCorrectionCommandKind.settlement) {
      detail = data;
      if (action == 'record') {
        final page = await base.accounts(scope, 'bank');
        if (!_current(e)) {
          return;
        }
        banks = page.items;
        comparison = data;
      } else {
        var all = (data['items'] as List).map(workforceMap).toList();
        String? after = data['next_cursor'] as String?;
        while (!all.any((row) => row['id'] == form!['id']) && after != null) {
          final page = await repository.correctionDetail(
            scope,
            form!['correction_id'] as String,
            'settlements',
            after: after,
          );
          if (!_current(e)) {
            return;
          }
          all = [...all, ...(page['items'] as List).map(workforceMap)];
          after = page['next_cursor'] as String?;
          if (all.length > 2000) {
            throw const DomainError(
              code: 'PAGE_LIMIT',
              message: 'Settlement comparison exceeds its bound.',
            );
          }
        }
        comparison = {
          ...data,
          'settlement': all
              .where((row) => row['id'] == form!['id'])
              .firstOrNull,
        };
      }
    } else {
      comparison = data;
      if (action == 'reverse') {
        final current = workforceMap(data['correction']);
        final page = await repository.correctionSources(
          scope,
          current['original_calculation_id'] as String,
        );
        if (!_current(e)) {
          return;
        }
        sources = page.items;
        sourceCursor = page.nextCursor;
      }
    }
  });
  Future<void> acceptComparison() => _run((e) async {
    if (comparison == null || form == null || local?.pending != null) {
      return;
    }
    final oldId = form!['id'] as String;
    if (kind == PayrollCorrectionCommandKind.correction &&
        action == 'prepare') {
      final replacements = <Map<String, Object?>>[];
      for (final value in form!['replacements'] as List) {
        final replacement = workforceMap(value);
        final current = sources
            .where((s) => s['seal_id'] == replacement['seal_id'])
            .firstOrNull;
        if (current == null) {
          throw const DomainError(
            code: 'VERSION_CONFLICT',
            message: 'A source is no longer available. Start a new proposal.',
          );
        }
        replacements.add({
          ...replacement,
          'before_revision_id': current['revision_id'],
          'expected_version': current['version'],
          if (replacement['impact'] != null)
            'impact': {
              ...workforceMap(replacement['impact']),
              'expected_source_version': workforceMap(
                current['operational'],
              )['source_version'],
            },
        });
      }
      await drafts.discard(scope, kind, oldId);
      if (!_current(e)) {
        return;
      }
      form = {...form!, 'id': _uuid.v4(), 'replacements': replacements};
      expectedVersion = 0;
    } else {
      final current = workforceMap(comparison!['correction']);
      selected = current;
      if (kind == PayrollCorrectionCommandKind.settlement) {
        if (action == 'record') {
          if (!canAction('record')) {
            throw const DomainError(
              code: 'STATE_CONFLICT',
              message: 'The current correction cannot accept a settlement.',
            );
          }
          final bank = banks
              .where((row) => row['id'] == form!['bank_id'])
              .firstOrNull;
          if (bank == null) {
            throw const DomainError(
              code: 'VERSION_CONFLICT',
              message: 'Select a current scoped bank account.',
            );
          }
          expectedVersion = 0;
          form = {...form!, 'bank_version': bank['version']};
          detail = comparison;
        } else {
          final settlement = comparison!['settlement'] == null
              ? null
              : workforceMap(comparison!['settlement']);
          if (!canAction('settlement_reverse', settlement: settlement)) {
            throw const DomainError(
              code: 'STATE_CONFLICT',
              message: 'Choose a current recorded settlement after comparison.',
            );
          }
          expectedVersion = settlement!['version'] as int;
        }
      } else {
        if (!canAction(action)) {
          throw const DomainError(
            code: 'STATE_CONFLICT',
            message: 'Choose a current action after comparison.',
          );
        }
        expectedVersion = current['version'] as int;
        form = {
          ...form!,
          'digest': current['digest'],
          if (action == 'reverse')
            'current_billing_impacts': <Map<String, Object?>>[],
        };
      }
    }
    await drafts.save(
      scope,
      kind,
      form!['id'] as String,
      action,
      form!,
      expectedVersion,
      compared: true,
    );
    if (!_current(e)) {
      return;
    }
    local = await drafts.load(scope, kind, form!['id'] as String);
    if (_current(e)) {
      comparison = null;
    }
  });
  Future<void> discard() => _run((e) async {
    if (form == null) {
      return;
    }
    await drafts.discard(scope, kind, form!['id'] as String);
    if (_current(e)) {
      form = null;
      local = null;
      confirmed = null;
    }
  });
  Future<void> closeForm() => _run((e) async {
    if (form != null && confirmed == null && local?.pending == null) {
      await drafts.save(
        scope,
        kind,
        form!['id'] as String,
        action,
        form!,
        expectedVersion,
      );
    }
    final saved = await drafts.recovery(scope);
    if (_current(e)) {
      recovery = saved;
      form = null;
      local = null;
      confirmed = null;
      comparison = null;
    }
  });
}
