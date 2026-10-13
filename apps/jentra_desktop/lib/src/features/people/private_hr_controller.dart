import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

enum PrivateHrView {
  contacts,
  documents,
  reviews,
  links,
  erasure,
  retention,
  myAccount,
}

final privateHrRepositoryProvider = Provider<HrRepository?>((ref) => null);
final privateHrFilesProvider = Provider<HrFiles>(
  (ref) => const NativeHrFiles(),
);
final privateHrControllerProvider = Provider.autoDispose<PrivateHrController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider),
      caps = ref.watch(businessCapabilitiesProvider);
  final repository = ref.watch(privateHrRepositoryProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('people.view') ?? false)) {
    return null;
  }
  final c = PrivateHrController(
    scope: scope,
    repository: repository,
    drafts: PrivateHrDraftStore(
      ref.watch(encryptedDraftRepositoryProvider),
      repository.authorize,
    ),
    files: ref.watch(privateHrFilesProvider),
    permissions: caps.value!,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(
    connectivityStateProvider,
    (_, v) => c.setOnline(v.value == ConnectivityState.online),
  );
  ref.onDispose(c.dispose);
  unawaited(c.initialize());
  return c;
});

final class PrivateHrController extends ChangeNotifier {
  PrivateHrController({
    required this.scope,
    required this.repository,
    required this.drafts,
    required this.files,
    required Set<String> permissions,
    required this.online,
    DateTime Function()? clock,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions),
       clock = clock ?? (() => DateTime.now().toUtc()) {
    view = views.first;
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final HrRepository repository;
  final PrivateHrDraftStore drafts;
  final HrFiles files;
  final Set<String> permissions;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  Timer? _timer;
  int _accessEpoch = 0;
  int? _operationEpoch;
  late PrivateHrView view;
  bool online, busy = false, accessDenied = false, _disposed = false;
  String? error,
      message,
      cursor,
      inboxCursor,
      historyCursor,
      subjectCursor,
      preparedExportId;
  String search = '';
  List<HrRecord> subjects = [], rows = [], history = [], inbox = [];
  List<PrivateHrRecovery> recovery = [];
  HrRecord? subject, selfIdentity, selectedReview, previewDocument;
  HrProfileState? contactState, comparedContacts;
  HrPolicyState? policyState;
  HrRecord? comparedReview;
  Map<String, Object?>? form;
  int expectedVersion = 0;
  PrivateHrDraft? local;
  PrivateHrRecovery? expiredRecovery;
  HrConfirmation? confirmed;
  Uint8List? previewBytes, uploadBytes;
  DateTime? _formExpiry;
  bool get current =>
      !_disposed &&
      !accessDenied &&
      (_operationEpoch == null || _operationEpoch == _accessEpoch);
  bool has(String p) => permissions.contains(p);
  List<PrivateHrView> get views => [
    if (has('people.hr.private.view') || has('people.hr.private.manage'))
      PrivateHrView.contacts,
    if (has('people.hr.documents.view')) PrivateHrView.documents,
    if (has('people.reviews.view') || has('people.reviews.manage'))
      PrivateHrView.reviews,
    if (has('people.account_links.manage')) PrivateHrView.links,
    if (has('people.hr.erase')) PrivateHrView.erasure,
    if (has('people.hr.retention.manage')) PrivateHrView.retention,
    PrivateHrView.myAccount,
  ];
  String? get subjectCapability => switch (view) {
    PrivateHrView.contacts =>
      has('people.hr.private.view')
          ? 'people.hr.private.view'
          : 'people.hr.private.manage',
    PrivateHrView.documents => 'people.hr.documents.view',
    PrivateHrView.reviews =>
      has('people.reviews.view')
          ? 'people.reviews.view'
          : 'people.reviews.manage',
    PrivateHrView.links => 'people.account_links.manage',
    PrivateHrView.erasure => 'people.hr.erase',
    _ => null,
  };
  String? get employeeId =>
      form?['employee_id'] as String? ?? subject?.id ?? selfIdentity?.id;
  String? get action => form?['action'] as String?;
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked => busy || !current || local?.pending != null || conflict;
  bool get canUpload =>
      has('people.hr.documents.view') && has('people.hr.documents.manage');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _wipe(Uint8List? bytes) {
    bytes?.fillRange(0, bytes.length, 0);
  }

  void closePreview() {
    _wipe(previewBytes);
    previewBytes = null;
    previewDocument = null;
    _notify();
  }

  void _clearForm() {
    form = null;
    local = null;
    _formExpiry = null;
    comparedContacts = null;
    comparedReview = null;
    expiredRecovery = null;
    _wipe(uploadBytes);
    uploadBytes = null;
  }

  void _clearVisible() {
    _clearForm();
    closePreview();
    subject = null;
    selfIdentity = null;
    selectedReview = null;
    subjects = [];
    rows = [];
    history = [];
    inbox = [];
    recovery = [];
    contactState = null;
    policyState = null;
    preparedExportId = null;
    confirmed = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _clearVisible();
    super.dispose();
  }

  void setOnline(bool value) {
    if (online != value) {
      // Reconnecting does not restore the authority of an earlier request.
      _accessEpoch++;
    }
    online = value;
    if (!value) {
      _clearVisible();
      message = 'Connect to recheck private access before loading content.';
    }
    _notify();
  }

  bool _denied(Object e) =>
      e is DomainError &&
      {
        'PERMISSION_DENIED',
        'FEATURE_NOT_ENTITLED',
        'AUTHENTICATION_REQUIRED',
      }.contains(e.code);
  Future<void> _run(Future<void> Function() work) async {
    final expired = _formExpiry != null && !_formExpiry!.isAfter(clock());
    if (expired) {
      _clearForm();
      closePreview();
      message = 'Private draft text expired after 24 hours. Resolve its minimal receipt in recovery.';
    }
    if (!current || busy) return;
    _operationEpoch = _accessEpoch;
    busy = true;
    error = null;
    _notify();
    try {
      _connected();
      if (expired) await _recover();
      if (!current) return;
      await work();
    } catch (e) {
      if (!current) return;
      if (_denied(e)) {
        accessDenied = true;
        _clearVisible();
      }
      if (e is DomainError &&
          {'HR_CONTENT_EXPIRED', 'MFA_REQUIRED'}.contains(e.code)) {
        _clearForm();
        closePreview();
        if (e.code == 'HR_CONTENT_EXPIRED') {
          contactState = null;
          rows = [];
          history = [];
          selectedReview = null;
        }
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Private HR is unavailable. Sealed recovery is retained.';
    } finally {
      _operationEpoch = null;
      busy = false;
      _notify();
    }
  }

  void _connected() {
    if (!online || !current) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect to verify current private HR access.',
      );
    }
  }

  Future<void> _recover() async {
    try {
      final result = await drafts.recovery(scope, permissions);
      if (current) recovery = result;
    } on DomainError catch (e) {
      if (e.code != 'MFA_REQUIRED') rethrow;
      if (current) recovery = [];
    }
  }

  Future<void> initialize() => _run(() async {
    await _reload();
    await _recover();
  });
  Future<void> refresh() => _run(() async {
    await _reload();
    await _recover();
  });
  Future<void> checkAccess() => _run(() async {
    if (_formExpiry != null && !_formExpiry!.isAfter(clock())) {
      _clearForm();
      closePreview();
      message = 'Private draft text expired after 24 hours. Resolve any minimal receipt in recovery.';
      await _recover();
    }
    await repository.authorize(
      scope,
      form?['employee_id'] as String? ?? subject?.id ?? selfIdentity?.id,
      action == null
          ? (previewDocument != null
                ? 'people.hr.documents.view'
                : subjectCapability ??
                      (selfIdentity != null
                          ? 'people.self.view'
                          : 'people.view'))
          : HrCommands.capability(action!),
    );
  });
  Future<void> changeView(PrivateHrView value) => _run(() async {
    if (!views.contains(value)) return;
    if (!await canLeave()) {
      throw const DomainError(
        code: 'DRAFT_UNSAVED',
        message: 'Save or resolve the private draft before changing workspace.',
      );
    }
    _clearVisible();
    view = value;
    cursor = null;
    historyCursor = null;
    subjectCursor = null;
    search = '';
    await _reload();
    await _recover();
  });
  Future<void> filter(String query) => _run(() async {
    if (query.length > 160) {
      throw const FormatException('Search is limited to 160 characters.');
    }
    search = query;
    await _subjects();
  });
  Future<void> _subjects({bool more = false}) async {
    final cap = subjectCapability;
    if (cap == null) return;
    final result = await repository.subjects(
      scope,
      cap,
      search: search,
      after: more ? subjectCursor : null,
    );
    if (!current) return;
    subjects = [if (more) ...subjects, ...result.items];
    subjectCursor = result.nextCursor;
  }

  Future<void> moreSubjects() => _run(() => _subjects(more: true));
  Future<void> _reload() async {
    if (subjectCapability != null) {
      await _subjects();
      if (subject != null) await _loadSubject();
    } else if (view == PrivateHrView.retention) {
      final result = await repository.policy(scope);
      if (current) policyState = result;
    } else {
      final proposals = await repository.page(scope, HrCollection.inbox);
      if (!current) return;
      inbox = proposals.items;
      inboxCursor = proposals.nextCursor;
      if (has('people.self.view')) {
        try {
          final identity = await repository.self(scope);
          if (!current) return;
          selfIdentity = identity;
          subject = null;
          final shared = await repository.page(
            scope,
            HrCollection.reviews,
            employee: identity.id,
          );
          if (current) {
            rows = shared.items;
            cursor = shared.nextCursor;
          }
        } on DomainError catch (e) {
          if (e.code != 'SELF_LINK_REQUIRED') rethrow;
          selfIdentity = null;
          rows = [];
        }
      }
    }
  }

  Future<void> openSubject(HrRecord value) => _run(() async {
    if (value.kind != HrRecordKind.subject || subjectCapability == null) return;
    if (!await canLeave()) {
      throw const DomainError(
        code: 'DRAFT_UNSAVED',
        message: 'Resolve the current private draft first.',
      );
    }
    _clearForm();
    closePreview();
    subject = value;
    contactState = null;
    rows = [];
    history = [];
    selectedReview = null;
    preparedExportId = null;
    cursor = null;
    historyCursor = null;
    await _loadSubject();
  });
  Future<void> _loadSubject({bool more = false}) async {
    final id = subject?.id ?? selfIdentity?.id;
    if (id == null) return;
    if (view == PrivateHrView.contacts) {
      if (!has('people.hr.private.view')) return;
      final result = await repository.contacts(
        scope,
        id,
        after: more ? historyCursor : null,
      );
      if (!current) return;
      contactState = result;
      history = [if (more) ...history, ...result.history.items];
      historyCursor = result.history.nextCursor;
    } else {
      final collection = switch (view) {
        PrivateHrView.documents => HrCollection.documents,
        PrivateHrView.links => HrCollection.links,
        PrivateHrView.erasure => HrCollection.erasure,
        _ => HrCollection.reviews,
      };
      if (view == PrivateHrView.reviews && !has('people.reviews.view')) return;
      final page = await repository.page(
        scope,
        collection,
        employee: id,
        after: more ? cursor : null,
      );
      if (!current) return;
      rows = [if (more) ...rows, ...page.items];
      cursor = page.nextCursor;
    }
  }

  Future<void> moreRows() => _run(() => _loadSubject(more: true));
  Future<void> moreInbox() => _run(() async {
    if (view != PrivateHrView.myAccount || inboxCursor == null) return;
    final page = await repository.page(
      scope,
      HrCollection.inbox,
      after: inboxCursor,
    );
    if (current) {
      inbox = [...inbox, ...page.items];
      inboxCursor = page.nextCursor;
    }
  });
  Future<List<HrRecord>> choices(String query, {String? after}) async {
    _connected();
    final cap = subjectCapability ?? 'people.reviews.manage';
    final result = await repository.subjects(
      scope,
      cap,
      search: query,
      after: after,
    );
    return current ? result.items : [];
  }

  Future<HrPage> memberships({String? after}) =>
      repository.page(scope, HrCollection.memberships, after: after);
  Future<void> openReview(HrRecord item, {bool more = false}) => _run(() async {
    if (item.kind != HrRecordKind.review || employeeId == null) return;
    selectedReview = item;
    if (!has('people.reviews.view')) return;
    final page = await repository.page(
      scope,
      HrCollection.reviewHistory,
      employee: employeeId,
      reviewId: item.id,
      after: more ? historyCursor : null,
    );
    if (!current) return;
    history = [if (more) ...history, ...page.items];
    historyCursor = page.nextCursor;
  });
  Future<void> begin(
    String commandAction, {
    HrRecord? record,
    HrRecord? reviewer,
    HrRecord? membership,
  }) => _run(() async {
    if (form != null || !has(HrCommands.capability(commandAction))) return;
    final employee = record?.kind == HrRecordKind.inbox
        ? record!.text('employee_id')
        : subject?.id ?? selfIdentity?.id;
    final entityAction = {
      'policy_create',
      'cycle_close',
      'hold',
      'release_hold',
    }.contains(commandAction);
    if (!entityAction && employee == null) return;
    await repository.authorize(
      scope,
      entityAction ? null : employee,
      HrCommands.capability(commandAction),
    );
    if (!current) return;
    final today = clock().toIso8601String().substring(0, 10);
    final row = {'review_create', 'link_initiate'}.contains(commandAction)
        ? null
        : record ?? selectedReview;
    final id = entityAction
        ? policyState?.policy?.id ?? _uuid.v4()
        : {'profile_save', 'erase_request'}.contains(commandAction)
        ? employee!
        : row?.id ?? _uuid.v4();
    expectedVersion = entityAction
        ? policyState?.policy?.version ?? 0
        : commandAction == 'profile_save'
        ? contactState?.profile?.version ?? 0
        : {
            'review_create',
            'link_initiate',
            'erase_request',
            'export_prepare',
          }.contains(commandAction)
        ? 0
        : row?.version ?? 0;
    form = {
      'action': commandAction,
      'id': id,
      if (!entityAction) 'employee_id': employee,
    };
    switch (commandAction) {
      case 'profile_save':
        form!.addAll({
          'revision_id': _uuid.v4(),
          'body':
              contactState?.profile?.body ??
              {for (final f in hrContactFields) f: null},
          'reason': '',
        });
      case 'review_create':
        form!.addAll({
          'reviewer_id': reviewer?.id,
          'revision_id': _uuid.v4(),
          'start_date': today,
          'end_date_exclusive': clock()
              .add(const Duration(days: 30))
              .toIso8601String()
              .substring(0, 10),
          'body': {
            'objectives': [''],
            'comments': null,
          },
          'reason': '',
        });
      case 'review_revise':
        form!.addAll({
          'revision_id': _uuid.v4(),
          'body': row?.body,
          'reason': '',
        });
      case 'review_decide':
        form!['private_text'] = '';
      case 'link_initiate':
        form!.addAll({
          'membership_id': membership?.id,
          'user_id': membership?.text('user_id'),
        });
      case 'policy_create':
        form!['purpose'] = 'Synthetic Wave 4 acceptance cycle';
      case 'cycle_close':
        form!['closed_at'] = clock().toIso8601String();
      case 'hold':
        form!.addAll({
          'reason': '',
          'review_date': clock()
              .add(const Duration(days: 7))
              .toIso8601String()
              .substring(0, 10),
        });
      case 'release_hold':
        form!['reason'] = '';
    }
    _formExpiry = clock().add(const Duration(hours: 24));
    local = null;
    confirmed = null;
    message = null;
  });
  void edit(String field, Object? value) {
    if (form == null || locked || !has(HrCommands.capability(action!))) return;
    if (HrCommands.fields[action!]?.contains(field) != true ||
        {'id', 'action', 'employee_id', 'revision_id'}.contains(field)) {
      return;
    }
    form = {...form!, field: value};
    _notify();
  }

  void editContact(String field, String value) {
    if (action != 'profile_save' || !hrContactFields.contains(field)) return;
    edit('body', {
      ...hrMap(form!['body']),
      field: value.isEmpty ? null : value,
    });
  }

  Future<void> beginDocument() => _run(() async {
    if (!canUpload || subject == null || form != null) return;
    await repository.authorize(
      scope,
      subject!.id,
      'people.hr.documents.manage',
    );
    final picked = await files.chooseUpload();
    if (picked == null) return;
    try {
      await repository.authorize(
        scope,
        subject!.id,
        'people.hr.documents.manage',
      );
      if (!current) return;
      uploadBytes = Uint8List.fromList(picked.bytes);
      form = {
        'action': 'document_reserve',
        'id': _uuid.v4(),
        'employee_id': subject!.id,
        'classification': 'contact-support',
        'purpose': '',
        'mime': picked.mime,
        'byte_size': picked.bytes.length,
        'checksum': picked.checksum,
      };
      expectedVersion = 0;
      _formExpiry = clock().add(const Duration(hours: 24));
      local = null;
      confirmed = null;
    } finally {
      _wipe(picked.bytes);
    }
  });
  Future<void> chooseReservedFile(HrRecord doc) => _run(() async {
    if (!canUpload || employeeId == null) return;
    await repository.authorize(scope, employeeId, 'people.hr.documents.manage');
    final picked = await files.chooseUpload();
    if (picked == null) return;
    try {
      await repository.authorize(
        scope,
        employeeId,
        'people.hr.documents.manage',
      );
      if (!current) return;
      if (picked.checksum != doc.text('checksum') ||
          picked.mime != doc.text('mime') ||
          picked.bytes.length != doc.toJson()['byte_size']) {
        throw const FormatException(
          'Choose the exact file reserved for this document.',
        );
      }
      _wipe(uploadBytes);
      uploadBytes = Uint8List.fromList(picked.bytes);
      if (form == null) {
        form = {
          'action': 'document_complete',
          'id': doc.id,
          'employee_id': employeeId,
        };
        expectedVersion = doc.version;
        local = null;
        _formExpiry = clock().add(const Duration(hours: 24));
      }
    } finally {
      _wipe(picked.bytes);
    }
  });
  Future<void> choosePendingFile() => _run(() async {
    if (action != 'document_complete' || employeeId == null) return;
    final page = await repository.page(
      scope,
      HrCollection.documents,
      employee: employeeId,
    );
    if (!current) return;
    final doc = page.items.where((d) => d.id == form!['id']).firstOrNull;
    if (doc == null) {
      throw const FormatException(
        'Reload the reserved document before retrying.',
      );
    }
    final picked = await files.chooseUpload();
    if (picked == null) return;
    try {
      await repository.authorize(
        scope,
        employeeId,
        'people.hr.documents.manage',
      );
      if (!current) return;
      if (picked.checksum != doc.text('checksum') ||
          picked.mime != doc.text('mime') ||
          picked.bytes.length != doc.toJson()['byte_size']) {
        throw const FormatException('Choose the exact reserved file.');
      }
      _wipe(uploadBytes);
      uploadBytes = Uint8List.fromList(picked.bytes);
    } finally {
      _wipe(picked.bytes);
    }
  });
  Future<void> save() => _run(() async {
    if (form == null || locked && local?.pending != null || conflict) return;
    await drafts.save(
      scope,
      form!['employee_id'] as String?,
      form!['id'] as String,
      action!,
      form!,
      expectedVersion,
    );
    if (!current) return;
    final saved = await drafts.load(
      scope,
      form!['employee_id'] as String?,
      form!['id'] as String,
      action!,
    );
    if (!current) return;
    local = saved;
    _formExpiry = local?.expiresAt;
    message = 'Private draft encrypted for up to 24 hours.';
    await _recover();
  });
  Future<void> resume(PrivateHrRecovery item) => _run(() async {
    if (form != null) return;
    final draft = await drafts.load(
      scope,
      item.employeeId,
      item.aggregateId,
      item.actionHint,
    );
    if (!current) return;
    if (draft == null) {
      expiredRecovery = item;
      message = 'Private text has expired. Check its minimal command receipt.';
      return;
    }
    local = draft;
    form = draft.form;
    expectedVersion = draft.version;
    _formExpiry = draft.expiresAt;
    comparedContacts = null;
    comparedReview = null;
    message = 'Exact private recovery restored with current access.';
  });
  Future<void> resolveExpired() => _run(() async {
    final item = expiredRecovery;
    if (item == null) return;
    final stub = await drafts.expiredReceipt(
      scope,
      item.employeeId,
      item.aggregateId,
      item.actionHint,
    );
    if (stub == null) {
      expiredRecovery = null;
      await _recover();
      return;
    }
    final result = await repository.receipt(
      scope,
      stub['command_id'] as String,
    );
    if (!current) return;
    if (result == null) {
      message = 'No confirmation is recorded. Original private text is expired; this request stays blocked for a controlled owner review.';
      return;
    }
    if (result.entity['id'] != item.aggregateId ||
        result.entity['employee_id'] != item.employeeId ||
        result.entity['action'] != stub['action'] ||
        result.version != (stub['expected_version'] as int) + 1) {
      throw const FormatException('Minimal receipt does not match recovery.');
    }
    confirmed = result;
    await drafts.complete(
      scope,
      item.employeeId,
      item.aggregateId,
      item.actionHint,
      result.commandId,
    );
    if (!current) return;
    expiredRecovery = null;
    message =
        'Server confirmation resolved; expired private text remains erased.';
    await _recover();
  });
  Future<void> discard() => _run(() async {
    if (form == null) return;
    await drafts.discard(
      scope,
      form!['employee_id'] as String?,
      form!['id'] as String,
      action!,
    );
    if (!current) return;
    _clearForm();
    await _recover();
    message = 'Private draft discarded.';
  });
  Future<bool> canLeave() async {
    if (!current || form == null || local?.pending != null || conflict) {
      return true;
    }
    if (!online) return false;
    try {
      await drafts.save(
        scope,
        form!['employee_id'] as String?,
        form!['id'] as String,
        action!,
        form!,
        expectedVersion,
      );
      return current;
    } catch (_) {
      return false;
    }
  }

  Future<void> compare() => _run(() async {
    if (!conflict || form == null) return;
    if (action == 'profile_save') {
      final result = await repository.contacts(scope, employeeId!);
      if (current) comparedContacts = result;
    } else if (action!.startsWith('review_')) {
      final page = await repository.page(
        scope,
        HrCollection.reviews,
        employee: employeeId!,
      );
      if (current) {
        comparedReview = page.items
            .where((r) => r.id == form!['id'])
            .firstOrNull;
      }
    } else {
      message = 'Reload and compare the current workflow. Discard this unconfirmed draft before choosing a fresh action.';
      await _reload();
      return;
    }
    message =
        'Compare current private content and status before retaining edits.';
  });
  Future<void> retainCompared() => _run(() async {
    if (!conflict || form == null) return;
    final version = action == 'profile_save'
        ? comparedContacts?.profile?.version
        : comparedReview?.version;
    if (version == null || version <= expectedVersion) return;
    if (action != 'profile_save' && action != 'review_revise') {
      throw const FormatException(
        'Choose the current workflow action after discarding this conflict.',
      );
    }
    form = {...form!, 'revision_id': _uuid.v4()};
    await drafts.save(
      scope,
      employeeId,
      form!['id'] as String,
      action!,
      form!,
      version,
      compared: true,
    );
    if (!current) return;
    expectedVersion = version;
    final saved = await drafts.load(
      scope,
      employeeId,
      form!['id'] as String,
      action!,
    );
    if (!current) return;
    local = saved;
    message = 'Edits retained against the compared version. Review before confirming.';
  });
  Future<void> prepareExport({HrRecord? review}) => _run(() async {
    if (form != null || !has('people.hr.export') || subject == null) return;
    final source = review ?? contactState?.profile;
    if (source == null) return;
    final sourceCap = review == null
        ? 'people.hr.private.view'
        : 'people.reviews.view';
    await repository.authorize(scope, subject!.id, 'people.hr.export');
    await repository.authorize(scope, subject!.id, sourceCap);
    if (!current) return;
    form = {
      'action': 'export_prepare',
      'id': _uuid.v4(),
      'employee_id': subject!.id,
      'kind': review == null ? 'profile' : 'review',
      'source_id': source.id,
      'source_version': source.version,
      'revision_id': source.text('revision_id'),
    };
    expectedVersion = 0;
    local = null;
    _formExpiry = clock().add(const Duration(hours: 24));
    confirmed = null;
  });
  Future<void> writePreparedExport() => _run(() async {
    final id = preparedExportId;
    if (id == null || !has('people.hr.export')) return;
    final path = await files.chooseExport('private-hr-$id.json');
    if (path == null || !current) return;
    final row = await repository.exportContent(scope, id);
    if (!current) return;
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(row)),
    );
    try {
      await repository.authorize(
        scope,
        row['employee_id'] as String,
        'people.hr.export',
      );
      await repository.authorize(
        scope,
        row['employee_id'] as String,
        row['kind'] == 'profile'
            ? 'people.hr.private.view'
            : 'people.reviews.view',
      );
      if (!current) return;
      await files.write(path, bytes, 'application/json');
      if (current) message = 'Private export written to the file you selected.';
    } finally {
      _wipe(bytes);
    }
  });
  Future<void> preview(HrRecord doc) => _run(() async {
    if (subject == null || doc.text('status') != 'active') return;
    closePreview();
    final bytes = await repository.document(scope, subject!.id, doc);
    if (!current) {
      _wipe(bytes);
      return;
    }
    previewDocument = doc;
    previewBytes = bytes;
  });
  Future<void> exportDocument(HrRecord doc) => _run(() async {
    if (subject == null ||
        !has('people.hr.export') ||
        doc.text('status') != 'active') {
      return;
    }
    final extension = switch (doc.text('mime')) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'application/pdf' => 'pdf',
      _ => 'txt',
    };
    final path = await files.chooseExport(
      'private-document-${doc.id}.$extension',
    );
    if (path == null || !current) return;
    final bytes = await repository.document(
      scope,
      subject!.id,
      doc,
      export: true,
    );
    try {
      await repository.authorize(scope, subject!.id, 'people.hr.export');
      await repository.authorize(
        scope,
        subject!.id,
        'people.hr.documents.view',
      );
      if (!current) return;
      await files.write(path, bytes, doc.text('mime')!);
      if (current) message = 'Private document exported to your selected file.';
    } finally {
      _wipe(bytes);
    }
  });
  Future<void> submit() => _run(() async {
    if (form == null || conflict) return;
    final frozen = hrMap(jsonDecode(jsonEncode(form))),
        a = action!,
        id = frozen['id'] as String,
        emp = frozen['employee_id'] as String?;
    final pending =
        local?.pending ??
        await drafts.prepare(scope, emp, id, a, frozen, expectedVersion);
    final saved = await drafts.load(scope, emp, id, a);
    if (!current) return;
    local = saved;
    _formExpiry = saved?.expiresAt;
    _notify();
    HrConfirmation result;
    try {
      if (a == 'document_complete') {
        final docs = await repository.page(
          scope,
          HrCollection.documents,
          employee: emp,
        );
        final doc = docs.items.where((d) => d.id == id).firstOrNull;
        if (doc == null || uploadBytes == null) {
          throw const DomainError(
            code: 'FILE_REQUIRED',
            message:
                'Choose the exact reserved file to retry its sealed upload.',
          );
        }
        result = await repository.upload(pending.envelope, doc, uploadBytes!);
      } else {
        result = await repository.command(pending.envelope);
      }
    } on DomainError catch (e) {
      try {
        await drafts.failure(scope, emp, id, a, pending.envelope.commandId, e);
        if (current) {
          final saved = await drafts.load(scope, emp, id, a);
          if (current) local = saved;
        }
      } catch (_) {}
      rethrow;
    }
    if (!current) return;
    confirmed = result;
    if (a == 'export_prepare') preparedExportId = id;
    message = a == 'review_acknowledge'
        ? 'Receipt acknowledged. This records receipt without agreement or a pay change.'
        : a == 'erase_request'
        ? 'Erasure requested. Access is closed; worker completion remains a separate result.'
        : 'Private HR change confirmed.';
    try {
      await drafts.complete(scope, emp, id, a, pending.envelope.commandId);
    } catch (_) {
      error = 'Change confirmed. Local cleanup needs a retry of the original request.';
      return;
    }
    if (!current) return;
    _clearForm();
    try {
      await _reload();
      await _recover();
    } catch (e) {
      if (_denied(e)) {
        accessDenied = true;
        _clearVisible();
      } else {
        error = 'Change confirmed. Reload to refresh the workspace.';
      }
    }
  });
}
