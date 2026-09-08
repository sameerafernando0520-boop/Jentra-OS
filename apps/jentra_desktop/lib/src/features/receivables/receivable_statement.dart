import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'receivables_controller.dart';
import 'receivable_picker.dart';

class ReceivableStatement extends StatefulWidget {
  const ReceivableStatement({super.key, required this.controller});
  final ReceivablesController controller;
  @override
  State<ReceivableStatement> createState() => _StatementState();
}

class _StatementState extends State<ReceivableStatement> {
  Map<String, Object?>? customer, report;
  String currency = 'LKR',
      asOf = DateTime.now().toIso8601String().substring(0, 10),
      buckets = '30,60,90';
  String? error;
  bool loading = false;
  ReceivablesController get c => widget.controller;
  Future<void> load() async {
    if (customer == null || !receivableDate(asOf)) {
      setState(() => error = 'Choose a customer and valid as-of date.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      report = null;
    });
    try {
      final days = buckets.split(',').map((v) => int.parse(v.trim())).toList();
      if (days.isEmpty ||
          days.length > 12 ||
          days.any((v) => v <= 0) ||
          days.toSet().length != days.length ||
          ([...days]..sort()).join(',') != days.join(',')) {
        throw const FormatException('Enter increasing positive bucket days.');
      }
      final result = await c.repository.statement(
        c.scope,
        customer!['id']! as String,
        currency,
        asOf,
        days,
      );
      if (mounted) setState(() => report = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> source(Map<String, Object?> row) async {
    try {
      final kind = ReceivableKind.values.firstWhere(
        (k) => k.wire == row['source_type'],
      );
      if (!kind.canRead(c.capabilities)) {
        throw const ReceivableFailure(
          'PERMISSION_DENIED',
          'Your role cannot open this source document.',
        );
      }
      final doc = await c.repository.find(
        c.scope,
        kind,
        row['source_id']! as String,
      );
      if (!mounted) return;
      await showScopedReceivableDialog<void>(
        context: context,
        controller: c,
        builder: (context) => AlertDialog(
          title: Text(doc.number),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${doc.kind.label} · ${doc.status} · ${doc.currency} ${doc.total}',
                  ),
                  Text(
                    'Date ${doc.data['document_date']} · Due ${doc.data['due_date']}',
                  ),
                  for (final line in doc.lines)
                    ListTile(
                      title: Text('${line['description']}'),
                      subtitle: Text(
                        '${line['base_quantity']} base units · ${line['line_total']}',
                      ),
                    ),
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
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> allocations(Map<String, Object?> row) async {
    var cursor = '';
    final rows = <Map<String, Object?>>[];
    try {
      final page = await c.repository.references(
        c.scope,
        'open_item_allocations',
        sourceId: row['id']! as String,
      );
      rows.addAll(page.items);
      cursor = page.nextCursor ?? '';
      if (!mounted) return;
      await showScopedReceivableDialog<void>(
        context: context,
        controller: c,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('Allocation history'),
            content: SizedBox(
              width: 640,
              height: 380,
              child: ListView(
                children: [
                  for (final a in rows)
                    ListTile(
                      title: Text(
                        '${a['posting_date']} · ${a['transaction_amount']}',
                      ),
                      subtitle: SelectableText(
                        'Source ${a['source_open_item_id']}\nTarget ${a['target_open_item_id']}\nFX ${a['exchange_difference']} · discount ${a['discount_amount']} · write-off ${a['write_off']}\n${a['reason'] ?? ''}',
                      ),
                    ),
                  if (rows.isEmpty)
                    const ListTile(title: Text('No allocations yet')),
                  if (cursor.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        try {
                          final page = await c.repository.references(
                            c.scope,
                            'open_item_allocations',
                            sourceId: row['id']! as String,
                            cursor: cursor,
                          );
                          if (context.mounted) {
                            setDialog(() {
                              rows.addAll(page.items);
                              cursor = page.nextCursor ?? '';
                            });
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        }
                      },
                      child: const Text('Load more'),
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
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Customer statements & aging',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'As-of posting-date balances. Unapplied receipts and credits are shown separately; originals remain unchanged.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton(
            onPressed: loading || !c.online
                ? null
                : () async {
                    final row = await pickReceivableReference(
                      context,
                      c,
                      'parties',
                      'Choose customer',
                    );
                    if (row != null && mounted) {
                      setState(() {
                        customer = row;
                        report = null;
                      });
                    }
                  },
            child: Text(
              customer == null ? 'Choose customer' : referenceLabel(customer!),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              onChanged: (v) => setState(() {
                currency = v;
                report = null;
              }),
            ),
          ),
          SizedBox(
            width: 200,
            child: TextFormField(
              initialValue: asOf,
              decoration: const InputDecoration(
                labelText: 'As of · YYYY-MM-DD',
              ),
              onChanged: (v) => setState(() {
                asOf = v;
                report = null;
              }),
            ),
          ),
          SizedBox(
            width: 190,
            child: TextFormField(
              initialValue: buckets,
              decoration: const InputDecoration(
                labelText: 'Overdue bucket days',
              ),
              onChanged: (v) => setState(() {
                buckets = v;
                report = null;
              }),
            ),
          ),
          FilledButton(
            onPressed: loading || !c.online ? null : load,
            child: const Text('Run statement'),
          ),
        ],
      ),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        SelectableText(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (report != null) ...[
        const SizedBox(height: 20),
        Text(
          '$currency ${report!['open_amount']} open · base ${report!['open_base_amount']}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Wrap(
          spacing: 12,
          children: [
            for (final raw in report!['aging'] as List)
              Builder(
                builder: (context) {
                  final a = receivableMap(raw);
                  final b = (a['bucket'] as num).toInt();
                  final days = (report!['bucket_days'] as List).cast<int>();
                  final label = b < 0
                      ? 'Unapplied credits'
                      : b == 0
                      ? 'Current'
                      : b > days.length
                      ? '> ${days.last} days'
                      : '${b == 1 ? 1 : days[b - 2] + 1}–${days[b - 1]} days';
                  return Chip(label: Text('$label · ${a['amount']}'));
                },
              ),
          ],
        ),
        const Divider(),
        for (final raw in report!['rows'] as List)
          Builder(
            builder: (context) {
              final row = receivableMap(raw);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 290,
                        child: Text(
                          '${row['document_number']} · ${row['source_type']}\n${row['posting_date']} · due ${row['due_date']}',
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: Text(
                          'Original ${row['original_amount']}\nOpen ${row['open_amount']} · base ${row['open_base_amount']}',
                        ),
                      ),
                      TextButton(
                        onPressed: () => source(row),
                        child: const Text('Source'),
                      ),
                      TextButton(
                        onPressed: () => allocations(row),
                        child: const Text('Allocations'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    ],
  );
}

Future<void> showReceivableAllocation(
  BuildContext context,
  ReceivablesController c,
) => showScopedReceivableDialog<void>(
  context: context,
  controller: c,
  builder: (_) => _AllocationDialog(controller: c),
);

class _AllocationDialog extends StatefulWidget {
  const _AllocationDialog({required this.controller});
  final ReceivablesController controller;
  @override
  State<_AllocationDialog> createState() => _AllocationState();
}

class _AllocationState extends State<_AllocationDialog> {
  Map<String, Object?>? customer, source;
  final rows = <Map<String, Object?>>[];
  String date = DateTime.now().toIso8601String().substring(0, 10),
      reason = '',
      error = '';
  bool busy = false;
  ReceivablesController get c => widget.controller;
  Future<void> choose(bool isSource) async {
    if (customer == null) {
      final party = await pickReceivableReference(
        context,
        c,
        'parties',
        'Choose customer',
      );
      if (party == null || !mounted) return;
      customer = party;
    }
    final item = await pickReceivableReference(
      context,
      c,
      'receivable_balances',
      isSource
          ? 'Choose an unapplied receipt or credit'
          : 'Choose an open invoice',
      customerId: customer!['id']! as String,
    );
    if (item == null || !mounted) return;
    final amount = receivableDecimal(item['amount']);
    if (isSource ? !amount.isNegative : !amount.isPositive) {
      setState(
        () => error = isSource
            ? 'Choose a negative unapplied item.'
            : 'Choose a positive invoice balance.',
      );
      return;
    }
    setState(() {
      error = '';
      if (isSource) {
        source = item;
        rows.clear();
      } else if (!rows.any((r) => r['target_open_item_id'] == item['id'])) {
        rows.add({
          'target_open_item_id': item['id'],
          '_label': item['document_number'],
          '_currency': item['currency_code'],
          'source_amount': '',
          'transaction_amount': '',
          'write_off': '0',
          'discount_amount': '0',
        });
      }
    });
  }

  Future<void> submit() async {
    try {
      if (source == null || rows.isEmpty || !receivableDate(date)) {
        throw const FormatException(
          'Choose source, invoices and a valid date.',
        );
      }
      for (final row in rows) {
        if (!receivableDecimal(row['source_amount']).isPositive ||
            !receivableDecimal(row['transaction_amount']).isPositive) {
          throw const FormatException(
            'Enter positive exact allocation amounts.',
          );
        }
      }
      setState(() => busy = true);
      await c.allocate({
        'source_open_item_id': source!['id'],
        'posting_date': date,
        'allocations': rows
            .map(
              (r) =>
                  {...r, 'reason': reason}
                    ..removeWhere((k, v) => k.startsWith('_')),
            )
            .toList(),
      });
      if (mounted) {
        if (c.error == null || c.pending) {
          Navigator.pop(context);
        } else {
          setState(() => error = c.error!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Allocate receipt / credit'),
    content: SizedBox(
      width: 800,
      height: 530,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Allocate one source to one or more invoices. A second receipt can be applied to the same invoice later. Server residuals are locked and rechecked.',
            ),
            OutlinedButton(
              onPressed: busy ? null : () => choose(true),
              child: Text(
                source == null
                    ? 'Choose receipt or credit'
                    : referenceLabel(source!),
              ),
            ),
            TextFormField(
              initialValue: date,
              decoration: const InputDecoration(
                labelText: 'Allocation posting date',
              ),
              onChanged: (v) => date = v,
            ),
            for (var i = 0; i < rows.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${rows[i]['_label']} · ${rows[i]['_currency']}'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final entry in {
                            'source_amount':
                                'Source ${source?['currency_code']} amount',
                            'transaction_amount':
                                'Invoice ${rows[i]['_currency']} amount',
                            if (c.capabilities.contains(
                              'finance.receipts.adjust',
                            )) ...{
                              'write_off': 'Write-off',
                              'discount_amount': 'Settlement discount',
                            },
                          }.entries)
                            SizedBox(
                              width: 230,
                              child: TextFormField(
                                key: ValueKey(
                                  '${rows[i]['target_open_item_id']}:${entry.key}',
                                ),
                                initialValue: '${rows[i][entry.key]}',
                                decoration: InputDecoration(
                                  labelText: entry.value,
                                ),
                                onChanged: (v) => rows[i][entry.key] = v,
                              ),
                            ),
                        ],
                      ),
                      if (source?['currency_code'] != rows[i]['_currency'])
                        TextButton(
                          onPressed: () async {
                            final rate = await pickReceivableReference(
                              context,
                              c,
                              'exchange_rates',
                              'Choose allocation conversion rate',
                            );
                            if (rate != null && mounted) {
                              setState(
                                () => rows[i]['exchange_rate_id'] = rate['id'],
                              );
                            }
                          },
                          child: Text(
                            rows[i]['exchange_rate_id'] == null
                                ? 'Choose conversion rate'
                                : 'Conversion rate selected',
                          ),
                        ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => rows.removeAt(i)),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ),
              ),
            if (source != null)
              TextButton.icon(
                onPressed: busy ? null : () => choose(false),
                icon: const Icon(Icons.add),
                label: const Text('Add invoice'),
              ),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Reason · required for adjustments',
              ),
              onChanged: (v) => reason = v,
            ),
            if (error.isNotEmpty)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: const Text('Post allocations'),
      ),
    ],
  );
}
