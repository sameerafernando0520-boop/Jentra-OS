import '../operations/access_changed.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'product_unit_controller.dart';
import 'procurement_picker.dart';

class ProductUnitScreen extends ConsumerWidget {
  const ProductUnitScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(productUnitControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose a business scope with catalogue-management permission.',
        ),
      );
    }
    return ProductUnitWorkspace(key: ValueKey(c), controller: c);
  }
}

class ProductUnitWorkspace extends StatelessWidget {
  const ProductUnitWorkspace({super.key, required this.controller});
  final ProductUnitController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (c.accessDenied) {
        return OperationalAccessChanged(
          retry: c.initialize,
          enabled: c.online && !c.busy,
        );
      }
      final f = c.form;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Product units',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Define how purchasing units convert to each product’s base unit.',
            ),
            const SizedBox(height: 16),
            if (c.busy) const LinearProgressIndicator(),
            if (!c.online) const Text('Offline · save changes on this device.'),
            if (c.error != null)
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (c.message != null) Text(c.message!),
            const SizedBox(height: 16),
            if (f == null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: c.busy ? null : c.edit,
                    icon: const Icon(Icons.add),
                    label: const Text('New product unit'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online ? null : c.refresh,
                    child: const Text('Refresh'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/procurement'),
                    child: const Text('Procurement'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.page.items.isEmpty && !c.busy)
                const Text('No product unit conversions loaded.'),
              for (final row in c.page.items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${row['_product_name']} · ${row['_unit_name']}',
                    ),
                    subtitle: Text(
                      '${row['numerator']} / ${row['denominator']} base units · ${row['status']} · v${row['version']}',
                    ),
                    onTap: c.busy ? null : () => c.edit(row),
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('Load more'),
                ),
            ] else
              Column(
                key: ValueKey(f['id']),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.version == null
                        ? 'New conversion'
                        : 'Edit conversion · v${c.version}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      OutlinedButton(
                        onPressed: c.locked || !c.online || c.version != null
                            ? null
                            : () async {
                                final p = await pickSourcingReference(
                                  context,
                                  c.references,
                                  c.scope,
                                  'catalogue_products',
                                  access: c,
                                );
                                if (p != null) {
                                  c.update('product_id', p['id']);
                                  c.update('_product_name', p['name']);
                                }
                              },
                        child: Text(
                          '${f['_product_name'] ?? 'Choose product'}',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: c.locked || !c.online || c.version != null
                            ? null
                            : () async {
                                final u = await pickSourcingReference(
                                  context,
                                  c.references,
                                  c.scope,
                                  'units',
                                  access: c,
                                );
                                if (u != null) {
                                  c.update('unit_id', u['id']);
                                  c.update('_unit_name', u['name']);
                                }
                              },
                        child: Text(
                          '${f['_unit_name'] ?? 'Choose transaction unit'}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'One transaction unit equals numerator / denominator base units. For a carton of 12, enter 12 and 1.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final entry in const {
                        'numerator': 'Numerator',
                        'denominator': 'Denominator',
                      }.entries)
                        SizedBox(
                          width: 260,
                          child: TextFormField(
                            initialValue: '${f[entry.key]}',
                            enabled: !c.locked,
                            decoration: InputDecoration(labelText: entry.value),
                            onChanged: (v) => c.update(entry.key, v),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available for new documents'),
                    value: f['status'] == 'active',
                    onChanged: c.locked
                        ? null
                        : (v) => c.update('status', v ? 'active' : 'inactive'),
                  ),
                  const Text(
                    'Existing documents keep their recorded conversion. Entity-level catalogue authority is required to change this shared product setting.',
                  ),
                  const SizedBox(height: 24),
                  if (c.local?.pending != null)
                    const Text(
                      'Retry the saved command to confirm its outcome.',
                    ),
                  if (c.local?.errorCode == 'VERSION_CONFLICT')
                    const Text(
                      'This conversion changed. Preserve your notes, discard the local edit and refresh.',
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed:
                            c.busy ||
                                !c.online ||
                                c.local?.errorCode == 'VERSION_CONFLICT'
                            ? null
                            : c.saveServer,
                        child: Text(
                          c.local?.pending != null
                              ? 'Retry saved command'
                              : 'Save to server',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: c.locked ? null : c.saveLocal,
                        child: const Text('Save on this device'),
                      ),
                      TextButton(
                        onPressed: c.busy || c.local?.pending != null
                            ? null
                            : () async {
                                final discard = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Discard local conversion draft?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Keep editing'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Discard'),
                                      ),
                                    ],
                                  ),
                                );
                                if (discard == true) {
                                  await c.discard();
                                }
                              },
                        child: const Text('Discard local draft'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );
}
