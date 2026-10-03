import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_receivables.dart';

import 'receivables_controller.dart';

String receivableReadError(ReceivablesController controller, Object error) {
  if (error is ReceivableFailure) {
    if (const {
      'PERMISSION_DENIED',
      'ACCESS_DENIED',
      'MFA_REQUIRED',
      'AUTHENTICATION_REQUIRED',
    }.contains(error.code)) {
      controller.error = 'Evidence is unavailable with your current access. Recheck your role and scope.';
      controller.invalidateReadEvidence();
      return controller.error!;
    }
    return error.toString();
  }
  if (error is FormatException) return error.message;
  return 'Evidence could not be verified. Retry when connected.';
}

/// Dialogs live on the root navigator, so explicitly hide cached content when
/// their actor/business-scope controller is invalidated.
Future<T?> showScopedReceivableDialog<T>({
  required BuildContext context,
  required ReceivablesController controller,
  required WidgetBuilder builder,
}) async {
  final access = controller.readAccessEpoch;
  if (!controller.currentRead(access)) return null;
  final result = await showDialog<T>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.currentRead(access)
          ? builder(context)
          : AlertDialog(
              title: Text(
                controller.online
                    ? 'Business scope changed'
                    : 'Connect to recheck access',
              ),
              content: const Text(
                'Close this dialog and reopen it after verifying the current scope.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            ),
    ),
  );
  return context.mounted && controller.currentRead(access) ? result : null;
}

String referenceLabel(Map<String, Object?> row) => [
  row['document_number'] ?? row['code'] ?? row['sku'],
  row['display_name'] ?? row['legal_name'] ?? row['name'] ?? row['description'],
  if (row['amount'] != null) '${row['currency_code']} ${row['amount']}',
  if (row['rate'] != null)
    '${row['source_currency_code']} → ${row['target_currency_code']} · ${row['rate']}',
].where((v) => v != null && '$v'.isNotEmpty).join(' · ');

Future<Map<String, Object?>?> pickReceivableReference(
  BuildContext context,
  ReceivablesController controller,
  String resource,
  String title, {
  String? customerId,
  String? sourceId,
}) => showScopedReceivableDialog<Map<String, Object?>>(
  context: context,
  controller: controller,
  builder: (_) => _Picker(
    controller: controller,
    resource: resource,
    title: title,
    customerId: customerId,
    sourceId: sourceId,
  ),
);

class _Picker extends StatefulWidget {
  const _Picker({
    required this.controller,
    required this.resource,
    required this.title,
    this.customerId,
    this.sourceId,
  });
  final ReceivablesController controller;
  final String resource, title;
  final String? customerId, sourceId;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final rows = <Map<String, Object?>>[];
  String? cursor, error;
  String search = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final access = widget.controller.readAccessEpoch;
    if (!widget.controller.currentRead(access)) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.controller.repository.references(
        widget.controller.scope,
        widget.resource,
        cursor: cursor,
        customerId: widget.customerId,
        sourceId: widget.sourceId,
      );
      if (!mounted || !widget.controller.currentRead(access)) return;
      setState(() {
        rows.addAll(page.items);
        cursor = page.nextCursor;
      });
    } catch (e) {
      if (!mounted || !widget.controller.currentRead(access)) return;
      final message = receivableReadError(widget.controller, e);
      if (mounted) {
        setState(() => error = message);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 620,
      height: 460,
      child: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Filter loaded records',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows.where(
                  (r) => referenceLabel(r).toLowerCase().contains(search),
                ))
                  ListTile(
                    title: Text(
                      referenceLabel(row).isEmpty
                          ? 'Record ${row['id']}'
                          : referenceLabel(row),
                    ),
                    subtitle: Text(
                      '${row['status'] ?? row['currency_code'] ?? ''}',
                    ),
                    onTap: () => Navigator.pop(context, row),
                  ),
                if (rows.isEmpty && !loading && error == null)
                  const ListTile(
                    title: Text('No eligible records'),
                    subtitle: Text(
                      'Check the business scope, permissions, and setup.',
                    ),
                  ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (!loading && (cursor != null || error != null))
            TextButton(
              onPressed: load,
              child: Text(error != null ? 'Retry' : 'Load more'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

Future<Map<String, Object?>?> pickReceivableLine(
  BuildContext context,
  Map<String, Object?> document,
  ReceivablesController controller,
) => showScopedReceivableDialog<Map<String, Object?>>(
  context: context,
  controller: controller,
  builder: (context) => AlertDialog(
    title: Text('Lines · ${document['document_number'] ?? 'source'}'),
    content: SizedBox(
      width: 620,
      height: 400,
      child: ListView(
        children: [
          for (final raw in document['lines'] as List? ?? [])
            Builder(
              builder: (context) {
                final line = receivableMap(raw);
                return ListTile(
                  title: Text('${line['description']}'),
                  subtitle: Text(
                    'Base quantity ${line['base_quantity'] ?? line['base_ordered_quantity']} · invoiced ${line['invoiced_quantity'] ?? '—'}',
                  ),
                  onTap: () => Navigator.pop(context, line),
                );
              },
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  ),
);
