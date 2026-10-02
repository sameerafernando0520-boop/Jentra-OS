import '../shared/report_wait.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart' show SetupFileService;

import '../../app_providers.dart';
import '../journal_evidence/posted_journal_screen.dart';
import '../report_export/report_export_screen.dart';
import 'operational_controller.dart';
import 'operational_link.dart';
import 'operational_read_access.dart';

String operationalLabel(String value) => value
    .split('_')
    .map((v) => v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}')
    .join(' ');

class OperationalScreen extends ConsumerStatefulWidget {
  const OperationalScreen({super.key, required this.target});
  final OperationalTarget target;
  @override
  ConsumerState<OperationalScreen> createState() => _OperationalScreenState();
}

class _OperationalScreenState extends ConsumerState<OperationalScreen> {
  bool restoring = true;
  bool contextAllowed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(restoreContext);
  }

  @override
  void didUpdateWidget(covariant OperationalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      restoring = true;
      contextAllowed = false;
      Future<void>.microtask(restoreContext);
    }
  }

  Future<void> restoreContext() async {
    final target = widget.target;
    var allowed = false;
    try {
      await ref.read(businessScopeProvider.future);
      if (!mounted || widget.target != target) return;
      allowed = await ref
          .read(businessScopeProvider.notifier)
          .selectPermittedContext(
            tenantId: target.tenantId,
            legalEntityId: target.entityId,
            branchId: target.branchId,
            isCurrent: () => mounted && widget.target == target,
          );
    } catch (_) {
      allowed = false;
    }
    if (!mounted || widget.target != target) return;
    setState(() {
      contextAllowed = allowed;
      restoring = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) return const Center(child: CircularProgressIndicator());
    if (!contextAllowed) {
      return const Center(
        child: Text(
          'This document destination is unavailable in the selected business scope.',
        ),
      );
    }
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry document access'),
        ),
      );
    }
    final controller = ref.watch(operationalControllerProvider(widget.target));
    return controller == null
        ? const Center(
            child: Text(
              'This document destination is unavailable in the selected business scope.',
            ),
          )
        : OperationalWorkspace(
            key: ValueKey(controller),
            controller: controller,
            canReadJournal: caps.value?.contains('finance.view') ?? false,
            canExport: caps.value?.contains('finance.reports.export') ?? false,
            canManageFiles: caps.value?.contains('core.files.manage') ?? false,
            fileService: ref.watch(setupFileServiceProvider),
          );
  }
}

class OperationalWorkspace extends StatefulWidget {
  const OperationalWorkspace({
    super.key,
    required this.controller,
    this.canReadJournal = false,
    this.canExport = false,
    this.canManageFiles = false,
    this.fileService,
  });
  final OperationalController controller;
  final bool canReadJournal;
  final bool canExport;
  final bool canManageFiles;
  final SetupFileService? fileService;
  @override
  State<OperationalWorkspace> createState() => _OperationalWorkspaceState();
}

