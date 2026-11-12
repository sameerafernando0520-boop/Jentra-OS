import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_people.dart' show CivilDate;
import 'package:jentra_platform/finance_opening.dart';
import 'package:jentra_platform/finance_opening_files.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'finance_opening_controller.dart';

class FinanceOpeningScreen extends ConsumerWidget {
  const FinanceOpeningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(businessCapabilitiesProvider);
    final controller = ref.watch(financeOpeningControllerProvider);
    if (capabilities.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (capabilities.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Recheck access'),
        ),
      );
    }
    if (controller == null) {
      return const Center(
        child: Text('Choose a company and branch with opening-balance access.'),
      );
    }
    return FinanceOpeningWorkspace(
      key: ValueKey(controller),
      controller: controller,
      files: ref.watch(setupFileServiceProvider),
    );
  }
}

class FinanceOpeningWorkspace extends StatefulWidget {
  const FinanceOpeningWorkspace({
    required this.controller,
    this.files = const SetupFileService(),
    super.key,
  });

  final FinanceOpeningController controller;
  final SetupFileService files;

  static Future<bool> confirmLeave(
    BuildContext context,
    FinanceOpeningController? controller,
  ) async {
    if (controller == null || !controller.hasUnsavedPreview) return true;
    if (controller.busy) return false;
    final discard = await showOperationalReadDialog<bool>(
      context,
      controller,
      (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Discard unsaved preview?'),
        content: const Text(
          'Save a draft to keep this import. Leaving discards the current preview and its unsaved selections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Discard preview'),
          ),
        ],
      ),
    );
    return discard == true || !controller.hasUnsavedPreview;
  }

  @override
  State<FinanceOpeningWorkspace> createState() =>
      _FinanceOpeningWorkspaceState();
}

class _FinanceOpeningWorkspaceState extends State<FinanceOpeningWorkspace> {
  FinanceOpeningController get controller => widget.controller;
  String? fileError;
  bool _selectingFile = false;

  Future<void> _selectFile() async {
    if (_selectingFile) return;
    final epoch = controller.readAccessEpoch;
    final editorId = controller.editorValue('id');
    bool isCurrentEditor() =>
        mounted &&
        controller.currentRead(epoch) &&
        controller.editorValue('id') == editorId;
    try {
      setState(() {
        _selectingFile = true;
        fileError = null;
      });
      final selected = await widget.files.openImportFile();
      if (selected != null && isCurrentEditor()) {
        await controller.previewFile(selected);
      }
    } on FormatException catch (failure) {
      if (isCurrentEditor()) {
        controller.invalidateFilePreview();
        setState(() => fileError = failure.message);
      }
    } catch (_) {
      if (isCurrentEditor()) {
        controller.invalidateFilePreview();
        setState(() => fileError = 'Could not open the selected file.');
      }
    } finally {
      if (mounted) setState(() => _selectingFile = false);
    }
  }

