import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

class QuotationRecoveryDialog extends ConsumerStatefulWidget {
  const QuotationRecoveryDialog({
    required this.scope,
    this.orders = false,
    super.key,
  });
  final TenantContext scope;
  final bool orders;
  @override
  ConsumerState<QuotationRecoveryDialog> createState() =>
      _QuotationRecoveryDialogState();
}

class _QuotationRecoveryDialogState
    extends ConsumerState<QuotationRecoveryDialog> {
  final _items = <QuotationRecoveryEntry>[];
  String? _cursor;
  bool _loading = true;
  Object? _error;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  bool get _active =>
      mounted &&
      ref.read(activeTenantContextProvider) == widget.scope &&
      ref
              .read(businessCapabilitiesProvider)
              .value
              ?.any(
                (cap) => widget.orders
                    ? {
                        'sales.orders.manage',
                        'inventory.reservations.manage',
                      }.contains(cap)
                    : cap == 'sales.quotations.manage',
              ) ==
          true &&
      !ref.read(businessCapabilitiesProvider).isLoading &&
      !ref.read(businessCapabilitiesProvider).hasError;
  Future<void> _load() async {
    if (!_active) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(
            widget.orders
                ? salesOrderDraftStoreProvider
                : quotationDraftStoreProvider,
          )
          .pageDrafts(widget.scope, afterId: _cursor);
      if (!_active) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loading = false;
      });
    } on Object catch (error) {
      if (_active) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeTenantContextProvider);
    ref.watch(businessCapabilitiesProvider);
    return AlertDialog(
      title: const Text('Recover encrypted draft'),
      content: SizedBox(
        width: 550,
        height: 340,
        child: !_active
            ? const Text(
                'Business scope or access changed. Close and reopen recovery.',
              )
            : ListView(
                children: [
                  const Text(
                    'Only drafts saved by you in this tenant, entity and branch are shown.',
                  ),
                  const SizedBox(height: 16),
                  for (final entry in _items)
                    ListTile(
                      title: Text(
                        entry.slot == 'new'
                            ? (widget.orders
                                  ? 'New sales order'
                                  : 'New quotation')
                            : entry.draft.form['_document_number']
                                      ?.toString() ??
                                  '${widget.orders ? 'Order' : 'Quotation'} ${entry.draft.form['id'] ?? entry.draft.form['quotation_id']}',
                      ),
                      subtitle: Text(
                        '${entry.draft.form['currency_code'] ?? ''} · ${entry.draft.form[widget.orders ? 'promised_date' : 'valid_until'] ?? 'Incomplete validity'}${entry.draft.pending != null ? ' · Confirmation pending' : ''}${entry.draft.errorCode == 'VERSION_CONFLICT' ? ' · Conflict' : ''}',
                      ),
                      onTap: () {
                        if (_active) Navigator.of(context).pop(entry);
                      },
                    ),
                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading local drafts',
                      ),
                    ),
                  if (!_loading && _items.isEmpty && _error == null)
                    const Text('No drafts found in this scope.'),
                  if (_error != null)
                    const Text(
                      'Could not read encrypted drafts. Your saved data has been retained.',
                    ),
                  if (!_loading && (_cursor != null || _error != null))
                    TextButton(
                      onPressed: _load,
                      child: Text(
                        _error != null
                            ? 'Try again'
                            : 'Check more saved drafts',
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
}
