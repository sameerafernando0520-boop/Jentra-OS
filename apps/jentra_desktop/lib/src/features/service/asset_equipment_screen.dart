import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asset_equipment_controller.dart';

final class AssetEquipmentWorkspace extends ConsumerWidget {
  const AssetEquipmentWorkspace({super.key, this.controller});
  final AssetEquipmentController? controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = controller ?? ref.watch(assetEquipmentControllerProvider);
    if (c == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Choose an authorized branch with service configuration and asset access.',
          ),
        ),
      );
    }
    final s = c.service;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => PopScope(
        canPop: s.form == null || s.confirmed != null,
        onPopInvokedWithResult: (popped, result) async {
          if (!popped && await s.canLeave() && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Internal asset equipment')),
          body: FocusTraversalGroup(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Maintain internal fixed assets',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Link an active asset to equipment using its named operational identity. Internal maintenance has no customer and is nonbillable. Linking creates no asset value or stock movement.',
                ),
                if (s.error != null || c.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      c.error ?? s.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (s.message != null)
                  Semantics(liveRegion: true, child: Text(s.message!)),
                if (s.busy || c.busy) const LinearProgressIndicator(),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: c.valid && !s.busy
                          ? () => unawaited(s.refresh())
                          : null,
                      child: const Text('Refresh equipment'),
                    ),
                    FilledButton(
                      onPressed: c.valid && !s.busy
                          ? () => unawaited(c.begin())
                          : null,
                      child: const Text('Link an internal asset'),
                    ),
                  ],
                ),
                for (final r in s.records.where(
                  (r) => r.toJson()['kind'] == 'asset',
                ))
                  Card(
                    child: ListTile(
                      title: Text(r.label),
                      subtitle: const Text(
                        'Internal equipment • immutable asset link',
                      ),
                      trailing: OutlinedButton(
                        onPressed: c.valid
                            ? () => unawaited(c.inspect(r.id))
                            : null,
                        child: const Text('Review source'),
                      ),
                    ),
                  ),
                if (c.valid &&
                    !s.busy &&
                    s.error == null &&
                    s.records.every((r) => r.toJson()['kind'] != 'asset'))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No internal asset equipment links in this branch.',
                    ),
                  ),
                if (s.cursor != null)
                  OutlinedButton(
                    onPressed: c.valid
                        ? () => unawaited(s.refresh(more: true))
                        : null,
                    child: const Text('Load more equipment'),
                  ),
                if (c.history != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Original asset: ${c.history!.source.name}'),
                          Text(
                            'Accountable location: ${c.history!.source.toJson()['location_name']}',
                          ),
                          Text(
                            'Ownership: ${c.history!.source.toJson()['ownership']}',
                          ),
                          Text('Link reason: ${c.history!.reason}'),
                          const Text(
                            'Dispatch and maintenance recheck current active status and branch. Original source identity is retained.',
                          ),
                        ],
                      ),
                    ),
                  ),
                if (s.form != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Link internal equipment',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          OutlinedButton(
                            onPressed: c.valid && !s.locked
                                ? () => unawaited(c.loadSources())
                                : null,
                            child: Text(
                              c.selected == null
                                  ? 'Choose an active named asset'
                                  : 'Asset: ${c.selected!.name}',
                            ),
                          ),
                          for (final source in c.sources)
                            ListTile(
                              title: Text('${source.code} • ${source.name}'),
                              subtitle: Text(
                                '${source.toJson()['location_name']} • ${source.toJson()['ownership']}',
                              ),
                              onTap: s.locked ? null : () => c.choose(source),
                            ),
                          if (c.sourcesLoaded &&
                              !c.busy &&
                              c.error == null &&
                              c.sources.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No active, unlinked assets are eligible in this branch.',
                              ),
                            ),
                          if (c.next != null)
                            OutlinedButton(
                              onPressed: c.valid && !c.busy
                                  ? () => unawaited(c.loadSources(more: true))
                                  : null,
                              child: const Text('Load more assets'),
                            ),
                          for (final field in [
                            'code',
                            'name',
                            'identity',
                            'reason',
                          ])
                            _AssetEquipmentField(
                              key: ValueKey('asset-link:${s.formEpoch}:$field'),
                              controller: c,
                              field: field,
                            ),
                          const Text(
                            'The selected asset version is frozen when the request is sealed. A changed source requires a new reviewed draft.',
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed: c.valid && !s.locked
                                    ? () async {
                                        try {
                                          await s.save();
                                        } catch (_) {}
                                      }
                                    : null,
                                child: const Text('Save encrypted draft'),
                              ),
                              FilledButton(
                                onPressed: c.valid && !s.locked
                                    ? () => unawaited(s.send())
                                    : null,
                                child: const Text('Create equipment link'),
                              ),
                              if (s.pending != null)
                                OutlinedButton(
                                  onPressed: c.valid && !s.busy
                                      ? () => unawaited(s.reconcile())
                                      : null,
                                  child: const Text(
                                    'Reconcile original request',
                                  ),
                                ),
                              if (s.pending != null && s.confirmed == null)
                                OutlinedButton(
                                  onPressed: c.valid && !s.busy
                                      ? () => unawaited(s.send())
                                      : null,
                                  child: const Text('Retry original request'),
                                ),
                              OutlinedButton(
                                onPressed: !s.busy && s.pending == null
                                    ? () => unawaited(s.discard())
                                    : null,
                                child: const Text('Discard draft'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  'Encrypted recovery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                OutlinedButton(
                  onPressed: c.valid && !s.busy
                      ? () => unawaited(s.loadRecovery())
                      : null,
                  child: const Text('Refresh saved drafts'),
                ),
                for (final saved in s.recovery)
                  ListTile(
                    title: Text(
                      saved.draft.form['name'] as String? ??
                          'Internal equipment draft',
                    ),
                    subtitle: Text(
                      saved.draft.pending == null
                          ? 'Saved encrypted draft'
                          : 'Original request requires reconciliation',
                    ),
                    onTap: c.valid ? () => unawaited(s.resume(saved)) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _AssetEquipmentField extends StatefulWidget {
  const _AssetEquipmentField({
    super.key,
    required this.controller,
    required this.field,
  });
  final AssetEquipmentController controller;
  final String field;
  @override
  State<_AssetEquipmentField> createState() => _AssetEquipmentFieldState();
}

final class _AssetEquipmentFieldState extends State<_AssetEquipmentField> {
  late final TextEditingController input;
  String get value =>
      widget.controller.service.form?[widget.field] as String? ?? '';
  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: value);
  }

  @override
  void didUpdateWidget(_AssetEquipmentField old) {
    super.didUpdateWidget(old);
    if (input.text != value) {
      input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: input,
      enabled: !widget.controller.service.locked,
      decoration: InputDecoration(
        labelText: switch (widget.field) {
          'code' => 'Equipment code',
          'name' => 'Equipment name',
          'identity' => 'Operational identity',
          _ => 'Link reason',
        },
      ),
      onChanged: (v) => widget.controller.service.edit(widget.field, v),
    ),
  );
}