class _OperationalWorkspaceState extends State<OperationalWorkspace> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final header = (c.evidence['header'] as Map?)?.cast<String, Object?>();
      final attachments = (c.evidence['attachments'] as List?) ?? [];
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${operationalLabel(c.target.kind)} ${c.target.id == null ? 'documents' : 'evidence'}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            c.target.id == null
                ? 'Current records in your selected business scope.'
                : 'Source access is checked each time this page is opened.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: c.online && !c.busy ? c.refresh : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Verify and refresh'),
              ),
              if (c.target.id != null)
                OperationalLink(
                  scope: c.scope,
                  kind: c.target.kind,
                  label: 'Open current list',
                ),
              if (c.target.id == null && widget.canExport)
                OutlinedButton.icon(
                  onPressed: c.online && c.verified && !c.busy
                      ? c.freezeCurrentList
                      : null,
                  icon: const Icon(Icons.inventory_outlined),
                  label: Text(
                    c.reportPending
                        ? 'Retry saved report'
                        : 'Freeze current list for export',
                  ),
                ),
            ],
          ),
          if (c.target.id == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final key in const [
                    'search',
                    'status',
                    'from_date',
                    'to_date',
                  ])
                    SizedBox(
                      width: key == 'search' ? 250 : 175,
                      child: TextFormField(
                        key: ValueKey('$key:${c.filters[key]}'),
                        initialValue: c.filters[key] as String?,
                        enabled: !c.busy && !c.reportPending,
                        decoration: InputDecoration(
                          labelText: switch (key) {
                            'search' => 'Find a document',
                            'status' => 'Status',
                            'from_date' => 'From date',
                            _ => 'To date',
                          },
                          hintText: switch (key) {
                            'search' => 'Number, name or reference',
                            'status' => 'e.g. posted',
                            _ => 'YYYY-MM-DD',
                          },
                        ),
                        onFieldSubmitted: (value) =>
                            c.filter({...c.filters, key: value.trim()}),
                      ),
                    ),
                  TextButton(
                    onPressed:
                        !c.busy && !c.reportPending && c.filters.isNotEmpty
                        ? () => c.filter({})
                        : null,
                    child: const Text('Clear saved filters'),
                  ),
                ],
              ),
            ),
          if (c.reportWait.active)
            ReportWaitIndicator(
              state: c.reportWait,
              onCancel: c.cancelReportWait,
            )
          else if (c.busy)
            const LinearProgressIndicator(),
          if (!c.online)
            const Text('Offline. Server evidence has been cleared.'),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.verified) ...[
            if (c.reportPending)
              const Text(
                'An unconfirmed report request is saved. Retry sends that exact request.',
              ),
            if (c.reportSummary.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saved current list · ${c.reportSummary['row_count']} records',
                      ),
                      Text('Generated ${c.reportSummary['generated_at']}'),
                      if (widget.canExport)
                        ReportExportLink(
                          sourceType: 'operational',
                          sourceId: c.reportSummary['id'] as String,
                          section: 'rows',
                          label: 'Export saved current list',
                        ),
                    ],
                  ),
                ),
              ),
            if (header != null) ...[
              const SizedBox(height: 16),
              Text(
                _title(header, c.target.kind),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _DocumentFields(value: header),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.canReadJournal &&
                      header['journal_entry_id'] is String)
                    PostedJournalLink(
                      scope: c.scope,
                      journalId: header['journal_entry_id'] as String,
                    ),
                  for (final link in _related(c.target.kind, header))
                    OperationalLink(
                      scope: c.scope,
                      kind: link.$1,
                      id: link.$2,
                      label: 'Open ${operationalLabel(link.$1).toLowerCase()}',
                    ),
                ],
              ),
              ExpansionTile(
                title: const Text('Document and command identity'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'Document ${header['id']}\nTenant ${c.scope.tenantId}\nEntity ${c.scope.legalEntityId}\nSource branch ${header['branch_id'] ?? 'Entity-wide'}',
                    ),
                  ),
                  for (final item in (c.evidence['commands'] as List?) ?? [])
                    ListTile(
                      title: SelectableText('${item['command_id']}'),
                      subtitle: SelectableText(
                        '${item['completed_at']} · ${item['request_id']}',
                      ),
                    ),
                ],
              ),
            ],
            const Divider(height: 32),
            if (c.rows.isEmpty)
              Text(
                c.target.id == null
                    ? 'No matching documents.'
                    : 'No further document lines.',
              ),
            for (var index = 0; index < c.rows.length; index++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(
                          c.rows[index],
                          c.target.id == null
                              ? c.target.kind
                              : 'Line ${index + 1}',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _DocumentFields(value: c.rows[index]),
                      if (c.target.id == null)
                        OperationalLink(
                          scope: c.scope,
                          kind: c.target.kind,
                          id: c.rows[index]['id'] as String,
                        ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: !c.busy && c.previousPages.isNotEmpty
                      ? c.previous
                      : null,
                  child: const Text('Previous page'),
                ),
                OutlinedButton(
                  onPressed: !c.busy && c.nextCursor != null ? c.next : null,
                  child: const Text('Next page'),
                ),
              ],
            ),
            if (header != null) ...[
              const Divider(height: 32),
              Text(
                'Attachments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.canManageFiles &&
                  c.files != null &&
                  widget.fileService != null)
                OutlinedButton.icon(
                  onPressed: c.online && !c.busy ? _uploadAttachment : null,
                  icon: const Icon(Icons.attach_file),
                  label: Text(switch (c.filePhase) {
                    'complete' => 'Retry saved file confirmation',
                    'register' || 'upload' => 'Reselect original file',
                    _ => 'Attach private file',
                  }),
                ),
              if (c.filePending)
                const Text(
                  'An unfinished file request is saved without file bytes. Reselect the original file to continue.',
                ),
              if (widget.canManageFiles && c.rejectionPending)
                OutlinedButton.icon(
                  onPressed: c.online && !c.busy
                      ? () => c.rejectAttachment(null, null)
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry saved file rejection'),
                ),
              if (attachments.isEmpty)
                const Text(
                  'No attachments are available with your current access.',
                ),
              for (final item in attachments)
                Card(
                  child: ListTile(
                    title: Text('${item['file_name']}'),
                    subtitle: Text(
                      '${item['upload_status']} · ${item['byte_size']} bytes',
                    ),
                    trailing: item['upload_status'] == 'ready'
                        ? PopupMenuButton<String>(
                            tooltip: 'Private file actions',
                            enabled: c.online && !c.busy,
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'open',
                                child: Text('Get private link'),
                              ),
                              if (widget.canManageFiles && !c.rejectionPending)
                                const PopupMenuItem(
                                  value: 'reject',
                                  child: Text('Reject file with reason'),
                                ),
                            ],
                            onSelected: (choice) async {
                              final file = (item as Map)
                                  .cast<String, Object?>();
                              if (choice == 'open') {
                                await _openAttachment(file);
                              } else {
                                await _rejectAttachment(file);
                              }
                            },
                          )
                        : null,
                  ),
                ),
            ],
          ],
        ],
      );
    },
  );

  Future<void> _openAttachment(Map<String, Object?> attachment) async {
    final c = widget.controller;
    final epoch = c.readAccessEpoch;
    if (!c.currentRead(epoch)) return;
    try {
      final url = await c.gateway.signedAttachmentUrl(
        c.scope,
        c.target.kind,
        c.target.id!,
        attachment,
      );
      if (!mounted ||
          !identical(widget.controller, c) ||
          !c.currentRead(epoch)) {
        return;
      }
      await showOperationalReadDialog<void>(
        context,
        c,
        (context) => AlertDialog(
          title: const Text('Private attachment link'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This link expires in 15 minutes. Share it only with an authorized user.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(url),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (failure) {
      if (!mounted ||
          !identical(widget.controller, c) ||
          !c.currentRead(epoch)) {
        return;
      }
      if (failure is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(failure.code)) {
        c.denyReadAccess();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The private file could not be opened. Refresh document access and retry.',
          ),
        ),
      );
    }
  }

  Future<void> _uploadAttachment() async {
    final c = widget.controller;
    final epoch = c.readAccessEpoch;
    if (!c.currentRead(epoch)) return;
    try {
      final file = c.filePhase == 'complete'
          ? null
          : await widget.fileService!.openAttachmentFile();
      if (!mounted ||
          !identical(widget.controller, c) ||
          !c.currentRead(epoch) ||
          (file == null && c.filePhase != 'complete')) {
        return;
      }
      await c.addFile(file);
    } catch (_) {
      if (!mounted ||
          !identical(widget.controller, c) ||
          !c.currentRead(epoch)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The private file could not be selected.'),
        ),
      );
    }
  }

  Future<void> _rejectAttachment(Map<String, Object?> attachment) async {
    final c = widget.controller;
    final epoch = c.readAccessEpoch;
    if (!c.currentRead(epoch)) return;
    final text = TextEditingController();
    try {
      final reason = await showOperationalReadDialog<String>(
        context,
        c,
        (context) => AlertDialog(
          title: const Text('Reject private file'),
          content: TextField(
            controller: text,
            autofocus: true,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Reason',
              helperText: 'The file stays in the audit history but becomes unavailable.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, text.text.trim()),
              child: const Text('Reject file'),
            ),
          ],
        ),
      );
      if (reason == null ||
          !mounted ||
          !identical(widget.controller, c) ||
          !c.currentRead(epoch)) {
        return;
      }
      await c.rejectAttachment(attachment, reason);
    } finally {
      text.dispose();
    }
  }
}

