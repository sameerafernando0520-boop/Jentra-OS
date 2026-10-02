import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assets.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_assets_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

const assetActions = {
  'location',
  'opening',
  'propose',
  'approve',
  'post',
  'depreciate',
  'reverse',
  'cancel',
};
const assetDefiniteFailures = {
  'VERSION_CONFLICT',
  'VALIDATION_ERROR',
  'STATE_CONFLICT',
  'IDENTITY_EXISTS',
  'ASSET_SOURCE_ALREADY_OWNED',
  'PERIOD_CLOSED',
  'ASSET_REBOOK_AFTER_REVERSAL_REQUIRED',
  'ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL',
};
ScopedCommandDraftStore assetDrafts(
  EncryptedDraftRepository repository,
  String action,
) => ScopedCommandDraftStore(
  repository,
  entityType: 'assets.command.$action',
  fields: AssetCommands.fields,
  validate: AssetCommands.validate,
  definiteFailures: assetDefiniteFailures,
);
final assetsRepositoryProvider = Provider<AssetRepository?>((ref) => null);
final assetsControllerProvider = Provider.autoDispose<AssetsController?>((ref) {
  final scope = ref.watch(activeTenantContextProvider),
      caps = ref.watch(businessCapabilitiesProvider),
      repository = ref.watch(assetsRepositoryProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('assets.view') ?? false)) {
    return null;
  }
  final encrypted = ref.watch(encryptedDraftRepositoryProvider);
  final c = AssetsController(
    scope: scope,
    repository: repository,
    drafts: {for (final a in assetActions) a: assetDrafts(encrypted, a)},
    permissions: caps.value!,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
    branches: ref.watch(businessScopeProvider).value?.branches ?? const [],
  );
  ref.listen(
    connectivityStateProvider,
    (_, value) => c.setOnline(value.value == ConnectivityState.online),
  );
  ref.onDispose(c.dispose);
  unawaited(c.initialize());
  return c;
});

final class AssetSavedDraft {
  const AssetSavedDraft(this.action, this.draft);
  final String action;
  final ScopedCommandDraft draft;
  ScopedPendingCommand? get pending => draft.pending;
  String get aggregateId => draft.aggregateId;
}

final class AssetsController extends ChangeNotifier {
  AssetsController({
    required this.scope,
    required this.repository,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
    required List<BranchSummary> branches,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions),
       branches = List.unmodifiable(
         branches.where(
           (b) =>
               b.tenantId == scope.tenantId &&
               b.legalEntityId == scope.legalEntityId &&
               b.status == 'active',
         ),
       ) {
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final AssetRepository repository;
  final Map<String, ScopedCommandDraftStore> drafts;
  final Set<String> permissions;
  final List<BranchSummary> branches;
  static const _uuid = Uuid();
  Timer? _timer;
  bool online,
      busy = false,
      accessDenied = false,
      _disposed = false,
      _sending = false;
  int _epoch = 0;
  AssetProviderState? providers;
  List<AssetRecord> records = [];
  List<AssetSavedDraft> recovery = [];
  String? cursor, error, message;
  AssetDetail? selected, comparison;
  AssetSchedulePage? schedule;
  AssetHistoryKind historyKind = AssetHistoryKind.books;
  List<AssetBook> books = [];
  List<AssetEffect> effects = [];
  List<AssetProposal> proposals = [];
  String? historyCursor;
  List<AssetSchedulePeriod> periods = [];
  int? scheduleCursor;
  Map<String, Object?>? form, confirmed;
  ScopedCommandDraft? local;
  int expectedVersion = 0;
  final labels = <String, String>{};
  final recoveryCursors = <String, String?>{};
  bool get current => !_disposed && !accessDenied;
  bool has(String cap) => permissions.contains(cap);
  String? get action => form?['action'] as String?;
  ScopedPendingCommand? get pending => local?.pending;
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked =>
      busy || !current || pending != null || conflict || confirmed != null;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void setOnline(bool value) {
    online = value;
    _notify();
  }

  void _clearForm() {
    _epoch++;
    form = null;
    local = null;
    confirmed = null;
    comparison = null;
    labels.clear();
    expectedVersion = 0;
  }

  void _clear() {
    _clearForm();
    records = [];
    recovery = [];
    selected = null;
    schedule = null;
    books = [];
    effects = [];
    proposals = [];
    periods = [];
    providers = null;
    cursor = null;
    historyCursor = null;
    scheduleCursor = null;
    recoveryCursors.clear();
  }

  void _deny() {
    accessDenied = true;
    _clear();
    error = 'Asset access changed. Select an authorized scope.';
    message = null;
    _notify();
  }

  void _connected() {
    if (!online) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect before checking or submitting an asset command.',
      );
    }
  }

