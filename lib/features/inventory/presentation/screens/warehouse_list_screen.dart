import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/inventory_failure.dart';
import '../../application/inventory_models.dart';
import '../../application/inventory_state.dart';

final class WarehouseListScreen extends ConsumerWidget {
  const WarehouseListScreen({super.key});

  void _showAddWarehouseDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final addressController = TextEditingController();
    bool isDefault = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Warehouse'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Warehouse Name *',
                    hintText: 'e.g. Main Warehouse',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    hintText: 'e.g. WH-MAIN',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Building, City, State',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(dialogContext);
                try {
                  await ref
                      .read(warehouseControllerProvider.notifier)
                      .createWarehouse(
                        WarehouseInput(
                          name: name,
                          code: codeController.text.trim(),
                          address: addressController.text.trim(),
                          isDefault: isDefault,
                        ),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Warehouse added successfully')),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    final message =
                        error is InventoryFailure ? error.message : error.toString();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final warehousesAsync = ref.watch(warehouseControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Warehouses - ${company.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Add Warehouse',
            onPressed: () => _showAddWarehouseDialog(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddWarehouseDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Warehouse'),
      ),
      body: warehousesAsync.when(
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
                  error is InventoryFailure ? error.message : error.toString(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(warehouseControllerProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (warehouses) {
          if (warehouses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warehouse_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No warehouses registered yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a warehouse to start tracking stock locations.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showAddWarehouseDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Warehouse'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: warehouses.length,
            itemBuilder: (context, index) {
              final wh = warehouses[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: wh.isDefault
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.grey.shade200,
                    child: Icon(
                      Icons.warehouse,
                      color: wh.isDefault
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Colors.grey.shade700,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        wh.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (wh.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Default',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${wh.code != null ? "Code: ${wh.code} • " : ""}'
                    '${wh.address ?? "No address specified"}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
