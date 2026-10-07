import 'package:flutter/foundation.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';
import 'package:uuid/uuid.dart';

final class ExpenseEvidenceController extends ChangeNotifier {
  ExpenseEvidenceController({
    required this.scope,
    required this.projectId,
    required this.expenseId,
    required this.repository,
    required this.drafts,
    required this.files,
    List<ExpenseEvidenceProof> initialProofs = const [],
    this.editable = true,
  }) : selected = {for (final proof in initialProofs) proof.id: proof};
  final TenantContext scope;
  final String projectId, expenseId;
  final ExpenseEvidenceRepository repository;
  final SensitiveExpenseEvidenceDraftStore drafts;
  final ExpenseEvidenceFiles files;
  final bool editable;
  final Map<String, ExpenseEvidenceProof> selected;
  List<ExpenseEvidenceDocument> documents = [];
  List<({String id, String cap})> recoveries = [];
  List<String> policyRecoveries = [];
  bool busy = false,
      available = false,
      canManage = false,
      canExport = false,
      canRetain = false;
  bool canConfigurePolicy = false;
  bool _alive = true;
  int _epoch = 0;
  String? error, notice, nextAfter;
  Uint8List? preview;
  ExpenseEvidenceDocument? previewDocument;
  ExpenseEvidenceConfirmation? confirmed;
  SensitiveExpenseEvidenceDraft? comparison;
  ExpenseEvidenceDocument? comparisonCurrent;
  String? comparisonCapability;
  List<ExpenseEvidenceProof> get proofs =>
      selected.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  void _guard(int token) {
    if (!_alive || token != _epoch) throw StateError('Evidence view expired.');
  }