  Future<void> _access(String capability) async {
    _connected();
    if (!has(capability)) {
      throw const DomainError(
        code: 'ACTION_NOT_PERMITTED',
        message: 'This asset action needs its current permission.',
      );
    }
    AssetProviderState state;
    try {
      state = await repository.authorize(scope, capability);
    } on DomainError catch (cause) {
      if ({
            'PERMISSION_DENIED',
            'AUTHENTICATION_REQUIRED',
            'FEATURE_NOT_ENTITLED',
          }.contains(cause.code) &&
          current) {
        _deny();
      }
      rethrow;
    }
    if (current) {
      providers = state;
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || !current) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await work();
    } on DomainError catch (cause) {
      if ({
        'PERMISSION_DENIED',
        'AUTHENTICATION_REQUIRED',
        'FEATURE_NOT_ENTITLED',
      }.contains(cause.code)) {
        _deny();
      } else if (current) {
        error = cause.message;
      }
    } catch (_) {
      if (current) {
        error = 'The asset data or form could not be verified. Check the fields and refresh its scoped history.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> checkAccess() async {
    if (!current || busy || !online) {
      return;
    }
    try {
      await _access('assets.view');
      if (action != null) {
        await _access(AssetCommands.capability(action!));
      }
    } on DomainError catch (cause) {
      if ({
            'PERMISSION_DENIED',
            'AUTHENTICATION_REQUIRED',
            'FEATURE_NOT_ENTITLED',
          }.contains(cause.code) &&
          current) {
        _deny();
      }
    } catch (_) {
      /* A failed read grants no new authority and displays no new data. */
    }
  }

  Future<void> initialize() => _run(() async {
    await _access('assets.view');
    if (!current) {
      return;
    }
    await _register();
    if (current) {
      await _recover();
    }
  });
  Future<void> _register({bool more = false}) async {
    _connected();
    final page = await repository.register(scope, after: more ? cursor : null);
    if (!current) {
      return;
    }
    records = [if (more) ...records, ...page.items];
    cursor = page.nextCursor;
  }

  Future<void> refresh() => _run(() async {
    await _access('assets.view');
    if (current) {
      await _register();
    }
  });
  Future<void> more() => _run(() async {
    await _access('assets.view');
    if (current) {
      await _register(more: true);
    }
  });
  Future<void> _recover({String? more}) async {
    final rows = <AssetSavedDraft>[if (more != null) ...recovery];
    for (final a in assetActions) {
      if (more != null && a != more || !has(AssetCommands.capability(a))) {
        continue;
      }
      // Each action has its own encrypted namespace, so original authority is
      // checked before any draft body from that namespace is decrypted.
      await _access(AssetCommands.capability(a));
      if (!current) {
        return;
      }
      final page = await drafts[a]!.page(
        scope,
        after: more == a ? recoveryCursors[a] : null,
      );
      if (!current) {
        return;
      }
      rows.addAll(page.items.map((d) => AssetSavedDraft(a, d)));
      recoveryCursors[a] = page.nextCursor;
    }
    if (current) {
      recovery = rows;
    }
  }

  Future<void> moreRecovery(String action) =>
      _run(() => _recover(more: action));
  Future<void> _detail(
    String id,
    AssetHistoryKind kind, {
    bool more = false,
  }) async {
    final row = await repository.detail(
      scope,
      id,
      kind,
      after: more ? historyCursor : null,
    );
    if (!current) {
      return;
    }
    selected = row;
    historyKind = kind;
    historyCursor = row.nextCursor;
    books = [if (more) ...books, ...row.books];
    effects = [if (more) ...effects, ...row.effects];
    proposals = [if (more) ...proposals, ...row.proposals];
  }

  Future<void> select(AssetRecord record) => _run(() async {
    if (form != null) {
      await _save();
      if (!current) {
        return;
      }
      _clearForm();
    }
    await _access('assets.view');
    if (!current) {
      return;
    }
    await _detail(record.id, AssetHistoryKind.books);
    if (!current) {
      return;
    }
    schedule = null;
    periods = [];
    scheduleCursor = null;
    if (selected?.asset.bookId != null) {
      await _schedule(selected!.asset.bookId!);
    }
  });
  Future<void> history(AssetHistoryKind kind, {bool more = false}) =>
      _run(() async {
        if (selected == null) {
          return;
        }
        await _access('assets.view');
        if (current) {
          await _detail(selected!.asset.id, kind, more: more);
        }
      });
  Future<void> _schedule(String book, {bool more = false}) async {
    if (selected == null) {
      return;
    }
    final page = await repository.schedule(
      scope,
      selected!.asset.id,
      book,
      after: more ? scheduleCursor ?? 0 : 0,
    );
    if (!current) {
      return;
    }
    schedule = page;
    periods = [if (more) ...periods, ...page.periods];
    scheduleCursor = page.nextCursor;
  }

  Future<void> showBook(String id) => _run(() async {
    await _access('assets.view');
    if (current) {
      await _schedule(id);
    }
  });
  Future<void> moreSchedule() => _run(() async {
    if (schedule != null && scheduleCursor != null) {
      await _access('assets.view');
      if (current) {
        await _schedule(schedule!.bookId, more: true);
      }
    }
  });
  Map<String, Object?> _bookForm(AssetBookDefinition? b, {int posted = 0}) {
    if (b != null) {
      final result = b.toJson();
      return {
        for (final k in assetBookInputFields) k: result[k],
        'remaining_months': b.basis.remainingMonths - posted,
      };
    }
    return {
      'residual': '0',
      'remaining_months': 12,
      'method': 'straight_line',
      'convention': 'in_service_month',
      'rate_numerator': 1,
      'rate_denominator': 1,
      'precision': providers!.precision,
      'expense_account_id': null,
    };
  }

  Future<void> begin(String next, {String? kind}) => _run(() async {
    if (form != null) {
      await _save();
      if (!current) {
        return;
      }
      _clearForm();
    }
    await _access(AssetCommands.capability(next));
    if (!current) {
      return;
    }
    final date = providers!.businessDate.value;
    Map<String, Object?> nextForm;
    int nextVersion;
    if ({'location', 'opening'}.contains(next)) {
      nextForm = {
        'action': next,
        'id': _uuid.v4(),
        'reason': '',
        'code': '',
        'name': '',
      };
      nextVersion = 0;
      if (next == 'opening') {
        nextForm.addAll({
          'proposal_id': _uuid.v4(),
          'source_id': _uuid.v4(),
          'source_reference': '',
          'ownership': '',
          'in_service': date,
          'posting_date': date,
          'currency_code': providers!.currency,
          'location_id': null,
          'custodian_id': null,
          'cost': '',
          'opening_accumulated': '0',
          'cost_components': [
            {'code': 'OPENING', 'name': 'Synthetic opening cost', 'amount': ''},
          ],
          'cost_account_id': null,
          'accumulated_account_id': null,
          'impairment_account_id': null,
          'offset_account_id': null,
          'book': _bookForm(null),
        });
      }
    } else {
      if (selected == null) {
        throw const DomainError(
          code: 'RESOURCE_NOT_FOUND',
          message: 'Choose an asset first.',
        );
      }
      if (recovery.any(
        (d) => d.aggregateId == selected!.asset.id && d.pending != null,
      )) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Reconcile the saved request for this asset before preparing another action.',
        );
      }
      await _detail(selected!.asset.id, historyKind);
      if (!current) {
        return;
      }
      final a = selected!.asset;
      nextVersion = a.version;
      nextForm = {'action': next, 'id': a.id, 'reason': ''};
      if (next == 'propose') {
        if (!{
              'book_revision',
              'transfer',
              'impair',
              'revalue',
              'dispose',
            }.contains(kind) ||
            a.status != 'active' ||
            a.proposalId != null) {
          throw const DomainError(
            code: 'STATE_CONFLICT',
            message: 'Choose an active asset without another pending proposal.',
          );
        }
        nextForm.addAll({
          'proposal_id': _uuid.v4(),
          'kind': kind,
          'posting_date': date,
        });
        if (kind == 'book_revision') {
          await _schedule(a.bookId!);
          if (!current) {
            return;
          }
          nextForm['book'] = _bookForm(
            schedule!.definition,
            posted: a.postedPeriods,
          );
        }
        if (kind == 'transfer') {
          await _access('assets.transfer');
          if (!current) {
            return;
          }
          nextForm.addAll({
            'destination_branch_id': null,
            'location_id': null,
            'custodian_id': null,
          });
        }
        if (kind == 'impair') {
          nextForm.addAll({'amount': '', 'loss_account_id': null});
        }
        if (kind == 'revalue') {
          nextForm.addAll({
            'cost': a.cost.toDecimalString(),
            'surplus_account_id': null,
            'loss_account_id': null,
          });
        }
        if (kind == 'dispose') {
          nextForm.addAll({
            'proceeds': '0',
            'proceeds_account_id': null,
            'gain_account_id': null,
            'loss_account_id': null,
          });
        }
      } else if (next == 'depreciate') {
        nextForm.addAll({
          'book_id': a.bookId,
          'period_index': a.postedPeriods + 1,
        });
      } else if (next == 'reverse') {
        nextForm['effect_id'] = a.lastEffectId;
      } else {
        final p = selected!.proposal;
        if (p == null) {
          throw const DomainError(
            code: 'STATE_CONFLICT',
            message: 'This asset has no current proposal.',
          );
        }
        if (next == 'approve' && p.actorId == scope.actorId) {
          throw const DomainError(
            code: 'STATE_CONFLICT',
            message: 'Another authorized member must approve this proposal.',
          );
        }
        nextForm.addAll({'proposal_id': p.id, 'digest': p.digest});
      }
    }
    form = nextForm;
    expectedVersion = nextVersion;
    local = null;
    confirmed = null;
    comparison = null;
    _epoch++;
    message = null;
  });
  void update(String field, Object? value) {
    if (locked ||
        form == null ||
        !form!.containsKey(field) ||
        {
          'action',
          'id',
          'proposal_id',
          'source_id',
          'book_id',
          'effect_id',
          'digest',
          'period_index',
          'currency_code',
        }.contains(field)) {
      return;
    }
    form = Map<String, Object?>.from(jsonDecode(jsonEncode(form)) as Map)
      ..[field] = value;
    _epoch++;
    if (field == 'cost' &&
        action == 'opening' &&
        (form!['cost_components'] as List).length == 1) {
      final row = Map<String, Object?>.from(
        (form!['cost_components'] as List).single as Map,
      )..['amount'] = value;
      form!['cost_components'] = [row];
    }
    _notify();
  }

  void updateBook(String field, Object? value) {
    if (locked ||
        form?['book'] == null ||
        !assetBookInputFields.contains(field)) {
      return;
    }
    final book = assetMap(form!['book']);
    update('book', {...book, field: value});
  }

  void components(List<Map<String, Object?>> rows) {
    if (locked || action != 'opening' || rows.isEmpty || rows.length > 50) {
      return;
    }
    update('cost_components', rows);
    try {
      var amount = Money.zero(providers!.currency);
      for (final row in rows) {
        amount += assetAmount(row['amount'] as String, providers!.currency);
      }
      form!['cost'] = amount.toDecimalString();
      _notify();
    } catch (_) {
      /* Preserve invalid input for correction; sealing still requires exact conservation. */
    }
  }

  Future<AssetPage<AssetPicker>> choices(
    String kind, {
    String? after,
    String? branchId,
  }) async {
    if (!current || !online) {
      return const AssetPage([], null);
    }
    final epoch = _epoch;
    final context = branchId == null
        ? scope
        : scope.copyWith(branchId: branchId);
    try {
      await repository.authorize(context, 'assets.view');
    } on DomainError catch (cause) {
      if (cause.code == 'AUTHENTICATION_REQUIRED' ||
          context.branchId == scope.branchId &&
              {
                'PERMISSION_DENIED',
                'FEATURE_NOT_ENTITLED',
              }.contains(cause.code)) {
        _deny();
      }
      rethrow;
    }
    if (!current || epoch != _epoch) {
      return const AssetPage([], null);
    }
    final page = await repository.pickers(context, kind, after: after);
    if (!current || epoch != _epoch) {
      return const AssetPage([], null);
    }
    for (final row in page.items) {
      labels[row.id] = '${row.code} — ${row.name}';
    }
    return page;
  }

  void choose(String field, AssetPicker row) {
    if (locked) {
      return;
    }
    labels[row.id] = '${row.code} — ${row.name}';
    if (field == 'expense_account_id') {
      updateBook(field, row.id);
    } else {
      update(field, row.id);
    }
  }

  Future<void> destination(String id) => _run(() async {
    if (form?['kind'] != 'transfer' ||
        pending != null ||
        conflict ||
        confirmed != null) {
      return;
    }
    if (!branches.any((b) => b.id == id)) {
      throw const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'Choose a named branch in this entity.',
      );
    }
    await repository.authorize(scope.copyWith(branchId: id), 'assets.transfer');
    if (!current) {
      return;
    }
    form = {
      ...form!,
      'destination_branch_id': id,
      'location_id': null,
      'custodian_id': null,
    };
    _epoch++;
  });
  Future<void> _save() async {
    if (form == null ||
        local?.pending != null ||
        conflict ||
        confirmed != null) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    if (online) {
      await _access(AssetCommands.capability(a));
      if (!current) {
        return;
      }
    }
    await drafts[a]!.save(scope, id, a, form!, expectedVersion);
    if (!current) {
      return;
    }
    local = await drafts[a]!.load(scope, id);
    if (current && local != null) {
      recovery = [
        ...recovery.where((d) => d.action != a || d.aggregateId != id),
        AssetSavedDraft(a, local!),
      ];
    }
  }

  Future<void> save() => _run(_save);
  Future<void> resume(AssetSavedDraft row) => _run(() async {
    if (form != null) {
      await _save();
      if (!current) {
        return;
      }
    }
    await _access(AssetCommands.capability(row.action));
    if (!current) {
      return;
    }
    final loaded = await drafts[row.action]!.load(scope, row.aggregateId);
    if (!current || loaded == null) {
      return;
    }
    _clearForm();
    local = loaded;
    form = Map<String, Object?>.from(
      jsonDecode(jsonEncode(loaded.pending?.envelope.payload ?? loaded.form))
          as Map,
    );
    expectedVersion = loaded.version;
    if (!{'location', 'opening'}.contains(row.action)) {
      selected = null;
      books = [];
      effects = [];
      proposals = [];
      schedule = null;
      periods = [];
      scheduleCursor = null;
      try {
        await _detail(row.aggregateId, AssetHistoryKind.books);
      } on DomainError catch (cause) {
        if ({
          'PERMISSION_DENIED',
          'AUTHENTICATION_REQUIRED',
          'FEATURE_NOT_ENTITLED',
        }.contains(cause.code)) {
          _deny();
        } else if (current) {
          message = 'The saved request is ready for reconciliation. Its optional current proposal review could not be refreshed.';
        }
      } catch (_) {
        if (current) message = 'The saved request is ready for reconciliation. Its optional current proposal review could not be refreshed.';
      }
    }
  });
  Map<String, Object?> _verify(
    Map<String, Object?> result,
    CommandEnvelope<Map<String, Object?>> command,
  ) {
    calendarFields(result, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    calendarUuid(result['request_id']);
    calendarUuid(result['correlation_id']);
    final e = assetMap(result['entity']);
    assertAssetScope(e, scope);
    final a = command.payload['action'];
    calendarFields(e, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'version',
      if (a != 'location') ...{
        'current_branch_id',
        'status',
        'proposal_id',
        'book_id',
        'last_effect_id',
      },
    });
    if (a != 'location') {
      calendarUuid(e['current_branch_id']);
      assetOptionalId(e['proposal_id']);
      assetOptionalId(e['book_id']);
      assetOptionalId(e['last_effect_id']);
      if (!{'draft', 'active', 'disposed', 'reversed'}.contains(e['status']) ||
          !{'post', 'reverse'}.contains(a) &&
              e['current_branch_id'] != scope.branchId ||
          {'opening', 'propose', 'approve'}.contains(a) &&
              e['proposal_id'] != command.payload['proposal_id'] ||
          {'post', 'cancel'}.contains(a) && e['proposal_id'] != null ||
          a == 'opening' && (e['status'] != 'draft' || e['book_id'] != null) ||
          a == 'depreciate' &&
              (e['status'] != 'active' ||
                  e['book_id'] != command.payload['book_id'])) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'The confirmation does not match this asset transition.',
          retryable: true,
        );
      }
    }
    if (result['command_id'] != command.commandId ||
        e['id'] != command.payload['id'] ||
        e['version'] != command.expectedEntityVersion! + 1 ||
        result['warnings'] is! List ||
        (result['warnings'] as List).isNotEmpty) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The confirmation does not match the exact saved request.',
        retryable: true,
      );
    }
    return e;
  }

  Future<void> _confirmed(
    Map<String, Object?> result,
    ScopedPendingCommand sealed,
  ) async {
    final e = _verify(result, sealed.envelope);
    if (!current) {
      return;
    }
    confirmed = e;
    message = 'Confirmed. The original request succeeded.';
    _notify();
    try {
      await drafts[sealed.action]!.complete(
        scope,
        form!['id'] as String,
        sealed.envelope.commandId,
      );
      if (!current) {
        return;
      }
      local = null;
    } catch (_) {
      if (current) {
        message = 'Confirmed. Encrypted recovery cleanup needs reconciliation; do not submit another request.';
      }
      return;
    }
    try {
      await _register();
      if (current) {
        await _recover();
      }
    } on DomainError catch (cause) {
      if ({
        'PERMISSION_DENIED',
        'AUTHENTICATION_REQUIRED',
        'FEATURE_NOT_ENTITLED',
      }.contains(cause.code)) {
        _deny();
      } else if (current) {
        message =
            'Confirmed. Refresh the register when the service is available.';
      }
    } catch (_) {
      if (current) {
        message =
            'Confirmed. Refresh the register when the service is available.';
      }
    }
  }

  Future<void> send() => _run(() async {
    if (form == null || conflict || confirmed != null) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    await _access(AssetCommands.capability(a));
    if (!current) {
      return;
    }
    final sealed = await drafts[a]!.prepare(
      scope,
      id,
      a,
      form!,
      expectedVersion,
    );
    if (!current) {
      return;
    }
    local = await drafts[a]!.load(scope, id);
    if (!current) {
      return;
    }
    if (local != null) {
      recovery = [
        ...recovery.where((d) => d.action != a || d.aggregateId != id),
        AssetSavedDraft(a, local!),
      ];
    }
    _sending = true;
    _notify();
    try {
      final result = await repository.execute(sealed.envelope);
      if (current) {
        await _confirmed(result, sealed);
      }
    } on DomainError catch (cause) {
      await drafts[a]!.recordFailure(
        scope,
        id,
        sealed.envelope.commandId,
        cause,
      );
      if (!current) {
        return;
      }
      local = await drafts[a]!.load(scope, id);
      if (!current) {
        return;
      }
      recovery = [
        ...recovery.where((d) => d.action != a || d.aggregateId != id),
        if (local != null) AssetSavedDraft(a, local!),
      ];
      if ({
        'PERMISSION_DENIED',
        'AUTHENTICATION_REQUIRED',
        'FEATURE_NOT_ENTITLED',
      }.contains(cause.code)) {
        _deny();
      } else {
        error = cause.message;
      }
    } catch (_) {
      const failure = DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The result is uncertain. Reconcile the exact encrypted request.',
        retryable: true,
      );
      await drafts[a]!.recordFailure(
        scope,
        id,
        sealed.envelope.commandId,
        failure,
      );
      if (current) {
        local = await drafts[a]!.load(scope, id);
        if (current) {
          error = failure.message;
        }
      }
    } finally {
      _sending = false;
    }
  });
  Future<void> reconcile() => _run(() async {
    final sealed = pending;
    if (sealed == null || confirmed != null) {
      return;
    }
    await _access(AssetCommands.capability(sealed.action));
    if (!current) {
      return;
    }
    final row = await repository.ownReceipt(
      scope,
      sealed.envelope.idempotencyKey,
      sealed.action,
    );
    if (!current) {
      return;
    }
    if (row == null) {
      message = 'No matching receipt was found. Retry only the exact encrypted request.';
      return;
    }
    if (row['command_id'] != sealed.envelope.commandId ||
        row['idempotency_key'] != sealed.envelope.idempotencyKey) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'The receipt does not match this encrypted request.',
      );
    }
    await _confirmed(assetMap(row['response']), sealed);
  });
  Future<void> compare() => _run(() async {
    if (!conflict || form == null || {'location', 'opening'}.contains(action)) {
      return;
    }
    await _access('assets.view');
    if (!current) {
      return;
    }
    final row = await repository.detail(
      scope,
      form!['id'] as String,
      AssetHistoryKind.books,
    );
    if (current) {
      comparison = row;
    }
  });
  Future<void> adoptComparison() => _run(() async {
    if (!conflict || comparison == null || form == null || pending != null) {
      return;
    }
    final a = action!;
    await _access(AssetCommands.capability(a));
    if (!current) {
      return;
    }
    final compared = comparison!,
        fresh = await repository.detail(
          scope,
          form!['id'] as String,
          AssetHistoryKind.books,
        );
    if (!current) {
      return;
    }
    if (fresh.asset.version != compared.asset.version) {
      comparison = null;
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'The asset changed again. Compare it again.',
      );
    }
    final next = Map<String, Object?>.from(jsonDecode(jsonEncode(form)) as Map);
    if ({'approve', 'post', 'cancel'}.contains(a)) {
      if (fresh.proposal == null) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message:
              'The compared asset has no current proposal. Review its history.',
        );
      }
      next['proposal_id'] = fresh.proposal!.id;
      next['digest'] = fresh.proposal!.digest;
    } else if (a == 'depreciate') {
      next['book_id'] = fresh.asset.bookId;
      next['period_index'] = fresh.asset.postedPeriods + 1;
    } else if (a == 'reverse') {
      next['effect_id'] = fresh.asset.lastEffectId;
    }
    await drafts[a]!.save(
      scope,
      next['id'] as String,
      a,
      next,
      fresh.asset.version,
      resolveConflict: true,
    );
    if (!current) {
      return;
    }
    local = await drafts[a]!.load(scope, next['id'] as String);
    if (!current) {
      return;
    }
    form = next;
    expectedVersion = fresh.asset.version;
    comparison = null;
    selected = fresh;
    _epoch++;
  });
  Future<void> discard() => _run(() async {
    if (form == null || pending != null || confirmed != null) {
      return;
    }
    await _access(AssetCommands.capability(action!));
    if (!current) {
      return;
    }
    await drafts[action!]!.discard(scope, form!['id'] as String);
    if (current) {
      _clearForm();
      await _recover();
    }
  });
  Future<void> closeEditor() async {
    if (_sending) {
      return;
    }
    if (form != null) {
      await _save();
      if (current) {
        _clearForm();
        _notify();
      }
    }
  }

  Future<bool> canLeave() async {
    if (_sending) {
      return false;
    }
    if (_disposed) {
      return true;
    }
    if (busy) {
      return false;
    }
    try {
      await _save();
      return true;
    } catch (_) {
      message = 'Save or reconcile this asset draft before leaving.';
      _notify();
      return false;
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _clear();
    super.dispose();
  }
}
