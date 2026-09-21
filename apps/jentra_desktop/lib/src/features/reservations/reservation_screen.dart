import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_providers.dart';
import 'reservation_controller.dart';

class ReservationScreen extends ConsumerWidget {
  const ReservationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(reservationControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose a scope with reservation-management permission.'),
      );
    }
    return ReservationWorkspace(key: ValueKey(c), controller: c);
  }
}

class ReservationWorkspace extends StatelessWidget {
  const ReservationWorkspace({required this.controller, super.key});
  final ReservationController controller;
  Future<void> confirm(BuildContext context) async {
    if (controller.local?.pending != null) {
      await controller.release();
      return;
    }
    final f = controller.form!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release this reservation?'),
        content: SingleChildScrollView(
          child: Text(
            'Release ${f['base_quantity']} base units of ${f['product_name']} for ${f['document_number']}.\n\nMode: ${f['mode']}\nReason: ${f['reason']}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm release'),
          ),
        ],
      ),
    );
    if (accepted == true && !controller.locked) await controller.release();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, f = c.form;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Stock reservations',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Review held quantities and release allocations with a recorded reason.',
          ),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — saved work is available. Connect to release or refresh.',
            ),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Semantics(liveRegion: true, child: Text(c.message!)),
          if (f == null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  'active': 'Active',
                  'expired': 'Expired',
                  'retired': 'Retired products',
                  'all': 'All history',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: c.filter == entry.key,
                    onSelected: c.busy || !c.online
                        ? null
                        : (_) => c.refresh(selection: entry.key),
                  ),
                OutlinedButton.icon(
                  onPressed: c.busy || !c.online ? null : c.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (c.items.isEmpty && !c.busy)
              const Text('No reservations in this queue.'),
            for (final row in c.items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['document_number']} · ${row['product_name']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${row['warehouse_name']} · ${row['base_quantity']} base units · ${row['status']}',
                      ),
                      Text('Expires ${row['expires_at']}'),
                      TextButton(
                        onPressed: c.locked ? null : () => c.open(row),
                        child: const Text('Review reservation'),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: c.busy || !c.online
                    ? null
                    : () => c.refresh(more: true),
                child: const Text('Load more reservations'),
              ),
            const Divider(height: 40),
            Text(
              'Held stock at a past time',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Historical quantities use recorded reservation events. Reference names are current labels.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: c.reportInstant,
              enabled: !c.busy,
              decoration: const InputDecoration(
                labelText: 'As-of time (UTC)',
                hintText: '2026-09-19T12:00:00Z',
              ),
              onChanged: (value) => c.reportInstant = value,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: c.busy || !c.online ? null : c.loadReport,
                child: const Text('Load dated reservations'),
              ),
            ),
            if (c.loadedReportInstant != null) ...[
              Text(
                'Loaded at ${c.loadedReportInstant} · History starts ${c.reportCoverage}',
              ),
              if (c.reportRows.isEmpty)
                const Text('No held allocations at this time.'),
              for (final row in c.reportRows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['document_number']} · ${row['product_name']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${row['warehouse_name']} · ${row['base_quantity']} base units · Version ${row['version']}',
                        ),
                      ],
                    ),
                  ),
                ),
              if (c.reportCursor != null)
                TextButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.loadReport(more: true),
                  child: const Text('Load more dated reservations'),
                ),
            ],
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f['document_number']} · ${f['product_name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${f['warehouse_name']} · ${f['base_quantity']} base units',
                    ),
                    Text(
                      '${f['status']} · Version ${f['version']} · Expires ${f['expires_at']}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (f['status'] == 'active') ...[
              DropdownButtonFormField<String>(
                key: ValueKey('${f['id']}-${f['version']}-mode'),
                initialValue: f['mode'] as String,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Release mode'),
                items: const [
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text('Manual review'),
                  ),
                  DropdownMenuItem(
                    value: 'expired',
                    child: Text('Expired reservation'),
                  ),
                  DropdownMenuItem(
                    value: 'retired',
                    child: Text('Retired product'),
                  ),
                ],
                onChanged: c.locked ? null : (v) => c.update('mode', v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey('${f['id']}-${f['version']}-reason'),
                initialValue: f['reason'] as String? ?? '',
                enabled: !c.locked,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Release reason'),
                onChanged: (v) => c.update('reason', v),
              ),
            ] else
              Text('Release reason: ${f['release_reason'] ?? ''}'),
            if (c.local?.pending != null)
              const Text(
                'The outcome is uncertain. The saved request is sealed; retry it to confirm the result.',
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (f['status'] == 'active')
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => confirm(context),
                    child: Text(
                      c.local?.pending == null
                          ? 'Release reservation'
                          : 'Retry saved release',
                    ),
                  ),
                OutlinedButton(
                  onPressed: c.locked ? null : c.save,
                  child: const Text('Save locally'),
                ),
                OutlinedButton(
                  onPressed: c.busy || !c.online ? null : c.history,
                  child: const Text('Load history'),
                ),
                TextButton(
                  onPressed: c.locked ? null : c.close,
                  child: const Text('Discard local copy / close'),
                ),
              ],
            ),
            if (c.coverageStart != null) ...[
              const SizedBox(height: 24),
              Text(
                'Reservation history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'History coverage starts ${c.coverageStart}. Earlier changes are not reconstructed.',
              ),
              if (c.events.isEmpty)
                const Text('No changes recorded since coverage began.'),
              for (final event in c.events)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Version ${event['version']} · ${event['recorded_at']}${event['baseline'] == true ? ' · Coverage baseline' : ''}',
                        ),
                        Text(
                          '${(event['snapshot'] as Map)['status']} · ${(event['snapshot'] as Map)['base_quantity']} base units',
                        ),
                        if ((event['snapshot'] as Map)['release_reason'] !=
                            null)
                          Text(
                            '${(event['snapshot'] as Map)['release_reason']}',
                          ),
                      ],
                    ),
                  ),
                ),
              if (c.historyCursor != null)
                TextButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.history(more: true),
                  child: const Text('Load older history'),
                ),
            ],
          ],
        ],
      );
    },
  );
}
