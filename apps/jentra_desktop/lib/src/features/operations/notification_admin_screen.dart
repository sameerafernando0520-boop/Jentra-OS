import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import '../../app_providers.dart';
import 'notification_admin_controller.dart';

class NotificationAdminScreen extends ConsumerWidget {
  const NotificationAdminScreen({super.key});
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
    final controller = ref.watch(notificationAdminControllerProvider);
    return controller == null
        ? const Center(
            child: Text(
              'Choose a permitted notification administration scope.',
            ),
          )
        : NotificationAdminWorkspace(
            key: ValueKey(controller),
            controller: controller,
          );
  }
}

class NotificationAdminWorkspace extends StatefulWidget {
  const NotificationAdminWorkspace({super.key, required this.controller});
  final NotificationAdminController controller;
  @override
  State<NotificationAdminWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<NotificationAdminWorkspace> {
  String? recipient;
  String event = 'posting', kind = 'AP';
  late final cutoff = TextEditingController(
    text: DateTime.now().toUtc().toIso8601String().substring(0, 10),
  );
  @override
  void dispose() {
    cutoff.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final members = c.pages['members'] ?? [];
      final selected = members.any((row) => row['id'] == recipient)
          ? recipient
          : null;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Notification administration',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text(
            'Subscriptions apply to the selected entity and branch. Recipients still need current source access.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline. Server configuration has been cleared; a saved request can be retried when connected.',
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
          if (c.diagnosticStatus != null)
            Semantics(
              liveRegion: true,
              child: Text(
                'Undelivered events awaiting review: ${c.diagnosticStatus!['dead_letter_depth']}',
              ),
            ),
          if (c.gateway is Wave3DiagnosticGateway)
            TextButton(
              onPressed: c.busy || !c.online || c.denied
                  ? null
                  : c.refreshDiagnostics,
              child: const Text('Refresh delivery queue status'),
            ),
          if (c.pending) ...[
            const Text(
              'An action awaits confirmation. Retry uses its original identity, version, date and payload.',
            ),
            FilledButton(
              onPressed: c.busy || !c.online || c.denied ? null : c.retry,
              child: const Text('Retry saved notification action'),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Active member identity',
            ),
            items: [
              for (final row in members)
                DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(row['id'] as String),
                ),
            ],
            onChanged: c.locked || !c.online
                ? null
                : (value) => setState(() => recipient = value),
          ),
          if (c.cursors['members'] != null)
            TextButton(
              onPressed: c.busy || !c.online
                  ? null
                  : () => c.refresh('members', more: true),
              child: const Text('Load more active members'),
            ),
          DropdownButtonFormField<String>(
            initialValue: event,
            decoration: const InputDecoration(labelText: 'Event class'),
            items: [
              for (final value in wave3NoticeClasses)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: c.locked
                ? null
                : (value) => setState(() => event = value!),
          ),
          FilledButton(
            onPressed: c.locked || !c.online || selected == null
                ? null
                : () => c.configure(selected, event),
            child: const Text('Enable scoped subscription'),
          ),
          const SizedBox(height: 16),
          Text('Subscriptions', style: Theme.of(context).textTheme.titleLarge),
          OutlinedButton(
            onPressed: c.busy || !c.online
                ? null
                : () => c.refresh('subscriptions'),
            child: const Text('Refresh current configuration'),
          ),
          for (final row in c.pages['subscriptions'] ?? [])
            Card(
              child: ListTile(
                title: Text(
                  '${row['event_class']} · ${row['enabled'] == true ? 'enabled' : 'disabled'}',
                ),
                subtitle: Text(
                  'Member ${row['recipient_id']} · ${row['recipient_status']} · Version ${row['version']}',
                ),
                trailing: TextButton(
                  onPressed:
                      c.locked ||
                          !c.online ||
                          (row['enabled'] != true &&
                              row['recipient_status'] != 'active')
                      ? null
                      : () => c.toggle(row),
                  child: Text(row['enabled'] == true ? 'Disable' : 'Enable'),
                ),
              ),
            ),
          if (c.cursors['subscriptions'] != null)
            TextButton(
              onPressed: c.busy || !c.online
                  ? null
                  : () => c.refresh('subscriptions', more: true),
              child: const Text('Load more subscriptions'),
            ),
          const SizedBox(height: 20),
          Text('Dated due scan', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'Review due receivables or payables for the selected date and notify configured recipients. Continue through every page until complete.',
          ),
          DropdownButtonFormField<String>(
            initialValue: kind,
            items: const [
              DropdownMenuItem(value: 'AP', child: Text('Payables')),
              DropdownMenuItem(value: 'AR', child: Text('Receivables')),
            ],
            onChanged: c.locked
                ? null
                : (value) => setState(() => kind = value!),
          ),
          TextField(
            controller: cutoff,
            enabled: !c.locked,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'As of (YYYY-MM-DD)'),
          ),
          FilledButton(
            onPressed:
                c.locked ||
                    !c.online ||
                    !c.permissions.contains(
                      kind == 'AR'
                          ? 'finance.receipts.view'
                          : 'finance.payments.manage',
                    )
                ? null
                : () => c.scan(kind, cutoff.text),
            child: const Text('Scan one due page'),
          ),
          if (c.scanResult case final result?) ...[
            Text(
              'Confirmed ${result['kind']} scan as of ${result['as_of']} · Examined ${result['examined']} · Notices emitted ${result['emitted']}',
            ),
            Text(
              result['has_more'] == true
                  ? 'More due items remain.'
                  : 'Due scan page sequence complete.',
            ),
            if (result['has_more'] == true)
              OutlinedButton(
                onPressed:
                    c.locked ||
                        !c.online ||
                        result['kind'] != kind ||
                        result['as_of'] != cutoff.text
                    ? null
                    : () => c.scan(kind, cutoff.text, more: true),
                child: const Text('Scan next due page'),
              ),
          ],
        ],
      );
    },
  );
}
