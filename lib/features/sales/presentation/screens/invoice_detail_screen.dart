import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/invoice_failure.dart';
import '../../application/invoice_models.dart';
import '../../application/invoice_state.dart';
import '../widgets/record_payment_dialog.dart';

final class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final invoiceAsync = ref.watch(invoiceDetailProvider(invoiceId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Details'),
        actions: [
          invoiceAsync.when(
            data: (invoice) {
              if (invoice.isDraft) {
                return IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Draft Invoice',
                  onPressed: () =>
                      context.push('/sales/invoices/$invoiceId/edit'),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  error is InvoiceFailure ? error.message : error.toString(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (invoice) => _InvoiceDetailContent(
          invoice: invoice,
          companyName: company.name,
        ),
      ),
    );
  }
}

final class _InvoiceDetailContent extends ConsumerStatefulWidget {
  const _InvoiceDetailContent({
    required this.invoice,
    required this.companyName,
  });

  final Invoice invoice;
  final String companyName;

  @override
  ConsumerState<_InvoiceDetailContent> createState() =>
      _InvoiceDetailContentState();
}

final class _InvoiceDetailContentState
    extends ConsumerState<_InvoiceDetailContent> {
  bool _issuing = false;

  Future<void> _markAsIssued() async {
    setState(() => _issuing = true);
    try {
      await ref
          .read(invoiceMutationControllerProvider.notifier)
          .markAsIssued(widget.invoice.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice marked as Issued!')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _issuing = false);
        final message =
            error is InvoiceFailure ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        invoice.documentNumber,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: invoice.isDraft
                              ? Colors.amber.shade100
                              : Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          invoice.status.toUpperCase(),
                          style: TextStyle(
                            color: invoice.isDraft
                                ? Colors.amber.shade900
                                : Colors.blue.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Company: ${widget.companyName}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Billed To',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            invoice.customerName ?? 'Customer',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Issue Date',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            invoice.issueDate.toString().split(' ').first,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (invoice.dueDate != null) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Due Date',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              invoice.dueDate!.toString().split(' ').first,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Items Table
          Text('Invoice Items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ...invoice.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.description,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '\$${item.lineTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              if (item.discountAmount > 0 || item.taxRate > 0)
                                Text(
                                  '${item.discountAmount > 0 ? "Disc: \$${item.discountAmount.toStringAsFixed(2)} " : ""}'
                                  '${item.taxRate > 0 ? "Tax (${item.taxRate}%): \$${item.taxAmount.toStringAsFixed(2)}" : ""}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Financial Breakdown
                  _SummaryRow(
                    label: 'Subtotal',
                    amount: invoice.subtotal,
                  ),
                  if (invoice.discountAmount > 0)
                    _SummaryRow(
                      label: 'Discount',
                      amount: -invoice.discountAmount,
                    ),
                  if (invoice.taxAmount > 0)
                    _SummaryRow(
                      label: 'Tax',
                      amount: invoice.taxAmount,
                    ),
                  const Divider(height: 24),
                  _SummaryRow(
                    label: 'Grand Total',
                    amount: invoice.grandTotal,
                    isBold: true,
                    fontSize: 18,
                  ),
                  _SummaryRow(
                    label: 'Balance Due',
                    amount: invoice.balanceDue,
                    isBold: true,
                    color: Colors.redAccent,
                  ),
                ],
              ),
            ),
          ),

          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Notes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(invoice.notes!),
                ),
              ),
            ),
          ],

          if (invoice.isDraft) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _issuing ? null : _markAsIssued,
                icon: _issuing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_issuing ? 'Updating...' : 'Mark as Issued'),
              ),
            ),
          ] else if (invoice.balanceDue > 0) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => RecordPaymentDialog.show(context, invoice),
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  'Record Payment (\$${invoice.balanceDue.toStringAsFixed(2)} Due)',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.isBold = false,
    this.fontSize = 14,
    this.color,
  });

  final String label;
  final double amount;
  final bool isBold;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
