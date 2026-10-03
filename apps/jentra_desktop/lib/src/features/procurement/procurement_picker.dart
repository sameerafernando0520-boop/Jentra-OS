import 'package:flutter/material.dart';

import 'procurement_controller.dart';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

import '../operations/operational_read_access.dart';

Future<Map<String, Object?>?> pickProcurementReference(
  BuildContext context,
  ProcurementController controller,
  String resource,
) => pickSourcingReference(
  context,
  controller.gateway,
  controller.scope,
  resource,
  access: controller,
);

Future<Map<String, Object?>?> pickSourcingReference(
  BuildContext context,
  ProcurementGateway gateway,
  TenantContext scope,
  String resource, {
  required OperationalReadAccess access,
}) async {
  final epoch = access.readAccessEpoch;
  if (!access.currentRead(epoch)) return null;
  final result = await showDialog<Map<String, Object?>>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: access,
      builder: (context, _) => access.currentRead(epoch)
          ? _ReferenceDialog(
              gateway: gateway,
              scope: scope,
              resource: resource,
              access: access,
              accessEpoch: epoch,
            )
          : AlertDialog(
              title: const Text('Reference access changed'),
              content: const Text(
                'Close this selector and recheck your business scope and connection.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
    ),
  );
  return context.mounted && access.currentRead(epoch) ? result : null;
}

class _ReferenceDialog extends StatefulWidget {
  const _ReferenceDialog({
    required this.gateway,
    required this.scope,
    required this.resource,
    required this.access,
    required this.accessEpoch,
  });
  final ProcurementGateway gateway;
  final TenantContext scope;
  final String resource;
  final OperationalReadAccess access;
  final int accessEpoch;
  @override
  State<_ReferenceDialog> createState() => _ReferenceDialogState();
}

class _ReferenceDialogState extends State<_ReferenceDialog> {
  final search = TextEditingController();
  List<Map<String, Object?>> rows = [];
  String? cursor, error;
  bool busy = true;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    epoch++;
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final request = ++epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.gateway.references(
        widget.scope,
        widget.resource,
        after: more ? cursor : null,
        search: search.text.trim(),
      );
      if (!mounted ||
          epoch != request ||
          !widget.access.currentRead(widget.accessEpoch)) {
        return;
      }
      final next = (result['items'] as List).map(
        (r) => (r as Map).cast<String, Object?>(),
      );
      setState(() {
        rows = [if (more) ...rows, ...next];
        cursor = result['next_cursor'] as String?;
      });
    } catch (failure) {
      if (mounted &&
          request == epoch &&
          widget.access.currentRead(widget.accessEpoch)) {
        if (failure is DomainError &&
            const {
              'PERMISSION_DENIED',
              'MFA_REQUIRED',
              'AUTHENTICATION_REQUIRED',
              'ACCESS_DENIED',
            }.contains(failure.code)) {
          widget.access.denyReadAccess();
          return;
        }
        setState(() => error = 'References could not be loaded. Try again.');
      }
    } finally {
      if (mounted && request == epoch) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.resource.startsWith('product_units:')
          ? 'Choose product unit'
          : 'Choose ${widget.resource.replaceAll('_', ' ')}',
    ),
    content: SizedBox(
      width: 620,
      height: 480,
      child: Column(
        children: [
          TextField(
            controller: search,
            autofocus: true,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Search code or name',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () => load(),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => load(),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: () => load(), child: Text(error!)),
          Expanded(
            child: ListView(
              children: [
                if (rows.isEmpty && !busy && error == null)
                  const ListTile(title: Text('No matching references.')),
                for (final row in rows)
                  ListTile(
                    title: Text('${row['code']} · ${row['name']}'),
                    onTap: busy
                        ? null
                        : () {
                            if (widget.access.currentRead(widget.accessEpoch)) {
                              Navigator.pop(context, row);
                            }
                          },
                  ),
                if (cursor != null)
                  TextButton(
                    onPressed: busy ? null : () => load(more: true),
                    child: const Text('Load more'),
                  ),
              ],
            ),
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