  Future<void> _saveTemplate(String extension) async {
    final epoch = controller.readAccessEpoch;
    try {
      setState(() => fileError = null);
      await widget.files.saveExport(
        suggestedName: 'opening-documents.$extension',
        bytes: FinanceOpeningFileCodec.encodeTemplate(extension),
        mimeType: extension == 'csv' ? 'text/csv' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (_) {
      if (mounted && controller.currentRead(epoch)) {
        setState(() => fileError = 'Could not save the import template.');
      }
    }
  }

  Future<void> _pick(String resource, String title) async {
    final epoch = controller.readAccessEpoch;
    final selection = await showOperationalReadDialog<_OpeningOption>(
      context,
      controller,
      (_) => _OpeningOptionPicker(
        controller: controller,
        resource: resource,
        title: title,
      ),
    );
    if (mounted && selection != null && controller.currentRead(epoch)) {
      controller.selectOption(
        resource,
        selection.row,
        baseCurrencyCode: selection.baseCurrencyCode,
      );
    }
  }

  Future<void> _act(String action, String title) async {
    if (action == 'save') {
      await controller.act(action);
      return;
    }
    final epoch = controller.readAccessEpoch;
    var reason = '';
    final requiresReason = const {
      'reject',
      'recall',
      'cancel',
    }.contains(action);
    final confirmed = await showOperationalReadDialog<bool>(
      context,
      controller,
      (_) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          scrollable: true,
          title: Text('$title?'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (action) {
                'post' => 'Post the approved opening balances to the ledger and open-item registers. Posted batches are kept as part of the accounting record.',
                'approve' => 'Confirm the documents, amounts and accounts against the signed opening records.',
                'submit' => 'Send this batch to an independent approver.',
                'reject' => 'Return the batch to the preparer with a reason.',
                'recall' =>
                  'Return this batch to draft and clear any approval.',
                _ => 'Cancel this batch and retain its history.',
              }),
              if (requiresReason) ...[
                const SizedBox(height: 12),
                TextField(
                  maxLength: 500,
                  onChanged: (value) => update(() => reason = value),
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: requiresReason && reason.trim().length < 3
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: Text(title),
            ),
          ],
        ),
      ),
    );
    if (mounted && confirmed == true && controller.currentRead(epoch)) {
      await controller.act(action, reason: reason);
    }
  }