String _title(Map<String, Object?> row, String fallback) =>
    '${row['document_number'] ?? row['code'] ?? row['name'] ?? row['description'] ?? fallback}';

class _DocumentFields extends StatelessWidget {
  const _DocumentFields({required this.value});
  final Map<String, Object?> value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final key in const [
        'status',
        'document_date',
        'posting_date',
        'currency_code',
        'base_currency_code',
        'exchange_rate',
        'reference',
        'supplier_reference',
        'quantity',
        'base_quantity',
        'unit_price',
        'subtotal',
        'discount_total',
        'tax_total',
        'total',
        'grand_total',
        'base_total',
        'amount',
        'base_amount',
        'debit',
        'credit',
      ])
        if (value[key] != null)
          SelectableText('${operationalLabel(key)}: ${value[key]}'),
    ],
  );
}

List<(String, String)> _related(String kind, Map<String, Object?> header) {
  final links = <(String, String)>[];
  void add(String key, String destination) {
    if (header[key] is String) links.add((destination, header[key] as String));
  }

  if (kind == 'goods_receipt') add('order_id', 'purchase_order');
  if (kind == 'quotation') add('opportunity_id', 'opportunity');
  if (kind == 'rfq') add('requisition_id', 'purchase_requisition');
  if (kind == 'purchase_order') {
    add('source_requisition_id', 'purchase_requisition');
    add('source_rfq_id', 'rfq');
  }
  if (kind == 'sales_order') add('source_quotation_id', 'quotation');
  if (kind == 'delivery') add('sales_order_id', 'sales_order');
  if (kind == 'supplier_payment') add('proposal_id', 'payment_proposal');
  if (kind == 'purchase_return') {
    if (header['source_kind'] == 'bill') add('source_id', 'supplier_bill');
    if (header['source_kind'] == 'receipt') add('source_id', 'goods_receipt');
  }
  if (kind == 'inventory_value_adjustment') add('receipt_id', 'goods_receipt');
  return links;
}
