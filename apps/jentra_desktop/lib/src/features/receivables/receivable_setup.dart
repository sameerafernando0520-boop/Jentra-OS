import 'package:flutter/material.dart';
import 'receivables_controller.dart';
import 'receivable_picker.dart';

Future<void> showReceivableSetup(
  BuildContext context,
  ReceivablesController controller,
) => showScopedReceivableDialog<void>(
  context: context,
  controller: controller,
  builder: (_) => _Setup(controller: controller),
);

class _Setup extends StatefulWidget {
  const _Setup({required this.controller});
  final ReceivablesController controller;
  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  String resource = 'cash_bank_account',
      purpose = 'receivable_control',
      name = '',
      code = '',
      currency = 'LKR',
      kind = 'bank',
      status = 'active';
  String? id, error;
  int? version;
  Map<String, Object?>? account;
  bool busy = false;
  final nameField = TextEditingController(),
      codeField = TextEditingController(),
      currencyField = TextEditingController(text: 'LKR');
  ReceivablesController get c => widget.controller;
  @override
  void dispose() {
    nameField.dispose();
    codeField.dispose();
    currencyField.dispose();
    super.dispose();
  }

  Future<void> existing() async {
    final row = await pickReceivableReference(
      context,
      c,
      resource == 'posting_mapping' ? 'posting_mappings' : 'cash_bank_accounts',
      'Choose existing setup',
    );
    if (row == null || !mounted) return;
    setState(() {
      id = row['id'] as String;
      version = row['version'] as int;
      purpose = row['purpose'] as String? ?? purpose;
      nameField.text = row['name'] as String? ?? '';
      codeField.text = row['code'] as String? ?? '';
      currencyField.text = row['currency_code'] as String? ?? 'LKR';
      kind = row['account_kind'] as String? ?? kind;
      status = row['status']! as String;
      account = {'id': row['account_id'], 'name': 'Current linked account'};
    });
  }

  Future<void> save() async {
    if (account == null) {
      setState(() => error = 'Choose a posting account.');
      return;
    }
    setState(() => busy = true);
    await c.setup({
      'resource': resource,
      if (id != null) 'id': id,
      'purpose': purpose,
      'account_id': account!['id'],
      'status': status,
      'name': nameField.text.trim(),
      'code': codeField.text.trim(),
      'currency_code': currencyField.text.trim(),
      'account_kind': kind,
    }, version);
    if (mounted) {
      if (c.error == null || c.pending) {
        Navigator.pop(context);
      } else {
        setState(() {
          error = c.error;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receivables posting setup'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure workflows, number sequences, tax, products, and fiscal periods in Business setup. These settings link receivables to the ledger. Used control mappings cannot be changed silently.',
            ),
            DropdownButtonFormField<String>(
              initialValue: resource,
              items: const [
                DropdownMenuItem(
                  value: 'cash_bank_account',
                  child: Text('Cash / bank account'),
                ),
                DropdownMenuItem(
                  value: 'posting_mapping',
                  child: Text('Posting account mapping'),
                ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      resource = v!;
                      id = null;
                      version = null;
                      account = null;
                    }),
            ),
            TextButton(
              onPressed: busy ? null : existing,
              child: const Text('Edit existing setup'),
            ),
            if (resource == 'posting_mapping')
              DropdownButtonFormField<String>(
                key: ValueKey(purpose),
                initialValue: purpose,
                decoration: const InputDecoration(labelText: 'Purpose'),
                items: [
                  for (final p in [
                    'receivable_control',
                    'output_tax',
                    'rounding',
                    'exchange_gain',
                    'exchange_loss',
                    'write_off',
                    'settlement_discount',
                  ])
                    DropdownMenuItem(
                      value: p,
                      child: Text(p.replaceAll('_', ' ')),
                    ),
                ],
                onChanged: busy || id != null
                    ? null
                    : (v) => setState(() => purpose = v!),
              )
            else ...[
              TextField(
                controller: codeField,
                decoration: const InputDecoration(
                  labelText: 'Code · uppercase letters, digits, hyphen',
                ),
              ),
              TextField(
                controller: nameField,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: currencyField,
                decoration: const InputDecoration(labelText: 'Currency code'),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(kind),
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Account kind'),
                items: const [
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                ],
                onChanged: busy ? null : (v) => setState(() => kind = v!),
              ),
            ],
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final row = await pickReceivableReference(
                        context,
                        c,
                        'accounts',
                        'Choose a posting ledger account',
                      );
                      if (row != null && mounted) setState(() => account = row);
                    },
              child: Text(
                account == null
                    ? 'Choose ledger account'
                    : referenceLabel(account!),
              ),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(status),
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: busy ? null : (v) => setState(() => status = v!),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: const Text('Save setup'),
      ),
    ],
  );
}