  Future<void> _requestReversal() async {
    if (!controller.canRequestReversal) return;
    final epoch = controller.readAccessEpoch;
    final batchId = controller.document!['id'];
    var date = '';
    var reason = '';
    bool validDate() {
      try {
        CivilDate.parse(date.trim());
        return true;
      } on FormatException {
        return false;
      }
    }

    final confirmed = await showOperationalReadDialog<bool>(
      context,
      controller,
      (_) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          scrollable: true,
          title: const Text('Request opening reversal'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send this posted batch for independent reversal review. The reversal uses its original accounts and exact amounts.',
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => update(() => date = value),
                decoration: const InputDecoration(
                  labelText: 'Reversal posting date',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
              TextField(
                maxLength: 500,
                maxLines: 3,
                onChanged: (value) => update(() => reason = value),
                decoration: const InputDecoration(
                  labelText: 'Reason for reversal',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: validDate() && reason.trim().length >= 3
                  ? () => Navigator.pop(dialog, true)
                  : null,
              child: const Text('Request reversal'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        confirmed == true &&
        controller.currentRead(epoch) &&
        controller.document?['id'] == batchId) {
      await controller.requestReversal(postingDate: date, reason: reason);
    }
  }

  Future<void> _actReversal(String action, String title) async {
    if (!controller.canActReversal(action)) return;
    final epoch = controller.readAccessEpoch;
    final requestId = controller.reversal!['id'];
    var reason = '';
    final requiresReason = const {'reject', 'cancel'}.contains(action);
    final confirmed = await showOperationalReadDialog<bool>(
      context,
      controller,
      (_) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          scrollable: true,
          title: Text('$title?'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (action) {
                'approve' => 'Confirm the reversal date, reason and original opening records for independent approval.',
                'post' => 'Post the approved opposite balances on the requested date and close each original opening item against its linked reversal.',
                'reject' =>
                  'Reject this reversal request and retain its review history.',
                _ => 'Cancel this reversal request and retain its history.',
              }),
              if (requiresReason) ...[
                const SizedBox(height: 12),
                TextField(
                  maxLength: 500,
                  onChanged: (value) => update(() => reason = value),
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: requiresReason && reason.trim().length < 3
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: Text(title),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        confirmed == true &&
        controller.currentRead(epoch) &&
        controller.reversal?['id'] == requestId) {
      await controller.actReversal(action, reason: reason);
    }
  }

  Future<void> _reversalHistory() => showOperationalReadDialog<void>(
    context,
    controller,
    (_) => _OpeningReversalHistory(
      controller: controller,
      batchId: controller.document!['id']! as String,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final document = c.document;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Opening balances',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Import unpaid customer or supplier documents as at a company cutoff date.',
            ),
            if (!c.online)
              const Text('Reconnect to review or post opening balances.'),
            if (c.accessDenied)
              const Text(
                'Access changed. Any saved request is retained securely.',
              ),
            if (c.error != null) _Notice(c.error!, error: true),
            if (c.currentRead(c.readAccessEpoch) &&
                c.editing &&
                fileError != null)
              _Notice(fileError!, error: true),
            if (c.message != null) _Notice(c.message!),
            if (c.busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Opening balances loading',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.canPrepare && !c.editing)
                  FilledButton.icon(
                    onPressed: c.canStart
                        ? () {
                            fileError = null;
                            c.startNew();
                          }
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('New opening batch'),
                  ),
                OutlinedButton(
                  onPressed: c.online && !c.busy ? c.refresh : null,
                  child: Text(
                    c.accessDenied ? 'Recheck access' : 'Refresh register',
                  ),
                ),
              ],
            ),
            if (c.hasPending) ...[
              const SizedBox(height: 12),
              const _Notice(
                'The last action is unconfirmed. Retry the saved request to check its outcome.',
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  onPressed: !c.busy && c.currentRead(c.readAccessEpoch)
                      ? c.retry
                      : null,
                  child: const Text('Retry saved request'),
                ),
              ),
            ],
            if (c.editing) _editor(context),
            if (!c.editing && document != null) _document(context, document),
            if (c.currentRead(c.readAccessEpoch) && !c.editing)
              _register(context),
          ],
        ),
      );
    },
  );

  Widget _editor(BuildContext context) {
    final c = controller;
    final preview = c.localPreview;
    final server = c.serverPreview;
    final editorId = c.editorValue('id');
    Widget field(String key, String label, {int? maxLength}) => TextFormField(
      key: ValueKey('$editorId-$key'),
      enabled: c.canStart && !_selectingFile,
      initialValue: c.editorValue(key),
      maxLength: maxLength,
      onChanged: (value) => c.updateField(key, value),
      decoration: InputDecoration(labelText: label),
    );
    Widget option(
      String resource,
      String key,
      String label, {
      bool enabled = true,
    }) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton(
        onPressed: c.canStart && enabled && !_selectingFile
            ? () => _pick(resource, label)
            : null,
        child: Text(
          c.optionLabel(key).isEmpty
              ? 'Choose $label'
              : '$label · ${c.optionLabel(key)}',
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text('Prepare import', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'The preview is kept in this session until you save a draft.',
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'AR', label: Text('Customers')),
            ButtonSegment(value: 'AP', label: Text('Suppliers')),
          ],
          selected: {c.kind},
          onSelectionChanged: c.canStart && !_selectingFile
              ? (value) => c.updateField('kind', value.single)
              : null,
        ),
        const SizedBox(height: 12),
        field('source_system', 'Source system', maxLength: 100),
        field('cutoff_date', 'Cutoff date (YYYY-MM-DD)', maxLength: 10),
        const SizedBox(height: 8),
        option('currencies', 'currency_code', 'currency'),
        option(
          'control_accounts',
          'control_account_id',
          'control account',
          enabled: c.currencyCode.isNotEmpty,
        ),
        option(
          'clearing_accounts',
          'clearing_account_id',
          'opening clearing account',
          enabled: c.currencyCode.isNotEmpty,
        ),
        const SizedBox(height: 12),
        const Text(
          'Use one currency per file. Enter original document and due dates as YYYY-MM-DD text. In Excel, format dates, references and amounts as text to preserve their exact values.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: c.canStart ? () => _saveTemplate('csv') : null,
              child: const Text('Download CSV template'),
            ),
            TextButton(
              onPressed: c.canStart ? () => _saveTemplate('xlsx') : null,
              child: const Text('Download Excel template'),
            ),
            FilledButton.icon(
              onPressed: c.canChooseFile && !_selectingFile
                  ? _selectFile
                  : null,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose CSV or Excel file'),
            ),
          ],
        ),
        if (preview != null) ...[
          const SizedBox(height: 16),
          Text(
            'File preview · ${c.fileName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (preview.outstandingTotal != null)
            Text('Outstanding · ${preview.outstandingTotal}'),
          if (preview.carryingBaseTotal != null)
            Text('Carrying value · ${preview.carryingBaseTotal}'),
          if (preview.issues.isNotEmpty)
            _PagedDetails(
              key: ObjectKey(preview),
              count: preview.issues.length,
              item: (index) {
                final issue = preview.issues[index];
                return _issue(issue.rowNumber, issue.field, issue.message);
              },
            ),
          if (preview.lines.isNotEmpty)
            _PagedDetails(
              key: ValueKey((preview, 'lines')),
              count: preview.lines.length,
              item: (index) => _OpeningLineTile(
                line: preview.lines[index].toPayload(),
                baseCurrency: c.baseCurrencyCode,
              ),
            ),
        ],
        if (server != null) ...[
          const SizedBox(height: 12),
          _Notice(
            server['valid'] == true ? 'Server checks passed.' : 'Fix the issues reported by the server and choose the corrected file.',
            error: server['valid'] != true,
          ),
          if (server['totals'] case final Map totals)
            _OpeningTotals(
              totals: totals,
              currency: c.currencyCode,
              baseCurrency: c.baseCurrencyCode,
            ),
          if (openingRows(server['issues']) case final issues
              when issues.isNotEmpty)
            _PagedDetails(
              key: ObjectKey(server),
              count: issues.length,
              item: (index) => _issue(
                issues[index]['row'],
                issues[index]['field'],
                issues[index]['message'],
              ),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: c.canAct('save') && !_selectingFile
                  ? () => _act('save', 'Save draft')
                  : null,
              child: const Text('Save draft'),
            ),
            TextButton(
              onPressed: c.canStart && !_selectingFile
                  ? () async {
                      if (await FinanceOpeningWorkspace.confirmLeave(
                        context,
                        c,
                      )) {
                        c.cancelEdit();
                      }
                    }
                  : null,
              child: const Text('Close file preview'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _document(BuildContext context, Map<String, Object?> document) {
    final c = controller;
    final lines = openingRows(document['lines']);
    final status = document['status'];
    const titles = {
      'submit': 'Submit for approval',
      'approve': 'Approve batch',
      'reject': 'Return to preparer',
      'recall': 'Recall batch',
      'cancel': 'Cancel batch',
      'post': 'Post batch',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          _batchLabel(document),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (document['totals'] case final Map totals)
          _OpeningTotals(
            totals: totals,
            currency: document['currency_code'],
            baseCurrency: document['base_currency_code'],
          ),
        if (document['control_account_id'] != null ||
            document['clearing_account_id'] != null)
          Text(
            'Control account · ${document['control_account_code'] ?? document['control_account_id']}\nOpening clearing account · ${document['clearing_account_code'] ?? document['clearing_account_id']}',
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (status == 'draft' && c.canPrepare)
              OutlinedButton(
                onPressed: c.canStart
                    ? () {
                        fileError = null;
                        c.editDraft();
                      }
                    : null,
                child: const Text('Replace draft file'),
              ),
            for (final entry in titles.entries)
              if (c.canAct(entry.key))
                OutlinedButton(
                  onPressed: () => _act(entry.key, entry.value),
                  child: Text(entry.value),
                ),
          ],
        ),
        if (document['reversal_supported'] == true) _reversal(context),
        if (lines.isNotEmpty)
          _PagedDetails(
            key: ObjectKey(document),
            count: lines.length,
            item: (index) {
              final line = lines[index];
              final sourceId = line['id'];
              return _OpeningLineTile(
                line: line,
                baseCurrency: document['base_currency_code'] as String?,
                onOpen: status == 'posted' && sourceId is String
                    ? () => context.push(
                        '/finance/opening-balances/source/${Uri.encodeComponent(sourceId)}',
                      )
                    : null,
              );
            },
          ),
      ],
    );
  }

  Widget _reversal(BuildContext context) {
    final c = controller;
    final request = c.reversal;
    final lines = openingRows(request?['lines']);
    const titles = {
      'approve': 'Approve reversal',
      'reject': 'Reject reversal',
      'cancel': 'Cancel reversal request',
      'post': 'Post reversal',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          'Opening reversal',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (request != null) ...[
          Text(_reversalStateLabel(request['status'])),
          SelectableText('Posting date · ${request['posting_date']}'),
          SelectableText('Reason · ${request['reason']}'),
          SelectableText('Request · ${request['id']}'),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _reversalHistory,
              child: const Text('Reversal history'),
            ),
          ),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (c.canRequestReversal)
              OutlinedButton(
                onPressed: _requestReversal,
                child: const Text('Request reversal'),
              ),
            for (final entry in titles.entries)
              if (c.canActReversal(entry.key))
                OutlinedButton(
                  onPressed: () => _actReversal(entry.key, entry.value),
                  child: Text(entry.value),
                ),
          ],
        ),
        if (request != null && lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Reversal documents',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          _PagedDetails(
            key: ValueKey((request['id'], request['version'])),
            count: lines.length,
            item: (index) {
              final line = lines[index];
              final sourceId = request['status'] == 'posted'
                  ? line['id']
                  : line['source_line_id'];
              return _OpeningLineTile(
                line: line,
                baseCurrency: c.document?['base_currency_code'] as String?,
                onOpen: sourceId is String
                    ? () => context.push(
                        '/finance/opening-balances/source/${Uri.encodeComponent(sourceId)}',
                      )
                    : null,
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _register(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          'Opening batch register',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (c.batches.isEmpty && !c.busy)
          const Text('No opening batches in this branch.'),
        for (final row in c.batches)
          ListTile(
            title: Text(_batchLabel(row)),
            subtitle: Text(
              '${row['row_count'] ?? ''} documents · ${row['currency_code'] ?? ''}',
            ),
            onTap: !c.busy && !c.hasPending && row['id'] is String
                ? () => c.openBatch(row['id'] as String)
                : null,
          ),
        if (c.cursor != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: c.busy ? null : () => c.refresh(more: true),
              child: const Text('Load more batches'),
            ),
          ),
      ],
    );
  }
}

String _batchLabel(Map<String, Object?> row) {
  final side = row['kind'] == 'AR' ? 'Customer openings' : 'Supplier openings';
  final state = switch (row['status']) {
    'pending_approval' => 'Awaiting approval',
    'approved' => 'Approved',
    'posted' => 'Posted',
    'cancelled' => 'Cancelled',
    _ => 'Draft',
  };
  return '$side · ${row['cutoff_date']} · ${row['source_system']} · $state';
}

String _reversalStateLabel(Object? status) => switch (status) {
  'pending_approval' => 'Awaiting independent reversal approval',
  'approved' => 'Approved for reversal',
  'posted' => 'Reversal posted',
  'rejected' => 'Reversal rejected',
  'cancelled' => 'Reversal request cancelled',
  _ => 'Reversal review',
};

Widget _issue(Object? row, Object? field, Object? message) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: _Notice(
    '${row == null ? 'File' : 'Row $row'} · $field · $message',
    error: true,
  ),
);

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: error
          ? TextStyle(color: Theme.of(context).colorScheme.error)
          : null,
    ),
  );
}

