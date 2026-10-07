import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';

import 'expense_evidence_controller.dart';

final class ExpenseEvidencePanel extends StatefulWidget {
  const ExpenseEvidencePanel({
    super.key,
    required this.scope,
    required this.projectId,
    required this.expenseId,
    required this.repository,
    required this.drafts,
    this.files = const NativeExpenseEvidenceFiles(),
    this.initialProofs = const [],
    this.onChanged,
    this.editable = true,
  });
  final TenantContext scope;
  final String projectId, expenseId;
  final ExpenseEvidenceRepository repository;
  final SensitiveExpenseEvidenceDraftStore drafts;
  final ExpenseEvidenceFiles files;
  final List<ExpenseEvidenceProof> initialProofs;
  final ValueChanged<List<ExpenseEvidenceProof>>? onChanged;
  final bool editable;
  @override
  State<ExpenseEvidencePanel> createState() => _ExpenseEvidencePanelState();
}

final class _ExpenseEvidencePanelState extends State<ExpenseEvidencePanel> {
  late ExpenseEvidenceController c;
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    c = ExpenseEvidenceController(
      scope: widget.scope,
      projectId: widget.projectId,
      expenseId: widget.expenseId,
      repository: widget.repository,
      drafts: widget.drafts,
      files: widget.files,
      initialProofs: widget.initialProofs,
      editable: widget.editable,
    );
    c.load();
  }

  @override
  void didUpdateWidget(covariant ExpenseEvidencePanel old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope ||
        old.projectId != widget.projectId ||
        old.expenseId != widget.expenseId ||
        old.repository != widget.repository) {
      c.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final text = await _text('Evidence purpose', 'Purpose', max: 160);
    if (!mounted || text == null) return;
    await c.uploadNew(text);
    if (mounted && c.confirmed?.entity['status'] == 'active') {
      widget.onChanged?.call(c.proofs);
    }
  }

  Future<String?> _text(String title, String label, {int max = 1000}) async {
    final field = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: field,
            maxLength: max,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      field.dispose();
    }
  }

  Future<void> _hold(ExpenseEvidenceDocument doc) async {
    final reason = await _text('Hold evidence', 'Reason');
    if (!mounted || reason == null) return;
    final date = await _text(
      'Review the hold',
      'Review date (YYYY-MM-DD)',
      max: 10,
    );
    if (!mounted || date == null) return;
    await c.retention(doc, 'hold', reason, reviewDate: date);
  }

  Future<void> _retention(ExpenseEvidenceDocument doc, String action) async {
    final reason = await _text(
      action == 'retire'
          ? 'Begin terminal financial retention'
          : 'Release evidence hold',
      'Reason',
    );
    if (mounted && reason != null) await c.retention(doc, action, reason);
  }

  Future<void> _policy() async {
    final purpose = await _text(
      'Expense evidence retention',
      'Explicit policy purpose',
      max: 160,
    );
    if (!mounted || purpose == null) return;
    final days = await _text(
      'Choose the retention interval',
      'Days after terminal expense retirement (1–3650)',
      max: 4,
    );
    if (!mounted || days == null) return;
    final number = int.tryParse(days);
    if (number != null) await c.createPolicy(number, purpose);
  }

  String _previewText() {
    final text = utf8.decode(c.preview!, allowMalformed: true);
    return text.substring(0, text.length.clamp(0, 4000));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Protected expense evidence',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Each document belongs to this project expense. Verified bytes stay in separate private storage; selected immutable proof accompanies the expense revision.',
        ),
        if (c.busy) const LinearProgressIndicator(),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(c.error!, key: const ValueKey('evidence-error')),
          ),
        if (c.notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(c.notice!, key: const ValueKey('evidence-notice')),
          ),
        if (c.confirmed != null)
          Text(
            'Confirmed ${c.confirmed!.entity['action']} · version ${c.confirmed!.recordVersion}',
            key: const ValueKey('evidence-confirmed'),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: c.busy ? null : () => c.load(),
              child: const Text('Refresh evidence'),
            ),
            if (c.canManage && widget.editable)
              FilledButton(
                onPressed: c.busy || !c.available ? null : _upload,
                child: const Text('Choose and verify evidence'),
              ),
            if (c.canConfigurePolicy && !c.available)
              OutlinedButton(
                onPressed: c.busy ? null : _policy,
                child: const Text('Record explicit retention choice'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final doc in c.documents)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    doc.purpose,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${doc.status} · ${doc.mime} · ${doc.byteSize} bytes · document version ${doc.recordVersion}',
                  ),
                  Text(
                    'Content proof ${doc.proof.version} · ${doc.proof.digest}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (doc.toJson()['hold_review_date'] != null)
                    Text(
                      'Held until explicit review · ${doc.toJson()['hold_review_date']}',
                    ),
                  if (doc.toJson()['purge_after'] != null)
                    Text('Retention ends ${doc.toJson()['purge_after']}'),
                  if (widget.editable &&
                      (doc.isActive || c.selected.containsKey(doc.id)))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Attach this verified proof'),
                      value: c.selected[doc.id]?.digest == doc.proof.digest,
                      onChanged: c.busy || !c.canManage
                          ? null
                          : (value) {
                              c.select(doc, value!);
                              widget.onChanged?.call(c.proofs);
                            },
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (doc.isActive)
                        OutlinedButton(
                          onPressed: c.busy ? null : () => c.view(doc),
                          child: const Text('View verified bytes'),
                        ),
                      if (doc.isActive && c.canExport)
                        OutlinedButton(
                          onPressed: c.busy ? null : () => c.export(doc),
                          child: const Text('Export evidence'),
                        ),
                      if (c.canManage &&
                          c.available &&
                          {'reserved', 'verified'}.contains(doc.status))
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () async {
                                  await c.finishUpload(doc);
                                  if (mounted &&
                                      c.confirmed?.entity['status'] ==
                                          'active') {
                                    widget.onChanged?.call(c.proofs);
                                  }
                                },
                          child: const Text('Finish exact upload'),
                        ),
                      if (c.canRetain &&
                          !{'purging', 'purged'}.contains(doc.status))
                        OutlinedButton(
                          onPressed: c.busy ? null : () => _hold(doc),
                          child: const Text('Hold evidence'),
                        ),
                      if (c.canRetain &&
                          doc.toJson()['hold_review_date'] != null)
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () => _retention(doc, 'release_hold'),
                          child: const Text('Release hold'),
                        ),
                      if (c.canRetain &&
                          {
                            'reserved',
                            'verified',
                            'active',
                          }.contains(doc.status))
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () => _retention(doc, 'retire'),
                          child: const Text('Begin terminal retention'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (c.nextAfter != null)
          OutlinedButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('Load more documents'),
          ),
        if (c.policyRecoveries.isNotEmpty)
          const Text('Saved entity retention choice'),
        for (final id in c.policyRecoveries)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text('Entity policy $id'),
              OutlinedButton(
                onPressed: c.busy ? null : () => c.retryPolicy(id),
                child: const Text('Resolve exact policy request'),
              ),
              TextButton(
                onPressed: c.busy ? null : () => c.discardPolicy(id),
                child: const Text('Discard unsubmitted policy'),
              ),
            ],
          ),
        if (c.recoveries.isNotEmpty)
          const Text(
            'Encrypted recovery · metadata expires after 24 hours; exact uncertain receipts remain.',
          ),
        for (final r in c.recoveries)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text('Saved document ${r.id}'),
              OutlinedButton(
                onPressed: c.busy ? null : () => c.retry(r.id, r.cap),
                child: const Text('Resolve or retry exact request'),
              ),
              TextButton(
                onPressed: c.busy ? null : () => c.discardRecovery(r.id, r.cap),
                child: const Text('Discard unsubmitted metadata'),
              ),
            ],
          ),
        if (c.comparison != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Compare saved evidence with current source'),
                  Text(c.comparisonText),
                  Text(
                    'Saved version ${c.comparison!.version} · current version ${c.comparisonCurrent?.recordVersion ?? 'new document'}',
                  ),
                  if (c.comparisonCurrent != null)
                    Text(
                      'Current ${c.comparisonCurrent!.purpose} · ${c.comparisonCurrent!.status}',
                    ),
                  FilledButton(
                    onPressed: c.busy ? null : () => c.submitComparison(),
                    child: const Text(
                      'Submit compared fields with current version',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (c.preview != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Verified ${c.previewDocument!.mime} · ${c.preview!.length} bytes',
                  ),
                  if (c.previewDocument!.mime.startsWith('image/'))
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: _PrivateExpenseImage(bytes: c.preview!),
                    ),
                  if (c.previewDocument!.mime == 'text/plain')
                    Text(_previewText()),
                  if (c.previewDocument!.mime == 'application/pdf')
                    const Text(
                      'PDF bytes are verified. Use the scoped export action to open the document.',
                    ),
                  TextButton(
                    onPressed: c.closePreview,
                    child: const Text('Close private preview'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// Private decoded images must not outlive their closed or revoked preview.
final class _PrivateExpenseImage extends StatefulWidget {
  const _PrivateExpenseImage({required this.bytes});
  final Uint8List bytes;
  @override
  State<_PrivateExpenseImage> createState() => _PrivateExpenseImageState();
}

final class _PrivateExpenseImageState extends State<_PrivateExpenseImage> {
  late MemoryImage _image;
  @override
  void initState() {
    super.initState();
    _image = MemoryImage(widget.bytes);
  }

  @override
  void didUpdateWidget(_PrivateExpenseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      PaintingBinding.instance.imageCache.evict(_image);
      _image = MemoryImage(widget.bytes);
    }
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.evict(_image);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _image,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stack) => const Text(
      'The verified file cannot be decoded as an image. Use the authorized export action to inspect its original bytes.',
    ),
  );
}
