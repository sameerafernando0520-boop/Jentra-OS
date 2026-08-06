import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/invoice_failure.dart';
import '../../application/invoice_state.dart';

final class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

final class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(invoiceControllerProvider.notifier).updateSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final invoicesAsync = ref.watch(invoiceControllerProvider);

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _InvoiceListError(
        message: error is InvoiceFailure ? error.message : error.toString(),
        onRetry: () =>
            ref.read(invoiceControllerProvider.notifier).refreshInvoices(),
      ),
      data: (state) => _InvoiceListContent(
        key: ValueKey('invoice-list-company-${company.id}'),
        companyName: company.name,
        state: state,
        searchController: _searchController,
        onSearchChanged: _scheduleSearch,
        onClearSearch: () {
          _searchController.clear();
          _scheduleSearch('');
        },
        onStatusSelected: (status) => ref
            .read(invoiceControllerProvider.notifier)
            .filterByStatus(status),
        onRefresh: () =>
            ref.read(invoiceControllerProvider.notifier).refreshInvoices(),
        onLoadMore: () =>
            ref.read(invoiceControllerProvider.notifier).loadMore(),
      ),
    );
  }
}

final class _InvoiceListContent extends StatelessWidget {
  const _InvoiceListContent({
    required this.companyName,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusSelected,
    required this.onRefresh,
    required this.onLoadMore,
    super.key,
  });

  final String companyName;
  final InvoiceState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onStatusSelected;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sales Invoices - $companyName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Invoice',
            onPressed: () => context.push('/sales/invoices/new'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sales/invoices/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search invoices by document number...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: onClearSearch,
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('All Statuses'),
                            selected: state.selectedStatus == null,
                            onSelected: (_) => onStatusSelected(null),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Draft'),
                            selected: state.selectedStatus == 'draft',
                            onSelected: (_) => onStatusSelected('draft'),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Issued'),
                            selected: state.selectedStatus == 'issued',
                            onSelected: (_) => onStatusSelected('issued'),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Paid'),
                            selected: state.selectedStatus == 'paid',
                            onSelected: (_) => onStatusSelected('paid'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (state.invoices.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.search.isNotEmpty || state.selectedStatus != null
                              ? 'No invoices match your search'
                              : 'No sales invoices created yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a sales invoice to bill your customers.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => context.push('/sales/invoices/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Create Invoice'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= state.invoices.length) {
                      if (state.canLoadMore) {
                        onLoadMore();
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    final invoice = state.invoices[index];
                    final isDraft = invoice.status == 'draft';
                    final isPaid = invoice.status == 'paid';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isPaid
                              ? Colors.green.shade100
                              : (isDraft ? Colors.amber.shade100 : Colors.blue.shade100),
                          child: Icon(
                            Icons.receipt,
                            color: isPaid
                                ? Colors.green.shade800
                                : (isDraft ? Colors.amber.shade900 : Colors.blue.shade800),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              invoice.documentNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(status: invoice.status),
                          ],
                        ),
                        subtitle: Text(
                          '${invoice.customerName ?? "Customer"} • '
                          'Issued: ${invoice.issueDate.toString().split(' ').first}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${invoice.grandTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (!isPaid)
                              Text(
                                'Due: \$${invoice.balanceDue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.redAccent,
                                ),
                              ),
                          ],
                        ),
                        onTap: () =>
                            context.push('/sales/invoices/${invoice.id}'),
                      ),
                    );
                  },
                  childCount: state.invoices.length + (state.canLoadMore ? 1 : 0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;

    switch (status) {
      case 'issued':
        bg = Colors.blue.shade100;
        text = Colors.blue.shade900;
        break;
      case 'paid':
        bg = Colors.green.shade100;
        text = Colors.green.shade900;
        break;
      case 'partially_paid':
        bg = Colors.orange.shade100;
        text = Colors.orange.shade900;
        break;
      case 'void':
      case 'cancelled':
        bg = Colors.red.shade100;
        text = Colors.red.shade900;
        break;
      case 'draft':
      default:
        bg = Colors.grey.shade200;
        text = Colors.grey.shade800;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }
}

final class _InvoiceListError extends StatelessWidget {
  const _InvoiceListError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