class _OpeningTotals extends StatelessWidget {
  const _OpeningTotals({
    required this.totals,
    required this.currency,
    required this.baseCurrency,
  });

  final Map totals;
  final Object? currency;
  final Object? baseCurrency;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 4,
    children: [
      Text('${totals['row_count']} documents'),
      Text('Outstanding · $currency ${totals['outstanding_amount']}'),
      Text('Carrying value · $baseCurrency ${totals['carrying_base_amount']}'),
    ],
  );
}

class _OpeningLineTile extends StatelessWidget {
  const _OpeningLineTile({required this.line, this.baseCurrency, this.onOpen});

  final Map<String, Object?> line;
  final String? baseCurrency;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text('${line['document_number']} · ${line['party_code']}'),
    subtitle: Text(
      [
        if (line['document_date'] != null || line['due_date'] != null)
          'Original date ${line['document_date']} · Due ${line['due_date']}',
        'Outstanding ${line['currency']} ${line['outstanding_amount']} · Carrying value ${baseCurrency ?? ''} ${line['carrying_base_amount']}',
        if (line['external_document_key'] != null)
          'Original reference ${line['external_document_key']}',
        if (line['source_line_id'] != null)
          'Original opening source ${line['source_line_id']}',
      ].join('\n'),
    ),
    isThreeLine: true,
    trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
    onTap: onOpen,
  );
}

