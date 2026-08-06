import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../finance/application/payment_failure.dart';
import '../../../finance/application/payment_models.dart';
import '../../../finance/application/payment_state.dart';
import '../../../finance/application/payment_validators.dart';
import '../../application/invoice_models.dart';

final class RecordPaymentDialog extends ConsumerStatefulWidget {
  const RecordPaymentDialog({
    required this.invoice,
    super.key,
  });

  final Invoice invoice;

  static Future<bool?> show(BuildContext context, Invoice invoice) {
    return showDialog<bool>(
      context: context,
      builder: (context) => RecordPaymentDialog(invoice: invoice),
    );
  }

  @override
  ConsumerState<RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

final class _RecordPaymentDialogState
    extends ConsumerState<RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amountController;
  late final TextEditingController _referenceController;
  late final TextEditingController _notesController;

  String? _selectedMoneyAccountId;
  String _selectedPaymentMethod = 'cash';
  DateTime _paymentDate = DateTime.now();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.invoice.balanceDue.toStringAsFixed(2),
    );
    _referenceController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final input = RecordPaymentInput(
        invoiceId: widget.invoice.id,
        moneyAccountId: _selectedMoneyAccountId,
        paymentMethod: _selectedPaymentMethod,
        amount: double.parse(_amountController.text.trim()),
        paymentDate: _paymentDate,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      final res = await ref
          .read(paymentMutationControllerProvider.notifier)
          .recordPayment(input);

      if (mounted) {
        Navigator.of(context).pop(res.success);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payment ${res.paymentNumber} recorded! Journal entry ${res.journalNumber} posted.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        final message =
            error is PaymentFailure ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final moneyAccountsAsync = ref.watch(moneyAccountListProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.payments_outlined, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Record Payment (${widget.invoice.documentNumber})',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance due notice
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Outstanding Balance:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '\$${widget.invoice.balanceDue.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Money Account Selector
              moneyAccountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => const SizedBox.shrink(),
                data: (accounts) {
                  if (accounts.isEmpty) return const SizedBox.shrink();
                  _selectedMoneyAccountId ??= accounts.first.id;
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedMoneyAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Deposit Account',
                      border: OutlineInputBorder(),
                    ),
                    items: accounts
                        .map(
                          (acc) => DropdownMenuItem<String>(
                            value: acc.id,
                            child: Text('${acc.name} (\$${acc.balance.toStringAsFixed(2)})'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedMoneyAccountId = val),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Payment Method
              DropdownButtonFormField<String>(
                initialValue: _selectedPaymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'check', child: Text('Check')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedPaymentMethod = val);
                  }
                },
                validator: PaymentValidators.validatePaymentMethod,
              ),
              const SizedBox(height: 12),

              // Payment Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Payment Amount *',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => PaymentValidators.validateAmount(
                  val,
                  widget.invoice.balanceDue,
                ),
              ),
              const SizedBox(height: 12),

              // Payment Date Picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Payment Date', style: TextStyle(fontSize: 12)),
                subtitle: Text(_paymentDate.toString().split(' ').first),
                trailing: const Icon(Icons.calendar_today, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _paymentDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() => _paymentDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),

              // Reference / Cheque No
              TextFormField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'Reference / Ref No (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_submitting ? 'Saving...' : 'Confirm Payment'),
        ),
      ],
    );
  }
}