  Future<void> _operation(Future<void> Function(int) work) async {
    if (busy || !_alive) return;
    final token = ++_epoch;
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await work(token);
      _guard(token);
    } catch (e) {
      if (!_alive || token != _epoch) return;
      if (e is DomainError) {
        error = e.message;
        if ({
          'PERMISSION_DENIED',
          'AUTHENTICATION_REQUIRED',
          'FEATURE_NOT_INSTALLED',
        }.contains(e.code)) {
          documents = [];
          recoveries = [];
          policyRecoveries = [];
          canConfigurePolicy = false;
          selected.clear();
          available = false;
          canManage = false;
          canExport = false;
          canRetain = false;
          preview = null;
          previewDocument = null;
          comparison = null;
          comparisonCurrent = null;
        }
      } else {
        error = 'Check the bounded evidence fields or retry the exact saved request.';
      }
    } finally {
      if (_alive && token == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _cap(String cap, int token, {bool policy = false}) async {
    try {
      await repository.authorize(
        scope,
        policy ? null : projectId,
        policy ? null : expenseId,
        cap,
      );
      _guard(token);
      return true;
    } on DomainError catch (e) {
      if (e.code == 'PERMISSION_DENIED') return false;
      rethrow;
    }
  }

  Future<void> _refresh(int token, {bool more = false}) async {
    final page = await repository.documents(
      scope,
      projectId,
      expenseId,
      after: more ? nextAfter : null,
    );
    _guard(token);
    documents = more ? [...documents, ...page.items] : page.items;
    nextAfter = page.nextAfter;
    final recovery = <({String id, String cap})>[];
    for (final cap in [
      if (canManage) expenseEvidenceManage,
      if (canRetain) expenseEvidenceRetention,
    ]) {
      final ids = await drafts.recoveryIds(scope, projectId, expenseId, cap);
      _guard(token);
      recovery.addAll(ids.map((id) => (id: id, cap: cap)));
    }
    recoveries = recovery;
    policyRecoveries = canConfigurePolicy
        ? await drafts.recoveryIds(scope, null, null, expenseEvidenceRetention)
        : [];
    _guard(token);
  }

  Future<void> load({bool more = false}) => _operation((token) async {
    available = await repository.authorize(
      scope,
      projectId,
      expenseId,
      expenseEvidenceView,
    );
    _guard(token);
    canManage = editable && await _cap(expenseEvidenceManage, token);
    canRetain = await _cap(expenseEvidenceRetention, token);
    canConfigurePolicy = await _cap(
      expenseEvidenceRetention,
      token,
      policy: true,
    );
    canExport = await _cap(expenseEvidenceExport, token);
    await _refresh(token, more: more);
    if (!available) notice = 'Protected evidence delivery is unavailable until the separate retention policy and worker are verified.';
  });
  void select(ExpenseEvidenceDocument doc, bool value) {
    if (!editable || !canManage || busy || value && !doc.isActive) return;
    if (value && selected.length >= 10 && !selected.containsKey(doc.id)) {
      error = 'Select at most ten documents.';
      notifyListeners();
      return;
    }
    if (value) {
      selected[doc.id] = doc.proof;
    } else {
      selected.remove(doc.id);
    }
    notifyListeners();
  }

  Future<ExpenseEvidenceConfirmation> _confirm(
    ExpenseEvidenceConfirmation result,
    String id,
    String cap,
    int token, {
    bool policy = false,
  }) async {
    _guard(token);
    confirmed = result;
    // Server success is retained independently of local acknowledgement cleanup.
    try {
      await drafts.acknowledge(
        scope,
        policy ? null : projectId,
        policy ? null : expenseId,
        id,
        cap,
        result,
      );
      _guard(token);
    } catch (e) {
      _guard(token);
      notice = 'Evidence is confirmed. Its encrypted receipt still needs local cleanup.';
    }
    return result;
  }

  Future<ExpenseEvidenceConfirmation> _send(
    Map<String, Object?> payload,
    int version,
    int token, {
    ExpenseEvidenceDocument? doc,
    ExpensePickedDocument? file,
  }) async {
    final action = payload['action'] as String,
        cap = ExpenseEvidenceCommands.capability(action),
        id = payload['id'] as String;
    final policy = action == 'policy_create',
        p = action == 'policy_create' ? null : projectId,
        x = action == 'policy_create' ? null : expenseId;
    await drafts.save(scope, payload, version);
    _guard(token);
    final pending = await drafts.seal(scope, p, x, id, cap);
    _guard(token);
    try {
      final result = doc == null
          ? await repository.command(pending.envelope)
          : await repository.upload(pending.envelope, doc, file!.bytes);
      return await _confirm(result, id, cap, token, policy: policy);
    } on DomainError catch (e) {
      await drafts.releaseRejected(scope, p, x, id, cap, e);
      _guard(token);
      rethrow;
    }
  }

  Future<void> uploadNew(String purpose) => _operation((token) async {
    if (!canManage || !available) {
      throw const DomainError(
        code: 'EVIDENCE_UNAVAILABLE',
        message:
            'Current evidence management and verified delivery are required.',
      );
    }
    final file = await files.chooseUpload();
    _guard(token);
    if (file == null) return;
    final id = const Uuid().v4();
    await _send(
      {
        'action': 'reserve',
        'id': id,
        'project_id': projectId,
        'expense_id': expenseId,
        'mime': file.mime,
        'byte_size': file.bytes.length,
        'checksum': file.checksum,
        'purpose': purpose.trim(),
      },
      0,
      token,
    );
    await _refresh(token);
    final doc = documents.singleWhere((d) => d.id == id);
    await _send(
      {
        'action': 'complete',
        'id': id,
        'project_id': projectId,
        'expense_id': expenseId,
      },
      doc.recordVersion,
      token,
      doc: doc,
      file: file,
    );
    await _refresh(token);
    final active = documents.singleWhere((d) => d.id == id);
    if (active.isActive) selected[id] = active.proof;
  });
  Future<void> retry(String id, String cap) => _operation((token) async {
    final receipt = await drafts.receipt(scope, projectId, expenseId, id, cap);
    _guard(token);
    if (receipt != null) {
      final result = await repository.receipt(
        scope,
        receipt['command_id'] as String,
      );
      _guard(token);
      if (result != null) {
        await _confirm(result, id, cap, token);
        await _refresh(token);
        return;
      }
    }
    final draft = await drafts.read(scope, projectId, expenseId, id, cap);
    _guard(token);
    if (draft == null) {
      notice = 'Private metadata expired. The minimal encrypted receipt remains until its exact outcome is known.';
      return;
    }
    final pending = draft.pending;
    if (pending == null) {
      comparison = draft;
      comparisonCapability = cap;
      comparisonCurrent = documents.where((d) => d.id == id).firstOrNull;
      notice = 'Compare saved fields with the current document before making a new request.';
      return;
    }
    try {
      ExpenseEvidenceConfirmation result;
      if (pending.action == 'complete') {
        final file = await files.chooseUpload();
        _guard(token);
        if (file == null) return;
        final doc = documents.singleWhere((d) => d.id == id);
        result = await repository.upload(pending.envelope, doc, file.bytes);
      } else {
        result = await repository.command(pending.envelope);
      }
      await _confirm(result, id, cap, token);
      await _refresh(token);
    } on DomainError catch (e) {
      await drafts.releaseRejected(scope, projectId, expenseId, id, cap, e);
      _guard(token);
      rethrow;
    }
  });
  Future<void> submitComparison() => _operation((token) async {
    final draft = comparison,
        doc = comparisonCurrent,
        cap = comparisonCapability;
    if (draft == null || cap == null) return;
    final payload = draft.payload;
    if (payload['action'] == 'complete') {
      notice =
          'Choose the exact reserved file through the document upload action.';
      return;
    }
    await _send(payload, doc?.recordVersion ?? draft.version, token);
    comparison = null;
    comparisonCurrent = null;
    comparisonCapability = null;
    await _refresh(token);
  });
  Future<void> discardRecovery(String id, String cap) =>
      _operation((token) async {
        await drafts.discard(scope, projectId, expenseId, id, cap);
        _guard(token);
        await _refresh(token);
      });
  Future<void> finishUpload(ExpenseEvidenceDocument doc) =>
      _operation((token) async {
        final file = await files.chooseUpload();
        _guard(token);
        if (file == null) return;
        await _send(
          {
            'action': 'complete',
            'id': doc.id,
            'project_id': projectId,
            'expense_id': expenseId,
          },
          doc.recordVersion,
          token,
          doc: doc,
          file: file,
        );
        await _refresh(token);
        final active = documents.singleWhere((d) => d.id == doc.id);
        if (active.isActive) selected[doc.id] = active.proof;
      });
  Future<void> retention(
    ExpenseEvidenceDocument doc,
    String action,
    String reason, {
    String? reviewDate,
  }) => _operation((token) async {
    final payload = <String, Object?>{
      'action': action,
      'id': doc.id,
      'project_id': projectId,
      'expense_id': expenseId,
      'reason': reason.trim(),
    };
    if (action == 'hold') payload['review_date'] = reviewDate;
    await _send(payload, doc.recordVersion, token);
    await _refresh(token);
  });
  Future<void> createPolicy(int days, String purpose) =>
      _operation((token) async {
        await repository.authorize(scope, null, null, expenseEvidenceRetention);
        _guard(token);
        final saved = await drafts.recoveryIds(
          scope,
          null,
          null,
          expenseEvidenceRetention,
        );
        _guard(token);
        if (saved.isNotEmpty) {
          policyRecoveries = saved;
          notice = 'Resolve the original entity retention request before creating another.';
          return;
        }
        final id = const Uuid().v4(),
            payload = <String, Object?>{
              'action': 'policy_create',
              'id': id,
              'retention_days': days,
              'purpose': purpose.trim(),
            };
        await _send(payload, 0, token);
        await _refresh(token);
        available = await repository.authorize(
          scope,
          projectId,
          expenseId,
          expenseEvidenceView,
        );
        _guard(token);
        if (!available) notice = 'Retention choice is saved. The separate private worker still needs verified activation.';
      });
  Future<void> retryPolicy(String id) => _operation((token) async {
    const cap = expenseEvidenceRetention;
    final receipt = await drafts.receipt(scope, null, null, id, cap);
    _guard(token);
    if (receipt != null) {
      final result = await repository.receipt(
        scope,
        receipt['command_id'] as String,
      );
      _guard(token);
      if (result != null) {
        await _confirm(result, id, cap, token, policy: true);
        await _refresh(token);
        return;
      }
    }
    final draft = await drafts.read(scope, null, null, id, cap);
    _guard(token);
    if (draft == null) {
      notice = 'Private policy metadata expired. Resolve its minimal receipt before making another entity retention choice.';
      return;
    }
    final pending = await drafts.seal(scope, null, null, id, cap);
    _guard(token);
    try {
      final result = await repository.command(pending.envelope);
      await _confirm(result, id, cap, token, policy: true);
      await _refresh(token);
    } on DomainError catch (e) {
      await drafts.releaseRejected(scope, null, null, id, cap, e);
      _guard(token);
      rethrow;
    }
  });
  Future<void> discardPolicy(String id) => _operation((token) async {
    await drafts.discard(scope, null, null, id, expenseEvidenceRetention);
    _guard(token);
    await _refresh(token);
  });
  Future<void> view(ExpenseEvidenceDocument doc) => _operation((token) async {
    final bytes = await repository.document(scope, projectId, expenseId, doc);
    _guard(token);
    preview = bytes;
    previewDocument = doc;
  });
  void closePreview() {
    preview = null;
    previewDocument = null;
    if (_alive) notifyListeners();
  }

  Future<void> export(ExpenseEvidenceDocument doc) => _operation((token) async {
    final extension = switch (doc.mime) {
      'text/plain' => 'txt',
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      _ => 'pdf',
    };
    final path = await files.chooseExport('expense-evidence.$extension');
    _guard(token);
    if (path == null) return;
    await repository.authorize(
      scope,
      projectId,
      expenseId,
      expenseEvidenceExport,
    );
    _guard(token);
    final bytes = await repository.document(
      scope,
      projectId,
      expenseId,
      doc,
      export: true,
    );
    _guard(token);
    await repository.authorize(
      scope,
      projectId,
      expenseId,
      expenseEvidenceExport,
    );
    _guard(token);
    await files.write(path, bytes, doc.mime);
    _guard(token);
    notice = 'The verified evidence was exported to the selected file.';
  });
  String get comparisonText {
    final saved = comparison?.payload;
    if (saved == null) return '';
    final action = switch (saved['action']) {
      'reserve' => 'Reserve a new private document',
      'complete' => 'Verify the selected document bytes',
      'hold' => 'Place an explicit retention hold',
      'release_hold' => 'Release the retention hold',
      'retire' => 'Retire this document under its retention policy',
      _ => 'Review the saved evidence request',
    };
    return [
      action,
      if (saved['purpose'] is String) 'Purpose: ${saved['purpose']}',
      if (saved['mime'] is String) 'Type: ${saved['mime']}',
      if (saved['byte_size'] is int) 'Size: ${saved['byte_size']} bytes',
      if (saved['reason'] is String) 'Reason: ${saved['reason']}',
      if (saved['review_date'] is String)
        'Hold review date: ${saved['review_date']}',
    ].join('\n');
  }

  @override
  void dispose() {
    _alive = false;
    ++_epoch;
    preview = null;
    previewDocument = null;
    documents = [];
    recoveries = [];
    policyRecoveries = [];
    selected.clear();
    super.dispose();
  }
}