class _OpeningReversalHistory extends StatefulWidget {
  const _OpeningReversalHistory({
    required this.controller,
    required this.batchId,
  });
  final FinanceOpeningController controller;
  final String batchId;

  @override
  State<_OpeningReversalHistory> createState() =>
      _OpeningReversalHistoryState();
}

class _OpeningReversalHistoryState extends State<_OpeningReversalHistory> {
  final rows = <Map<String, Object?>>[];
  String? cursor;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    if (loading || (more && cursor == null)) return;
    final epoch = widget.controller.readAccessEpoch;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.controller.reversalHistory(
        widget.batchId,
        after: more ? cursor : null,
      );
      if (!mounted || !widget.controller.currentRead(epoch)) return;
      setState(() {
        if (!more) rows.clear();
        rows.addAll(openingRows(page['items']));
        cursor = page['next_cursor'] as String?;
      });
    } catch (failure) {
      if (!mounted || !widget.controller.currentRead(epoch)) return;
      setState(
        () => error = failure is FinanceOpeningFailure
            ? failure.message
            : 'Could not read reversal history.',
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Opening reversal history'),
    content: SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) _Notice(error!, error: true),
          for (final row in rows) ...[
            SelectableText(
              '${row['posting_date']} · ${_reversalStateLabel(row['status'])}',
            ),
            SelectableText('${row['reason']}'),
            SelectableText('Request · ${row['id']}'),
            const Divider(),
          ],
          if (!loading && error == null && rows.isEmpty)
            const Text('No reversal requests.'),
          if (error != null && !loading)
            TextButton(
              onPressed: () => _load(more: cursor != null),
              child: const Text('Retry history'),
            ),
          if (cursor != null && !loading && error == null)
            TextButton(
              onPressed: () => _load(more: true),
              child: const Text('More requests'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _PagedDetails extends StatefulWidget {
  const _PagedDetails({required this.count, required this.item, super.key});

  final int count;
  final Widget Function(int index) item;

  @override
  State<_PagedDetails> createState() => _PagedDetailsState();
}

class _PagedDetailsState extends State<_PagedDetails> {
  static const pageSize = 20;
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, widget.count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = start; i < end; i++) widget.item(i),
        if (widget.count > pageSize)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${start + 1}–$end of ${widget.count}'),
              TextButton(
                onPressed: page > 0 ? () => setState(() => page--) : null,
                child: const Text('Previous page'),
              ),
              TextButton(
                onPressed: end < widget.count
                    ? () => setState(() => page++)
                    : null,
                child: const Text('Next page'),
              ),
            ],
          ),
      ],
    );
  }
}

