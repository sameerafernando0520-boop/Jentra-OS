import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import '../../app_providers.dart';

final bankReconciliationGatewayProvider = Provider<BankReconciliationGateway?>(
  (ref) => null,
);
final bankReconciliationControllerProvider =
    Provider.autoDispose<BankReconciliationController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(bankReconciliationGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('finance.view') ?? false)) {
        return null;
      }
      final c = BankReconciliationController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        capabilities: caps.value!,
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

final class BankReconciliationController extends ChangeNotifier {
  BankReconciliationController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.capabilities,
    required this.online,
  });
  final TenantContext scope;
  final BankReconciliationGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> capabilities;
  static const slot = 'bank-reconciliation-editor';
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  String? error, message;
  int formEpoch = 0;
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;
  final pages = <String, List<Map<String, Object?>>>{};
  final cursors = <String, String?>{};
  bool get pending => local?.pending != null;
  bool get locked => busy || pending || denied;
  String? get bankId => form['bank_id'] as String?;
  List<Map<String, Object?>> rows(String resource) => pages[resource] ?? [];
  bool can(String action) => capabilities.contains(switch (action) {
    'import' => 'finance.bank.import',
    'rules' => 'finance.bank.manage',
    _ => 'finance.bank.reconcile',
  });
  String get today => DateTime.now().toUtc().toIso8601String().substring(0, 10);
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

  void handle(Object e) {
    if (e is DomainError && e.code == 'PERMISSION_DENIED') {
      denied = true;
      verified = false;
      pages.clear();
      cursors.clear();
      form = {};
    }
    error = e is DomainError
        ? e.message
        : e is FormatException
        ? e.message
        : 'Unable to complete this action. Your saved request is retained.';
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      handle(e);
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => run(() async {
    if (form.isNotEmpty && !pending && !denied) await persist();
    local = await drafts.load(scope, slot);
    // Financial source descriptions remain hidden until current server access succeeds.
    if (!online) {
      verified = false;
      return;
    }
    await load('accounts');
    verified = true;
    denied = false;
    form =
        local?.form ?? {'posting_date': today, 'opening': '0', 'closing': '0'};
    formEpoch++;
    if (bankId != null) await reloadBank();
  });
  Future<void> load(String resource, {bool more = false}) async {
    if (!online) return;
    final r = await gateway.options(
      scope,
      resource,
      bankId:
          resource == 'accounts' ||
              resource == 'offset_accounts' ||
              resource == 'rates'
          ? null
          : bankId,
      after: more ? cursors[resource] : null,
    );
    if (_disposed) return;
    pages[resource] = [
      if (more) ...rows(resource),
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursors[resource] = r['next_cursor'] as String?;
  }

  Future<void> page(String resource) => run(() => load(resource, more: true));
  Future<void> reloadBank() async {
    for (final resource in [
      'statements',
      'statement_lines',
      'journal_lines',
      'matches',
      'offset_accounts',
      'rates',
    ]) {
      await load(resource);
    }
  }

  Future<void> refresh() => run(() async {
    if (online && !denied && bankId != null) await reloadBank();
  });
  Future<void> selectBank(String id) => run(() async {
    if (pending || !verified || denied) return;
    form = {
      'bank_id': id,
      'posting_date': today,
      'opening': '0',
      'closing': '0',
    };
    formEpoch++;
    pages.removeWhere((k, v) => k != 'accounts');
    cursors.removeWhere((k, v) => k != 'accounts');
    await persist();
    await reloadBank();
  });
  void field(String key, String value) {
    if (locked) return;
    form = {...form, key: value.trim()};
    emit();
  }

  void toggle(String resource, String id, bool value) {
    if (locked || !verified || !can('match')) return;
    final key = resource == 'statement_lines'
        ? 'statement_line_ids'
        : 'journal_line_ids';
    final ids = {...(form[key] as List? ?? []).cast<String>()};
    if (value) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    form = {...form, key: ids.toList()};
    emit();
  }

  ExactDecimal selectedTotal(String resource) {
    final key = resource == 'statement_lines'
        ? 'statement_line_ids'
        : 'journal_line_ids';
    final ids = (form[key] as List? ?? []).cast<String>().toSet();
    var total = ExactDecimal.zero(scale: 6);
    for (final row in rows(resource)) {
      if (ids.contains(row['id'])) {
        total += ExactDecimal.parse(row['amount'] as String, scale: 6);
      }
    }
    return total;
  }

  Future<void> preview(Uint8List bytes, String extension, String name) =>
      run(() async {
        if (pending || !verified || denied || !can('import')) return;
        final preview = BankStatementPreview.decode(bytes, extension);
        if (utf8.encode(jsonEncode(preview.lines)).length > 1900000) {
          throw const FormatException(
            'Normalized statement exceeds the 2 MiB import limit.',
          );
        }
        form = {
          ...form,
          'lines': preview.lines,
          'file_name': name,
          'total': preview.total.toDecimalString(),
        };
        await persist();
      });
  Future<void> persist() async {
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: expectedVersion(form['action'] as String? ?? 'match'),
    );
    local = await drafts.load(scope, slot);
  }

  int expectedVersion(String action) => action == 'reverse'
      ? 1
      : action == 'rules'
      ? (rows('accounts').firstWhere(
              (r) => r['id'] == bankId,
              orElse: () => {'version': local?.expectedVersion ?? 0},
            )['version']
            as int)
      : 0;

  Future<void> save() => run(() async {
    if (!pending && !denied && form.isNotEmpty) await persist();
  });
  Future<bool> canLeave() async {
    if (busy) return false;
    if (pending || denied || form.isEmpty) return true;
    await save();
    return error == null;
  }

  void validDate(Object? v) {
    if (v is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
        DateTime.tryParse(v)?.toIso8601String().substring(0, 10) != v) {
      throw const FormatException('Enter a valid YYYY-MM-DD date.');
    }
  }

  Future<void> execute(String action, {String? matchId}) => run(() async {
    if (!online || !verified || denied || !can(action)) return;
    var command = local?.pending;
    if (command == null) {
      if (bankId == null) throw const FormatException('Choose a bank account.');
      final p = <String, Object?>{
        'action': action,
        'id': const Uuid().v4(),
        'bank_id': bankId,
      };
      if (action == 'rules') {
        final value = form['tolerance'] as String? ?? '';
        if (!RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(value) ||
            (form['reason'] as String? ?? '').length < 3) {
          throw const FormatException(
            'Enter a non-negative exact tolerance and a reason.',
          );
        }
        p['tolerance'] = value;
        p['reason'] = form['reason'];
      } else if (action == 'import') {
        for (final k in ['start_date', 'end_date']) {
          validDate(form[k]);
        }
        if ((form['start_date'] as String).compareTo(
                  form['end_date'] as String,
                ) >
                0 ||
            (form['end_date'] as String).compareTo(today) > 0) {
          throw const FormatException(
            'Statement range must end today or earlier.',
          );
        }
        if ((form['identity'] as String? ?? '').isEmpty ||
            (form['lines'] as List? ?? []).isEmpty) {
          throw const FormatException(
            'Enter the statement identity and preview its file.',
          );
        }
        for (final k in ['opening', 'closing']) {
          if (!RegExp(
            r'^-?\d{1,14}(\.\d{1,6})?$',
          ).hasMatch(form[k] as String? ?? '')) {
            throw const FormatException(
              'Enter exact opening and closing balances.',
            );
          }
        }
        if (ExactDecimal.parse(form['opening'] as String, scale: 6) +
                ExactDecimal.parse(form['total'] as String, scale: 6) !=
            ExactDecimal.parse(form['closing'] as String, scale: 6)) {
          throw const FormatException(
            'Opening balance plus statement total must equal closing balance.',
          );
        }
        for (final row in (form['lines'] as List).cast<Map>()) {
          final date = row['date'] as String;
          if (date.compareTo(form['start_date'] as String) < 0 ||
              date.compareTo(form['end_date'] as String) > 0) {
            throw const FormatException(
              'Every statement line must be inside the selected date range.',
            );
          }
        }
        for (final k in [
          'identity',
          'start_date',
          'end_date',
          'opening',
          'closing',
          'lines',
        ]) {
          p[k] = form[k];
        }
      } else {
        validDate(form['posting_date']);
        if ((form['reason'] as String? ?? '').length < 3) {
          throw const FormatException(
            'Enter a reason of at least three characters.',
          );
        }
        p['posting_date'] = form['posting_date'];
        p['reason'] = form['reason'];
        if (action == 'reverse') {
          if (matchId == null) throw const FormatException('Choose a match.');
          p['match_id'] = matchId;
        } else {
          final s = form['statement_line_ids'] as List? ?? [],
              j = form['journal_line_ids'] as List? ?? [];
          if (s.isEmpty ||
              j.isEmpty ||
              s.length > 100 ||
              j.length > 100 ||
              (s.length > 1 && j.length > 1)) {
            throw const FormatException(
              'Select one-to-one, one-to-many or many-to-one sources (maximum 100 each).',
            );
          }
          p['statement_line_ids'] = s;
          p['journal_line_ids'] = j;
          for (final k in ['adjustment_account_id', 'exchange_rate_id']) {
            if (form[k] != null && form[k] != '') p[k] = form[k];
          }
        }
      }
      form = {...form, 'action': action};
      await persist();
      command = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        payload: p,
        expectedVersion: expectedVersion(action),
      );
      local = await drafts.load(scope, slot);
    }
    try {
      await gateway.execute(command.envelope);
      await drafts.complete(scope, slot, command.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: command.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      rethrow;
    }
    local = null;
    form = {
      'bank_id': bankId,
      'posting_date': today,
      'opening': '0',
      'closing': '0',
    };
    formEpoch++;
    message = 'Bank command confirmed. Original evidence remains in history.';
    try {
      await persist();
      await load('accounts');
      await reloadBank();
    } catch (e) {
      handle(e);
      if (!denied) {
        error = 'Command confirmed. Refresh to load its recorded evidence.';
      }
    }
  });
  Future<void> retry() =>
      execute(local?.pending?.envelope.payload['action'] as String? ?? 'match');
  Future<void> resolveConflict() => run(() async {
    if (!online ||
        !verified ||
        denied ||
        pending ||
        local?.errorCode != 'VERSION_CONFLICT') {
      return;
    }
    await reloadBank();
    form = {
      ...form,
      'statement_line_ids': <String>[],
      'journal_line_ids': <String>[],
      'action': 'match',
    };
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: 0,
      resolveConflict: true,
    );
    local = await drafts.load(scope, slot);
    message =
        'Sources refreshed. Select the current unmatched lines explicitly.';
  });
}
