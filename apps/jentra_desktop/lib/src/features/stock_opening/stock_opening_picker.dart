import 'package:flutter/material.dart';
import 'stock_opening_controller.dart';

/// Dialogs live on the root navigator, so explicitly hide cached content when
/// their actor/business-scope controller is invalidated.
Future<T?> showStockOpeningDialog<T>({
  required BuildContext context,
  required StockOpeningController controller,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  builder: (dialogContext) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => controller.active
        ? builder(context)
        : AlertDialog(
            title: const Text('Business scope changed'),
            content: const Text(
              'Close this dialog and reopen it in the current scope.',
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

String openingReferenceLabel(Map<String, Object?> row) => [
  row['document_number'] ?? row['code'] ?? row['sku'],
  row['display_name'] ?? row['legal_name'] ?? row['name'] ?? row['description'],
  if (row['amount'] != null) '${row['currency_code']} ${row['amount']}',
  if (row['rate'] != null)
    '${row['source_currency_code']} → ${row['target_currency_code']} · ${row['rate']}',
].where((v) => v != null && '$v'.isNotEmpty).join(' · ');

Future<Map<String, Object?>?> pickStockOpeningReference(
  BuildContext context,
  StockOpeningController controller,
  String resource,
  String title,
) => showStockOpeningDialog<Map<String, Object?>>(
  context: context,
  controller: controller,
  builder: (_) =>
      _Picker(controller: controller, resource: resource, title: title),
);

class _Picker extends StatefulWidget {
  const _Picker({
    required this.controller,
    required this.resource,
    required this.title,
  });
  final StockOpeningController controller;
  final String resource, title;
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
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.controller.repository.references(
        widget.controller.scope,
        widget.resource,
        cursor: cursor,
      );
      if (!mounted || !widget.controller.active) return;
      setState(() {
        rows.addAll(page.items);
        cursor = page.nextCursor;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
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
                  (r) =>
                      openingReferenceLabel(r).toLowerCase().contains(search),
                ))
                  ListTile(
                    title: Text(
                      openingReferenceLabel(row).isEmpty
                          ? 'Record ${row['id']}'
                          : openingReferenceLabel(row),
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