typedef _OpeningOption = ({Map<String, Object?> row, String? baseCurrencyCode});

class _OpeningOptionPicker extends StatefulWidget {
  const _OpeningOptionPicker({
    required this.controller,
    required this.resource,
    required this.title,
  });

  final FinanceOpeningController controller;
  final String resource;
  final String title;

  @override
  State<_OpeningOptionPicker> createState() => _OpeningOptionPickerState();
}

class _OpeningOptionPickerState extends State<_OpeningOptionPicker> {
  List<Map<String, Object?>> rows = const [];
  String? cursor;
  String? baseCurrencyCode;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final access = widget.controller;
    final epoch = access.readAccessEpoch;
    if (!loading) setState(() => loading = true);
    try {
      final page = await access.options(
        widget.resource,
        after: more ? cursor : null,
      );
      if (!mounted || !access.currentRead(epoch)) return;
      setState(() {
        final nextRows = openingRows(page['items']);
        rows = more ? [...rows, ...nextRows] : nextRows;
        cursor = page['next_cursor'] as String?;
        baseCurrencyCode = page['base_currency_code'] as String?;
        error = null;
        loading = false;
      });
    } catch (failure) {
      if (!mounted || !access.currentRead(epoch)) return;
      setState(() {
        error = failure is FinanceOpeningFailure
            ? failure.message
            : 'Could not load available choices.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Choose ${widget.title}'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const LinearProgressIndicator(semanticsLabel: 'Loading choices'),
        if (error != null) _Notice(error!, error: true),
        if (error != null && !loading && cursor == null)
          TextButton(
            onPressed: () => _load(),
            child: const Text('Retry choices'),
          ),
        if (!loading && error == null && rows.isEmpty)
          const Text('No matching choices are available.'),
        for (final row in rows)
          ListTile(
            title: Text('${row['code'] ?? row['id']}'),
            subtitle: row['name'] == null ? null : Text('${row['name']}'),
            onTap: loading
                ? null
                : () => Navigator.pop<_OpeningOption>(context, (
                    row: row,
                    baseCurrencyCode: baseCurrencyCode,
                  )),
          ),
        if (cursor != null && !loading)
          TextButton(
            onPressed: () => _load(more: true),
            child: const Text('More choices'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class OpeningSourceScreen extends ConsumerWidget {
  const OpeningSourceScreen({required this.sourceId, super.key});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = financeOpeningSourceProvider(sourceId);
    final source = ref.watch(provider);
    if (source.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final record = source.hasError ? null : source.value;
    final failure = source.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (context.canPop())
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
          Text(
            record?['reversal_id'] == null
                ? 'Imported opening document'
                : 'Opening reversal document',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          if (source.hasError) ...[
            _Notice(
              failure is FinanceOpeningFailure
                  ? failure.message
                  : 'Could not load this opening document.',
              error: true,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Retry source read'),
              ),
            ),
          ] else if (record == null)
            const Text(
              'Choose the document’s company and branch and check your opening-balance access.',
            )
          else ...[
            Text(
              '${record['document_number']} · ${record['party_code']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final (key, label) in [
              ('source_system', 'Source system'),
              ('external_document_key', 'Original reference'),
              ('kind', 'Opening type'),
              if (record['reversal_of_source_id'] != null) ...[
                ('original_document_date', 'Original document date'),
                ('original_due_date', 'Original due date'),
                ('due_date', 'Counter-item due date'),
              ] else ...[
                ('document_date', 'Original document date'),
                ('due_date', 'Original due date'),
                ('cutoff_date', 'Cutoff date'),
              ],
              ('currency', 'Currency'),
              ('outstanding_amount', 'Outstanding amount'),
              ('base_currency_code', 'Base currency'),
              ('carrying_base_amount', 'Carrying value'),
              ('legacy_original_amount', 'Legacy original amount'),
              ('legacy_settled_amount', 'Legacy settled amount'),
              ('batch_id', 'Opening batch'),
              ('open_item_id', 'Open item'),
              ('journal_entry_id', 'Posted journal'),
              ('posted_at', 'Posted at'),
              ('file_sha256', 'Original file SHA-256'),
              ('reversal_id', 'Reversal request'),
              ('reversal_of_source_id', 'Original opening source'),
              ('original_open_item_id', 'Original open item'),
              ('reversal_posting_date', 'Reversal posting date'),
              ('reversal_reason', 'Reason for reversal'),
            ])
              if (record[key] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SelectableText('$label · ${record[key]}'),
                ),
            if (record['reversal_source_id'] case final String reversalSource)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => context.push(
                    '/finance/opening-balances/source/${Uri.encodeComponent(reversalSource)}',
                  ),
                  child: const Text('Open reversal document'),
                ),
              ),
            if (record['reversal_of_source_id']
                case final String originalSource)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => context.push(
                    '/finance/opening-balances/source/${Uri.encodeComponent(originalSource)}',
                  ),
                  child: const Text('Open original opening document'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
