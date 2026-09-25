import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'cash_flow_mapping_controller.dart';

class CashFlowMappingScreen extends ConsumerWidget {
  const CashFlowMappingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(businessCapabilitiesProvider);
    if (access.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (access.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final controller = ref.watch(cashFlowMappingControllerProvider);
    return controller == null
        ? const Center(
            child: Text('Choose a branch with cash-flow configuration access.'),
          )
        : CashFlowMappingWorkspace(
            key: ValueKey(controller),
            controller: controller,
          );
  }
}

class CashFlowMappingWorkspace extends StatelessWidget {
  const CashFlowMappingWorkspace({super.key, required this.controller});
  final CashFlowMappingController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.verified || c.denied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.error ??
                    'Connect to verify access and restore the encrypted classification draft.',
              ),
              if (c.busy) const CircularProgressIndicator(),
              TextButton(
                onPressed: c.online && !c.busy ? c.initialize : null,
                child: const Text('Verify access'),
              ),
            ],
          ),
        );
      }
      final width =
          280.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cash-flow classifications',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Each dated decision is immutable. New indirect cash-flow reports freeze the classification visible at their cutoff.',
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => context.go('/finance/statements'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Financial statements'),
            ),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (c.message != null) Text(c.message!),
            if (c.busy) const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Configure account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('account-${c.form['id']}'),
                    initialValue: c.selectedAccount?['id'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Posting account',
                    ),
                    items: [
                      for (final row in c.accounts)
                        if (row['status'] == 'active')
                          DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text('${row['code']} · ${row['name']}'),
                          ),
                    ],
                    onChanged: c.locked || !c.online
                        ? null
                        : (value) {
                            if (value != null) c.select(value);
                          },
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('category-${c.form['id']}'),
                    initialValue: c.form['category'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cash-flow category',
                    ),
                    items: [
                      for (final entry
                          in CashFlowMappingController.categories.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (value) => c.field('category', value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('date-${c.form['id']}'),
                    initialValue: c.form['effective_date'] as String? ?? '',
                    enabled: !c.locked,
                    decoration: const InputDecoration(
                      labelText: 'Effective date (YYYY-MM-DD)',
                    ),
                    onChanged: (value) => c.field('effective_date', value),
                  ),
                ),
                SizedBox(
                  width: width * 1.5,
                  child: TextFormField(
                    key: ValueKey('reason-${c.form['id']}'),
                    initialValue: c.form['reason'] as String? ?? '',
                    enabled: !c.locked,
                    maxLength: 1000,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    onChanged: (value) => c.field('reason', value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: c.online && !c.locked && c.selectedAccount != null
                      ? c.configure
                      : null,
                  child: const Text('Record classification'),
                ),
                OutlinedButton(
                  onPressed: !c.locked && c.selectedAccount != null
                      ? c.save
                      : null,
                  child: const Text('Save encrypted draft'),
                ),
                if (c.pending)
                  FilledButton.tonal(
                    onPressed: c.online && !c.busy ? c.retry : null,
                    child: const Text('Retry sealed request'),
                  ),
                TextButton(
                  onPressed: c.online && !c.busy ? c.refresh : null,
                  child: const Text('Refresh accounts'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Account mappings as of ${c.today}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final row in c.accounts)
              ListTile(
                title: Text('${row['code']} · ${row['name']}'),
                subtitle: Text(
                  '${row['account_type']} · ${CashFlowMappingController.categories[row['category']] ?? 'Unmapped'}${row['effective_date'] == null ? '' : ' · effective ${row['effective_date']}'} · version ${row['version'] ?? 0}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: c.locked || row['status'] != 'active'
                    ? null
                    : () => c.select(row['id'] as String),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: c.busy ? null : c.moreAccounts,
                child: const Text('More accounts'),
              ),
          ],
        ),
      );
    },
  );
}
