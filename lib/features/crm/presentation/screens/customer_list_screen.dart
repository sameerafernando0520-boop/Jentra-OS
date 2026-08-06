import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/customer_models.dart';
import '../../application/customer_state.dart';
import '../widgets/customer_feedback.dart';

final class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

final class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
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
      ref.read(customerControllerProvider.notifier).updateSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final customers = ref.watch(customerControllerProvider);
    return customers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CustomerListError(
        message: CustomerFeedback.userMessage(error),
        onRetry: () =>
            ref.read(customerControllerProvider.notifier).refreshCustomers(),
      ),
      data: (state) => _CustomerListContent(
        key: ValueKey('customer-list-company-${company.id}'),
        companyName: company.name,
        state: state,
        searchController: _searchController,
        onSearchChanged: _scheduleSearch,
        onClearSearch: () {
          _searchController.clear();
          _scheduleSearch('');
        },
        onIncludeInactiveChanged: (value) => ref
            .read(customerControllerProvider.notifier)
            .setIncludeInactive(value),
        onRefresh: () =>
            ref.read(customerControllerProvider.notifier).refreshCustomers(),
        onLoadMore: () =>
            ref.read(customerControllerProvider.notifier).loadMore(),
      ),
    );
  }
}

final class _CustomerListContent extends StatelessWidget {
  const _CustomerListContent({
    required this.companyName,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onIncludeInactiveChanged,
    required this.onRefresh,
    required this.onLoadMore,
    super.key,
  });

  final String companyName;
  final CustomerState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppConstants.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isRefreshing) const LinearProgressIndicator(),
                  if (state.isRefreshing) const SizedBox(height: 12),
                  _CustomerListHeader(companyName: companyName),
                  const SizedBox(height: 20),
                  _CustomerFilters(
                    controller: searchController,
                    includeInactive: state.includeInactive,
                    onSearchChanged: onSearchChanged,
                    onClearSearch: onClearSearch,
                    onIncludeInactiveChanged: onIncludeInactiveChanged,
                  ),
                  const SizedBox(height: 16),
                  if (state.customers.isEmpty)
                    _CustomerEmptyState(hasSearch: state.search.isNotEmpty)
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < state.customers.length;
                            index++
                          ) ...[
                            _CustomerListTile(customer: state.customers[index]),
                            if (index != state.customers.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  if (state.nextCursor != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: state.isLoadingMore ? null : onLoadMore,
                        icon: state.isLoadingMore
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more),
                        label: Text(
                          state.isLoadingMore
                              ? 'Loading customers…'
                              : 'Load more',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _CustomerListHeader extends StatelessWidget {
  const _CustomerListHeader({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customers', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Manage customer records for $companyName.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        );
        final action = FilledButton.icon(
          onPressed: () => context.go('/crm/customers/new'),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Add customer'),
        );

        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 14), action],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            action,
          ],
        );
      },
    );
  }
}

final class _CustomerFilters extends StatelessWidget {
  const _CustomerFilters({
    required this.controller,
    required this.includeInactive,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onIncludeInactiveChanged,
  });

  final TextEditingController controller;
  final bool includeInactive;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<bool> onIncludeInactiveChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 240, maxWidth: 560),
              child: TextField(
                controller: controller,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Search customers',
                  hintText: 'Name, email, phone, or tax number',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
            FilterChip(
              selected: includeInactive,
              onSelected: onIncludeInactiveChanged,
              avatar: const Icon(Icons.archive_outlined, size: 18),
              label: const Text('Include inactive'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CustomerListTile extends StatelessWidget {
  const _CustomerListTile({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final contact =
        customer.email ?? customer.primaryPhone ?? 'No contact details';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      onTap: () => context.go('/crm/customers/${customer.id}'),
      leading: CircleAvatar(child: Text(_initials(customer.title))),
      title: Text(customer.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(contact, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(isActive: customer.isActive),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isActive ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

final class _CustomerEmptyState extends StatelessWidget {
  const _CustomerEmptyState({required this.hasSearch});

  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
        child: Column(
          children: [
            const Icon(Icons.people_outline, size: 48),
            const SizedBox(height: 14),
            Text(
              hasSearch ? 'No matching customers' : 'No customers yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch
                  ? 'Try another name, email, phone, or tax number.'
                  : 'Create the first customer for this company.',
              textAlign: TextAlign.center,
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => context.go('/crm/customers/new'),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add customer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _CustomerListError extends StatelessWidget {
  const _CustomerListError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              'Customers unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  return words.map((word) => word[0].toUpperCase()).join();
}
