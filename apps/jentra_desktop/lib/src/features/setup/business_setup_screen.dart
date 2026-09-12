import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'business_setup_controller.dart';
import '../tenant/stock_opening_access.dart';

class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({this.initialResource, super.key});
  final BusinessSetupResource? initialResource;

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  bool _initialResourceApplied = false;

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(businessSetupControllerProvider);
    if (!_initialResourceApplied && !setup.isLoading && setup.hasValue) {
      _initialResourceApplied = true;
      final resource = widget.initialResource;
      if (resource != null &&
          resource != setup.value!.resource &&
          setup.value!.capabilities.contains(resource.viewPermission)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(
              ref
                  .read(businessSetupControllerProvider.notifier)
                  .selectResource(resource),
            );
          }
        });
      }
    }
    return setup.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: JentraEmptyState(
          icon: Icons.domain_disabled_outlined,
          title: 'Business scope unavailable',
          description: error.toString(),
          action: JentraPrimaryButton(
            label: 'Try again',
            onPressed: () => ref.invalidate(businessScopeProvider),
          ),
        ),
      ),
      data: (state) => _SetupWorkspace(state: state),
    );
  }
}

class _SetupWorkspace extends ConsumerWidget {
  const _SetupWorkspace({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(businessScopeProvider).value;
    final accessibilityLayout =
        MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    if (accessibilityLayout) {
      return Padding(
        padding: const EdgeInsets.all(JentraSpacing.x5),
        child: ListView(
          children: [
            _PageHeader(state: state),
            const SizedBox(height: JentraSpacing.x4),
            if (scope != null) _ScopeStrip(scope: scope),
            const SizedBox(height: JentraSpacing.x4),
            _CompactResourcePicker(state: state),
            const SizedBox(height: JentraSpacing.x3),
            SizedBox(height: 680, child: _ResourcePanel(state: state)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(JentraSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(state: state),
          const SizedBox(height: JentraSpacing.x4),
          if (scope != null) _ScopeStrip(scope: scope),
          const SizedBox(height: JentraSpacing.x4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 1080) {
                  return Column(
                    children: [
                      _CompactResourcePicker(state: state),
                      const SizedBox(height: JentraSpacing.x3),
                      Expanded(child: _ResourcePanel(state: state)),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 164, child: _CategoryRail(state: state)),
                    const SizedBox(width: JentraSpacing.x3),
                    SizedBox(width: 218, child: _ResourceRail(state: state)),
                    const SizedBox(width: JentraSpacing.x3),
                    Expanded(child: _ResourcePanel(state: state)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends ConsumerWidget {
  const _PageHeader({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: JentraSpacing.x3,
              runSpacing: JentraSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Business setup',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const JentraStatusBadge(
                  label: 'Shared foundation',
                  tone: JentraStatusTone.info,
                ),
                JentraStatusBadge(
                  label: state.isOnline
                      ? 'Online confirmation ready'
                      : state.fromCache
                      ? 'Offline · cached view'
                      : 'Offline',
                  tone: state.isOnline
                      ? JentraStatusTone.success
                      : JentraStatusTone.warning,
                ),
              ],
            ),
            const SizedBox(height: JentraSpacing.x1),
            Text(
              'Govern the records every Jentra workflow depends on.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.jentraColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      const StockOpeningInviteButton(),
      IconButton(
        tooltip: 'Refresh setup data',
        onPressed: state.loading
            ? null
            : () =>
                  ref.read(businessSetupControllerProvider.notifier).refresh(),
        icon: const Icon(Icons.refresh),
      ),
    ],
  );
}

class _ScopeStrip extends ConsumerWidget {
  const _ScopeStrip({required this.scope});

  final BusinessScopeState scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) => JentraPanel(
    padding: const EdgeInsets.symmetric(
      horizontal: JentraSpacing.x4,
      vertical: JentraSpacing.x3,
    ),
    semanticsLabel: 'Current business scope',
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: context.jentraColors.infoSurface,
            borderRadius: BorderRadius.circular(JentraRadii.control),
          ),
          child: const Icon(
            Icons.corporate_fare_outlined,
            size: 18,
            color: JentraColors.navy700,
          ),
        ),
        const SizedBox(width: JentraSpacing.x3),
        Expanded(
          child: Wrap(
            spacing: JentraSpacing.x4,
            runSpacing: JentraSpacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ScopeMenu(
                label: 'Business group',
                value: scope.tenant.name,
                options: {for (final item in scope.tenants) item.id: item.name},
                onSelected: (value) => ref
                    .read(businessScopeProvider.notifier)
                    .selectTenant(value),
              ),
              _ScopeMenu(
                label: 'Legal entity',
                value: scope.legalEntity?.name ?? 'Not selected',
                options: {
                  for (final item in scope.legalEntities) item.id: item.name,
                },
                onSelected: (value) => ref
                    .read(businessScopeProvider.notifier)
                    .selectLegalEntity(value),
              ),
              _ScopeMenu(
                label: 'Branch',
                value: scope.branch?.name ?? 'Not selected',
                options: {
                  for (final item in scope.branches) item.id: item.name,
                },
                onSelected: (value) => ref
                    .read(businessScopeProvider.notifier)
                    .selectBranch(value),
              ),
            ],
          ),
        ),
        const SizedBox(width: JentraSpacing.x3),
        Text(
          scope.legalEntity?.currencyCode ?? '—',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontFamily: JentraTypography.monoFamily,
          ),
        ),
      ],
    ),
  );
}

class _ScopeMenu extends StatelessWidget {
  const _ScopeMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Switch $label',
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final option in options.entries)
        PopupMenuItem(value: option.key, child: Text(option.value)),
    ],
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.jentraColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        const SizedBox(width: JentraSpacing.x1),
        const Icon(Icons.expand_more, size: 16),
      ],
    ),
  );
}

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => JentraPanel(
    padding: const EdgeInsets.all(JentraSpacing.x2),
    semanticsLabel: 'Business setup categories',
    child: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Text(
            'DOMAINS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.jentraColors.textSecondary,
              letterSpacing: 1,
            ),
          ),
        ),
        for (final category in BusinessSetupCategory.values)
          _RailTile(
            label: category.label,
            icon: category.icon,
            selected: state.category == category,
            onTap: () => ref
                .read(businessSetupControllerProvider.notifier)
                .selectCategory(category),
          ),
      ],
    ),
  );
}

class _ResourceRail extends ConsumerWidget {
  const _ResourceRail({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = BusinessSetupResource.values.where(
      (resource) => resource.category == state.category,
    );
    return JentraPanel(
      padding: const EdgeInsets.all(JentraSpacing.x2),
      semanticsLabel: '${state.category.label} resources',
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(
              state.category.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.jentraColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Text(
              state.category.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.jentraColors.textSecondary,
              ),
            ),
          ),
          for (final resource in resources)
            _RailTile(
              label: resource.label,
              icon: resource.icon,
              selected: state.resource == resource,
              locked: !state.capabilities.contains(resource.viewPermission),
              onTap: () => ref
                  .read(businessSetupControllerProvider.notifier)
                  .selectResource(resource),
            ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Semantics(
      selected: selected,
      button: true,
      enabled: !locked,
      label: label,
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(JentraRadii.control),
        child: AnimatedContainer(
          duration: JentraMotion.fast,
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(
            horizontal: JentraSpacing.x3,
            vertical: JentraSpacing.x2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? JentraColors.green600.withValues(alpha: 0.11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(JentraRadii.control),
            border: selected
                ? const Border(
                    left: BorderSide(color: JentraColors.green600, width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: locked
                    ? context.jentraColors.textSecondary
                    : selected
                    ? JentraColors.green700
                    : context.jentraColors.textSecondary,
              ),
              const SizedBox(width: JentraSpacing.x2),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: locked ? context.jentraColors.textSecondary : null,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (locked)
                const Icon(Icons.lock_outline, size: 13)
              else if (selected)
                const Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: JentraColors.green700,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CompactResourcePicker extends ConsumerWidget {
  const _CompactResourcePicker({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => JentraPanel(
    padding: const EdgeInsets.symmetric(
      horizontal: JentraSpacing.x3,
      vertical: JentraSpacing.x2,
    ),
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<BusinessSetupCategory>(
            initialValue: state.category,
            decoration: const InputDecoration(
              labelText: 'Domain',
              isDense: true,
            ),
            items: [
              for (final category in BusinessSetupCategory.values)
                DropdownMenuItem(value: category, child: Text(category.label)),
            ],
            onChanged: (category) {
              if (category != null) {
                ref
                    .read(businessSetupControllerProvider.notifier)
                    .selectCategory(category);
              }
            },
          ),
        ),
        const SizedBox(width: JentraSpacing.x3),
        Expanded(
          child: DropdownButtonFormField<BusinessSetupResource>(
            initialValue: state.resource,
            decoration: const InputDecoration(
              labelText: 'Resource',
              isDense: true,
            ),
            items: [
              for (final resource in BusinessSetupResource.values.where(
                (item) => item.category == state.category,
              ))
                DropdownMenuItem(
                  value: resource,
                  enabled: state.capabilities.contains(resource.viewPermission),
                  child: Text(resource.label),
                ),
            ],
            onChanged: (resource) {
              if (resource != null) {
                ref
                    .read(businessSetupControllerProvider.notifier)
                    .selectResource(resource);
              }
            },
          ),
        ),
      ],
    ),
  );
}

class _ResourcePanel extends ConsumerWidget {
  const _ResourcePanel({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => JentraPanel(
    padding: EdgeInsets.zero,
    semanticsLabel: '${state.resource.label} setup list',
    child: Column(
      children: [
        _ResourceToolbar(state: state),
        Divider(height: 1, color: context.jentraColors.border),
        Expanded(child: _ResourceGrid(state: state)),
        if (state.nextCursor != null) ...[
          Divider(height: 1, color: context.jentraColors.border),
          Padding(
            padding: const EdgeInsets.all(JentraSpacing.x3),
            child: OutlinedButton.icon(
              onPressed: state.loading
                  ? null
                  : () => ref
                        .read(businessSetupControllerProvider.notifier)
                        .loadMore(),
              icon: const Icon(Icons.expand_more, size: 17),
              label: const Text('Load more'),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ResourceToolbar extends ConsumerWidget {
  const _ResourceToolbar({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = !state.resource.isReadOnly && state.canManage;
    return Padding(
      padding: const EdgeInsets.all(JentraSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: JentraColors.green600.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(JentraRadii.control),
                ),
                child: Icon(
                  state.resource.icon,
                  size: 19,
                  color: JentraColors.green700,
                ),
              ),
              const SizedBox(width: JentraSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.resource.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.resource.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.jentraColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              JentraStatusBadge(
                label: '${state.items.length} visible',
                tone: JentraStatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: JentraSpacing.x3),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: JentraSpacing.x2,
              runSpacing: JentraSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 680
                      ? constraints.maxWidth
                      : 280,
                  child: TextFormField(
                    key: const Key('setup-search'),
                    initialValue: state.search,
                    onChanged: (value) => ref
                        .read(businessSetupControllerProvider.notifier)
                        .setSearch(value),
                    decoration: const InputDecoration(
                      hintText: 'Search this list',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                _StatusFilter(state: state),
                IconButton.outlined(
                  tooltip: 'Refresh list',
                  onPressed: state.loading
                      ? null
                      : () => ref
                            .read(businessSetupControllerProvider.notifier)
                            .refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                const SizedBox(width: JentraSpacing.x1),
                OutlinedButton.icon(
                  onPressed:
                      state.resource.supportsImport &&
                          state.canManage &&
                          state.isOnline
                      ? () => _import(context, ref)
                      : null,
                  icon: const Icon(Icons.upload_file_outlined, size: 17),
                  label: const Text('Import'),
                ),
                PopupMenuButton<String>(
                  enabled:
                      state.resource.supportsExport &&
                      state.canView &&
                      state.items.isNotEmpty &&
                      state.isOnline,
                  onSelected: (format) => _export(context, ref, format),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                    PopupMenuItem(value: 'xlsx', child: Text('Export XLSX')),
                  ],
                  child: const _MenuButton(
                    icon: Icons.download_outlined,
                    label: 'Export',
                  ),
                ),
                if (canCreate)
                  JentraPrimaryButton(
                    label: 'Create ${state.resource.singularLabel}',
                    icon: Icons.add,
                    onPressed: () =>
                        state.resource == BusinessSetupResource.attachments
                        ? _attach(context, ref)
                        : _edit(context, ref),
                  ),
              ],
            ),
          ),
          if (!state.isOnline) ...[
            const SizedBox(height: JentraSpacing.x3),
            Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: JentraColors.warning,
                ),
                const SizedBox(width: JentraSpacing.x2),
                Expanded(
                  child: Text(
                    'Offline mode: cached references and encrypted drafts remain available. Imports and server commands are paused.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: JentraColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    SetupRecord? record,
  ]) async {
    final outcome = await showDialog<SetupSaveOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SetupRecordDialog(
        resource: state.resource,
        existing: record,
        online: state.isOnline,
        canManage: state.canManage,
      ),
    );
    if (outcome != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: outcome.status == SetupSaveStatus.failed
              ? JentraColors.danger
              : null,
        ),
      );
    }
  }

  Future<void> _attach(BuildContext context, WidgetRef ref) async {
    final target = await showDialog<({String type, String id})>(
      context: context,
      builder: (context) => const _AttachmentTargetDialog(),
    );
    if (target == null || !context.mounted) return;
    try {
      final file = await ref
          .read(setupFileServiceProvider)
          .openAttachmentFile();
      if (file == null || !context.mounted) return;
      final outcome = await ref
          .read(businessSetupControllerProvider.notifier)
          .uploadAttachment(
            aggregateType: target.type,
            aggregateId: target.id,
            fileName: file.name,
            mimeType: file.mimeType,
            bytes: file.bytes,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: outcome.status == SetupSaveStatus.failed
              ? JentraColors.danger
              : null,
        ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The attachment file could not be opened.'),
            backgroundColor: JentraColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    try {
      final selected = await ref
          .read(setupFileServiceProvider)
          .openImportFile();
      if (selected == null || !context.mounted) return;
      final codec = ref.read(setupTabularCodecProvider);
      final document = switch (selected.extension) {
        'csv' => codec.decodeCsv(selected.bytes),
        'xlsx' => codec.decodeXlsx(selected.bytes),
        _ => throw const TabularFileException(
          'UNSUPPORTED_FORMAT',
          'Choose a CSV or XLSX file.',
        ),
      };
      final preview = SetupImportPreview.validate(state.resource, document);
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => _ImportPreviewDialog(
          file: selected,
          document: document,
          resource: state.resource,
          preview: preview,
        ),
      );
      if (apply != true || !context.mounted) return;
      final outcome = await ref
          .read(businessSetupControllerProvider.notifier)
          .importDocument(
            format: selected.extension,
            fileName: selected.name,
            fileSize: selected.bytes.length,
            document: document,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(outcome.message)));
      }
    } on TabularFileException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: JentraColors.danger,
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The selected file could not be opened.'),
            backgroundColor: JentraColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    String format,
  ) async {
    final document = _exportDocument(state.items);
    final codec = ref.read(setupTabularCodecProvider);
    final bytes = format == 'csv'
        ? codec.encodeCsv(document)
        : codec.encodeXlsx(document, worksheetName: state.resource.label);
    final fileName =
        '${state.resource.apiView}-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.$format';
    try {
      final location = await ref
          .read(setupFileServiceProvider)
          .saveExport(
            suggestedName: fileName,
            bytes: bytes,
            mimeType: format == 'csv'
                ? 'text/csv'
                : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
      if (location == null || !context.mounted) return;
      final outcome = await ref
          .read(businessSetupControllerProvider.notifier)
          .recordExport(
            format: format,
            fileName: fileName,
            fileSize: bytes.length,
            rowCount: document.rowCount,
            columns: document.headers,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.status == SetupSaveStatus.failed
                ? 'Saved to $location, but ${outcome.message.toLowerCase()}'
                : 'Export saved to $location',
          ),
          backgroundColor: outcome.status == SetupSaveStatus.failed
              ? JentraColors.warning
              : null,
        ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The export could not be saved.'),
            backgroundColor: JentraColors.danger,
          ),
        );
      }
    }
  }

  static TabularDocument _exportDocument(List<SetupRecord> items) {
    final additional = <String>{
      for (final item in items) ...item.fields.keys,
    }.toList()..sort();
    final headers = ['code', 'name', 'status', 'version', ...additional];
    return TabularDocument(
      headers: headers,
      rows: [
        for (final item in items)
          [
            item.code,
            item.name,
            item.status,
            item.version.toString(),
            for (final key in additional) _cellText(item.fields[key]),
          ],
      ],
    );
  }

  static String _cellText(Object? value) => switch (value) {
    null => '',
    List<Object?>() || Map<String, Object?>() => jsonEncode(value),
    _ => value.toString(),
  };
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x3),
    decoration: BoxDecoration(
      border: Border.all(color: context.jentraColors.border),
      borderRadius: BorderRadius.circular(JentraRadii.control),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: JentraSpacing.x2),
        Text(label),
        const SizedBox(width: JentraSpacing.x1),
        const Icon(Icons.arrow_drop_down, size: 17),
      ],
    ),
  );
}

class _StatusFilter extends ConsumerWidget {
  const _StatusFilter({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String?>(
    tooltip: 'Filter by status',
    onSelected: (value) =>
        ref.read(businessSetupControllerProvider.notifier).setStatus(value),
    itemBuilder: (context) => [
      const PopupMenuItem(value: null, child: Text('All statuses')),
      for (final status in state.resource.filterStatuses)
        PopupMenuItem(value: status, child: Text(_titleCase(status))),
    ],
    child: _MenuButton(
      icon: Icons.filter_list,
      label: state.status == null ? 'All statuses' : _titleCase(state.status!),
    ),
  );
}

class _ResourceGrid extends ConsumerWidget {
  const _ResourceGrid({required this.state});

  final BusinessSetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error case final error?) {
      return JentraEmptyState(
        icon: error.code == 'PERMISSION_DENIED'
            ? Icons.lock_outline
            : Icons.cloud_off_outlined,
        title: error.code == 'PERMISSION_DENIED'
            ? 'Access is restricted'
            : 'Could not load ${state.resource.label.toLowerCase()}',
        description: error.message,
        action: error.retryable
            ? JentraPrimaryButton(
                label: 'Try again',
                onPressed: () => ref
                    .read(businessSetupControllerProvider.notifier)
                    .refresh(),
              )
            : null,
      );
    }
    if (state.items.isEmpty) {
      return JentraEmptyState(
        icon: state.resource.icon,
        title: state.search.isEmpty
            ? 'No ${state.resource.label.toLowerCase()} yet'
            : 'No matching records',
        description: state.search.isEmpty
            ? 'Create the first ${state.resource.singularLabel} when your role permits it.'
            : 'Try a different search phrase or remove the status filter.',
      );
    }
    return Column(
      children: [
        const _GridHeader(),
        Divider(height: 1, color: context.jentraColors.border),
        Expanded(
          child: Stack(
            children: [
              ListView.separated(
                itemCount: state.items.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: context.jentraColors.border.withValues(alpha: 0.7),
                ),
                itemBuilder: (context, index) => _SetupRow(
                  record: state.items[index],
                  canEdit:
                      state.canManage &&
                      !state.resource.isReadOnly &&
                      state.resource != BusinessSetupResource.attachments,
                  onEdit: () => _openEdit(context, ref, state.items[index]),
                  onReserve:
                      state.resource ==
                              BusinessSetupResource.documentSequences &&
                          state.canView &&
                          state.isOnline
                      ? () => _runSpecial(
                          context,
                          ref
                              .read(businessSetupControllerProvider.notifier)
                              .reserveNextNumber(state.items[index]),
                        )
                      : null,
                  onOpenAttachment:
                      state.resource == BusinessSetupResource.attachments &&
                          state.items[index].status == 'ready' &&
                          state.canView &&
                          state.isOnline
                      ? () => _openAttachment(context, ref, state.items[index])
                      : null,
                  onMarkRead:
                      state.resource == BusinessSetupResource.notifications &&
                          state.items[index].status == 'unread' &&
                          state.isOnline
                      ? () => _runSpecial(
                          context,
                          ref
                              .read(businessSetupControllerProvider.notifier)
                              .markNotificationRead(state.items[index]),
                        )
                      : null,
                ),
              ),
              if (state.loading)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    SetupRecord record,
  ) async {
    final outcome = await showDialog<SetupSaveOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SetupRecordDialog(
        resource: state.resource,
        existing: record,
        online: state.isOnline,
        canManage: state.canManage,
      ),
    );
    if (outcome != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(outcome.message)));
    }
  }

  Future<void> _runSpecial(
    BuildContext context,
    Future<SetupSaveOutcome> operation,
  ) async {
    final outcome = await operation;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.message),
        backgroundColor: outcome.status == SetupSaveStatus.failed
            ? JentraColors.danger
            : null,
      ),
    );
  }

  Future<void> _openAttachment(
    BuildContext context,
    WidgetRef ref,
    SetupRecord attachment,
  ) async {
    try {
      final url = await ref
          .read(businessSetupControllerProvider.notifier)
          .createAttachmentReadUrl(attachment);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Private attachment link'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This signed link expires in 15 minutes. Share it only with an authorized Jentra user.',
                ),
                const SizedBox(height: JentraSpacing.x3),
                SelectableText(url),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.copy_outlined, size: 17),
              label: const Text('Copy signed link'),
            ),
          ],
        ),
      );
    } on DomainError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: JentraColors.danger,
        ),
      );
    }
  }
}

class _GridHeader extends StatelessWidget {
  const _GridHeader();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 34),
    color: context.jentraColors.panelElevated,
    padding: const EdgeInsets.symmetric(
      horizontal: JentraSpacing.x4,
      vertical: JentraSpacing.x1,
    ),
    child: Row(
      children: [
        const SizedBox(width: 110, child: _GridLabel('CODE')),
        const Expanded(flex: 3, child: _GridLabel('NAME')),
        const Expanded(flex: 2, child: _GridLabel('DETAIL')),
        const SizedBox(width: 94, child: _GridLabel('STATUS')),
        const SizedBox(width: 96, child: _GridLabel('UPDATED')),
        const SizedBox(width: 36),
      ],
    ),
  );
}

class _GridLabel extends StatelessWidget {
  const _GridLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.jentraColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.record,
    required this.canEdit,
    required this.onEdit,
    this.onReserve,
    this.onMarkRead,
    this.onOpenAttachment,
  });

  final SetupRecord record;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onReserve;
  final VoidCallback? onMarkRead;
  final VoidCallback? onOpenAttachment;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '${record.code}, ${record.name}, status ${record.status}',
    child: InkWell(
      onTap: () => _showDetails(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x4),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  record.code.isEmpty ? '—' : record.code,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: JentraTypography.monoFamily,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  record.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.jentraColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: 94,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: JentraStatusBadge(
                    label: _titleCase(record.status),
                    tone: record.statusTone,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  DateFormat('dd MMM yy').format(record.updatedAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.jentraColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: PopupMenuButton<String>(
                  tooltip: 'Actions for ${record.name}',
                  onSelected: (action) {
                    switch (action) {
                      case 'view':
                        _showDetails(context);
                      case 'edit':
                        onEdit();
                      case 'reserve':
                        onReserve?.call();
                      case 'read':
                        onMarkRead?.call();
                      case 'open_attachment':
                        onOpenAttachment?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'view',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.visibility_outlined, size: 18),
                        title: Text('View details'),
                      ),
                    ),
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined, size: 18),
                          title: Text('Edit'),
                        ),
                      ),
                    if (onReserve != null)
                      const PopupMenuItem(
                        value: 'reserve',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.numbers_outlined, size: 18),
                          title: Text('Reserve next number'),
                        ),
                      ),
                    if (onMarkRead != null)
                      const PopupMenuItem(
                        value: 'read',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.mark_email_read_outlined,
                            size: 18,
                          ),
                          title: Text('Mark as read'),
                        ),
                      ),
                    if (onOpenAttachment != null)
                      const PopupMenuItem(
                        value: 'open_attachment',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.lock_open_outlined, size: 18),
                          title: Text('Open signed link'),
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.more_horiz, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record.name),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Code', value: record.code),
                _DetailRow(label: 'Status', value: record.status),
                _DetailRow(label: 'Version', value: '${record.version}'),
                for (final entry in record.fields.entries)
                  _DetailRow(
                    label: _titleCase(entry.key.replaceAll('_', ' ')),
                    value: _ResourceToolbar._cellText(entry.value),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: JentraSpacing.x3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: SelectableText(
            value.isEmpty ? '—' : value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class SetupRecordDialog extends ConsumerStatefulWidget {
  const SetupRecordDialog({
    required this.resource,
    required this.online,
    required this.canManage,
    this.existing,
    super.key,
  });

  final BusinessSetupResource resource;
  final SetupRecord? existing;
  final bool online;
  final bool canManage;

  @override
  ConsumerState<SetupRecordDialog> createState() => _SetupRecordDialogState();
}

class _SetupRecordDialogState extends ConsumerState<SetupRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _errors = <String, String>{};
  late SetupRecord? _saveExisting;
  SetupRecord? _conflictServer;
  String? _conflictMessage;
  String? _mergeNotice;
  late String _status;
  var _saving = false;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _saveExisting = widget.existing;
    _status =
        widget.existing?.status ??
        (widget.resource == BusinessSetupResource.workflowDefinitions
            ? 'draft'
            : 'active');
    final values = <String, Object?>{
      if (widget.resource == BusinessSetupResource.warehouses)
        'branch_id': ref.read(businessScopeProvider).value?.branchId,
      ...?widget.existing?.toJson(),
      ...?widget.existing?.fields,
    };
    for (final field in widget.resource.fields) {
      final initial = _initialValue(field, values[field.name]);
      _controllers[field.name] = TextEditingController(text: initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noun = widget.resource.singularLabel;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) unawaited(_requestClose());
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: JentraColors.green600.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          JentraRadii.control,
                        ),
                      ),
                      child: Icon(
                        widget.resource.icon,
                        color: JentraColors.green700,
                      ),
                    ),
                    const SizedBox(width: JentraSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existing == null
                                ? 'New $noun'
                                : 'Edit $noun',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            widget.online
                                ? 'Draft locally or confirm this version with the server.'
                                : 'Offline: only an encrypted local draft can be saved.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.jentraColors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving ? null : _requestClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.jentraColors.border),
              if (_conflictMessage != null)
                _ConflictNotice(
                  message: _conflictMessage!,
                  localVersion: widget.existing?.version,
                  serverVersion: _conflictServer?.version,
                  canMerge: _conflictServer != null,
                  onReload: _reloadServer,
                  onMerge: _prepareMerge,
                )
              else if (_mergeNotice != null)
                _MergeNotice(message: _mergeNotice!),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(JentraSpacing.x6),
                  child: Form(
                    key: _formKey,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        return Wrap(
                          spacing: JentraSpacing.x4,
                          runSpacing: JentraSpacing.x4,
                          children: [
                            for (final field in widget.resource.fields)
                              SizedBox(
                                width: field.wide ? width : (width - 16) / 2,
                                child: _buildField(field),
                              ),
                            SizedBox(
                              width: (width - 16) / 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: _status,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                ),
                                items: [
                                  if (widget.resource ==
                                      BusinessSetupResource.workflowDefinitions)
                                    const DropdownMenuItem(
                                      value: 'draft',
                                      child: Text('Draft'),
                                    ),
                                  const DropdownMenuItem(
                                    value: 'active',
                                    child: Text('Active'),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'inactive',
                                    child: Text('Inactive'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _status = value;
                                    _dirty = true;
                                    _errors.remove('status');
                                  });
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: context.jentraColors.border),
              Padding(
                padding: const EdgeInsets.all(JentraSpacing.x4),
                child: Row(
                  children: [
                    if (_saveExisting != null)
                      Text(
                        'Version ${_saveExisting!.version}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: context.jentraColors.textSecondary,
                              fontFamily: JentraTypography.monoFamily,
                            ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : _requestClose,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: JentraSpacing.x2),
                    OutlinedButton(
                      onPressed: _saving ? null : () => _submit(online: false),
                      child: const Text('Save draft'),
                    ),
                    const SizedBox(width: JentraSpacing.x2),
                    JentraPrimaryButton(
                      label: 'Save to server',
                      loading: _saving,
                      onPressed: !_saving && widget.online && widget.canManage
                          ? () => _submit(online: true)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(_SetupField field) {
    final controller = _controllers[field.name]!;
    if (widget.resource == BusinessSetupResource.warehouses &&
        field.name == 'branch_id') {
      final scope = ref.watch(businessScopeProvider).value;
      final branches = scope?.branches ?? const <BranchSummary>[];
      final selected = branches.any((b) => b.id == controller.text)
          ? controller.text
          : null;
      return DropdownButtonFormField<String>(
        key: field.key,
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Branch',
          errorText: _errors[field.name],
        ),
        items: [
          for (final branch in branches)
            DropdownMenuItem(
              value: branch.id,
              child: Text('${branch.code} · ${branch.name}'),
            ),
        ],
        onChanged: widget.existing != null
            ? null
            : (value) => setState(() {
                controller.text = value ?? '';
                _dirty = true;
                _errors.remove(field.name);
              }),
      );
    }
    if (field.options case final options?) {
      final current = options.contains(controller.text)
          ? controller.text
          : options.first;
      controller.text = current;
      return DropdownButtonFormField<String>(
        initialValue: current,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.helper,
          errorText: _errors[field.name],
        ),
        items: [
          for (final value in options)
            DropdownMenuItem(value: value, child: Text(_titleCase(value))),
        ],
        onChanged: (value) {
          setState(() {
            controller.text = value ?? '';
            _dirty = true;
            _errors.remove(field.name);
          });
        },
      );
    }
    return TextFormField(
      key: field.key,
      controller: controller,
      autofocus: field.autofocus,
      minLines: field.multiline ? 3 : 1,
      maxLines: field.multiline ? 5 : 1,
      keyboardType: field.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.helper,
        errorText: _errors[field.name],
      ),
      onChanged: (_) {
        setState(() {
          _dirty = true;
          _errors.remove(field.name);
        });
      },
    );
  }

  Future<void> _submit({required bool online}) async {
    FocusScope.of(context).unfocus();
    final payload = _payload();
    final validation = BusinessSetupValidator.validate(
      widget.resource,
      payload,
    );
    if (online && !validation.isValid) {
      setState(() {
        _errors
          ..clear()
          ..addEntries(
            validation.issues.map(
              (issue) => MapEntry(issue.field, issue.message),
            ),
          );
      });
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(businessSetupControllerProvider.notifier);
    final outcome = online
        ? await controller.saveOnline(
            resource: widget.resource,
            payload: payload,
            existing: _saveExisting,
          )
        : await controller.saveDraft(
            resource: widget.resource,
            payload: payload,
            existing: _saveExisting,
          );
    if (!mounted) return;
    if (outcome.error?.code == 'VERSION_CONFLICT') {
      setState(() {
        _saving = false;
        _conflictServer = outcome.serverRecord;
        _conflictMessage = outcome.message;
        _mergeNotice = null;
      });
      return;
    }
    if (outcome.error?.fieldDetails.isNotEmpty ?? false) {
      setState(() {
        _saving = false;
        _errors
          ..clear()
          ..addAll(outcome.error!.fieldDetails);
      });
      return;
    }
    _dirty = false;
    Navigator.pop(context, outcome);
  }

  Map<String, Object?> _payload() {
    final payload = <String, Object?>{
      if (_saveExisting != null) 'id': _saveExisting!.id,
      for (final field in widget.resource.fields)
        field.name: _typedValue(field, _controllers[field.name]!.text),
      'status': _status,
    };
    return payload;
  }

  Future<void> _requestClose() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'Your current field edits have not been saved as an encrypted draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      Navigator.pop(context);
    }
  }

  Future<void> _reloadServer() async {
    await ref.read(businessSetupControllerProvider.notifier).refresh();
    if (!mounted) return;
    _dirty = false;
    Navigator.pop(
      context,
      const SetupSaveOutcome(
        SetupSaveStatus.draftSaved,
        'Server data reloaded. The conflicted encrypted draft remains on this device.',
      ),
    );
  }

  void _prepareMerge() {
    final server = _conflictServer;
    if (server == null) return;
    setState(() {
      _saveExisting = server;
      _conflictServer = null;
      _conflictMessage = null;
      _mergeNotice =
          'Manual merge prepared against server version ${server.version}. Review every field, then save again.';
      _dirty = true;
    });
  }

  static Object? _typedValue(_SetupField field, String source) {
    final value = source.trim();
    if (field.optional && value.isEmpty) return null;
    if (field.integer) return int.tryParse(value);
    if (field.list) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (field.json) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
    if (field.boolean) return value == 'true';
    return value;
  }

  static String _initialValue(_SetupField field, Object? value) {
    if (value is List) return value.join(', ');
    if (value is Map) return jsonEncode(value);
    if (value != null) return value.toString();
    return field.defaultValue ?? field.options?.first ?? '';
  }
}

class _ConflictNotice extends StatelessWidget {
  const _ConflictNotice({
    required this.message,
    required this.localVersion,
    required this.serverVersion,
    required this.canMerge,
    required this.onReload,
    required this.onMerge,
  });

  final String message;
  final int? localVersion;
  final int? serverVersion;
  final bool canMerge;
  final VoidCallback onReload;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: context.jentraColors.warningSurface,
    padding: const EdgeInsets.all(JentraSpacing.x4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.merge_type_outlined,
              color: JentraColors.warning,
              size: 20,
            ),
            const SizedBox(width: JentraSpacing.x2),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: JentraSpacing.x2),
        Text(
          'Draft version ${localVersion ?? 'unknown'} · Server version ${serverVersion ?? 'unavailable'}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontFamily: JentraTypography.monoFamily,
          ),
        ),
        const SizedBox(height: JentraSpacing.x3),
        Wrap(
          spacing: JentraSpacing.x2,
          runSpacing: JentraSpacing.x2,
          children: [
            OutlinedButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Reload server data'),
            ),
            FilledButton.icon(
              onPressed: canMerge ? onMerge : null,
              icon: const Icon(Icons.call_merge_outlined, size: 17),
              label: const Text('Merge my draft'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MergeNotice extends StatelessWidget {
  const _MergeNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: context.jentraColors.infoSurface,
    padding: const EdgeInsets.all(JentraSpacing.x4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: JentraColors.navy700, size: 20),
        const SizedBox(width: JentraSpacing.x2),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({
    required this.file,
    required this.document,
    required this.resource,
    required this.preview,
  });

  final SelectedSetupFile file;
  final TabularDocument document;
  final BusinessSetupResource resource;
  final SetupImportPreview preview;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Review ${resource.singularLabel} import'),
    content: SizedBox(
      width: 760,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: JentraSpacing.x2,
            runSpacing: JentraSpacing.x2,
            children: [
              JentraStatusBadge(
                label: '${document.rowCount} rows',
                tone: JentraStatusTone.info,
              ),
              JentraStatusBadge(
                label: '${document.columnCount} columns',
                tone: JentraStatusTone.neutral,
              ),
              JentraStatusBadge(
                label: file.extension.toUpperCase(),
                tone: JentraStatusTone.success,
              ),
              JentraStatusBadge(
                label: preview.isValid
                    ? 'Field validation passed'
                    : '${preview.invalidRowCount} invalid rows',
                tone: preview.isValid
                    ? JentraStatusTone.success
                    : JentraStatusTone.danger,
              ),
            ],
          ),
          const SizedBox(height: JentraSpacing.x4),
          Text(file.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: JentraSpacing.x3),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: context.jentraColors.border),
              borderRadius: BorderRadius.circular(JentraRadii.control),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: [
                    for (final header in document.headers)
                      DataColumn(label: Text(_titleCase(header))),
                  ],
                  rows: [
                    for (final row in document.rows.take(5))
                      DataRow(
                        cells: [for (final value in row) DataCell(Text(value))],
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (preview.issues.isNotEmpty) ...[
            const SizedBox(height: JentraSpacing.x3),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              width: double.infinity,
              padding: const EdgeInsets.all(JentraSpacing.x3),
              decoration: BoxDecoration(
                color: context.jentraColors.dangerSurface,
                borderRadius: BorderRadius.circular(JentraRadii.control),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fix these fields before applying',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: JentraSpacing.x2),
                    for (final issue in preview.issues.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Row ${issue.row} · ${issue.field}: ${issue.message}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (preview.issues.length > 20)
                      Text(
                        '${preview.issues.length - 20} more issues not shown.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: JentraSpacing.x3),
          Text(
            'Local field checks run before apply. The server then validates permissions and references and applies the file atomically; any rejected row rolls back the full import.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.jentraColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: !preview.isValid ? null : () => Navigator.pop(context, true),
        icon: const Icon(Icons.verified_outlined, size: 17),
        label: const Text('Apply import'),
      ),
    ],
  );
}

class _AttachmentTargetDialog extends StatefulWidget {
  const _AttachmentTargetDialog();

  @override
  State<_AttachmentTargetDialog> createState() =>
      _AttachmentTargetDialogState();
}

class _AttachmentTargetDialogState extends State<_AttachmentTargetDialog> {
  final _type = TextEditingController();
  final _id = TextEditingController();
  String? _typeError;
  String? _idError;

  @override
  void dispose() {
    _type.dispose();
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Attach a business file'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _type,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Record type',
              hintText: 'for example, party',
              errorText: _typeError,
            ),
          ),
          const SizedBox(height: JentraSpacing.x4),
          TextField(
            controller: _id,
            decoration: InputDecoration(
              labelText: 'Record ID',
              hintText: 'UUID of the related record',
              errorText: _idError,
            ),
          ),
          const SizedBox(height: JentraSpacing.x4),
          Text(
            'PDF, PNG, JPEG, CSV, or XLSX · maximum 25 MiB. The file stays private and is confirmed only after upload succeeds.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.jentraColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _continue,
        icon: const Icon(Icons.folder_open_outlined, size: 17),
        label: const Text('Choose file'),
      ),
    ],
  );

  void _continue() {
    final type = _type.text.trim();
    final id = _id.text.trim();
    final typeValid = RegExp(r'^[a-z][a-z0-9_.-]{1,79}$').hasMatch(type);
    final idValid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(id);
    if (!typeValid || !idValid) {
      setState(() {
        _typeError = typeValid ? null : 'Use a safe lower-case record type.';
        _idError = idValid ? null : 'Enter a valid record UUID.';
      });
      return;
    }
    Navigator.pop(context, (type: type, id: id));
  }
}

final class _SetupField {
  const _SetupField(
    this.name,
    this.label, {
    this.key,
    this.helper,
    this.options,
    this.defaultValue,
    this.wide = false,
    this.multiline = false,
    this.numeric = false,
    this.integer = false,
    this.boolean = false,
    this.list = false,
    this.json = false,
    this.optional = false,
    this.autofocus = false,
  });

  final String name;
  final String label;
  final Key? key;
  final String? helper;
  final List<String>? options;
  final String? defaultValue;
  final bool wide;
  final bool multiline;
  final bool numeric;
  final bool integer;
  final bool boolean;
  final bool list;
  final bool json;
  final bool optional;
  final bool autofocus;
}

extension on BusinessSetupCategory {
  String get label => switch (this) {
    BusinessSetupCategory.finance => 'Finance',
    BusinessSetupCategory.parties => 'Parties',
    BusinessSetupCategory.catalogue => 'Catalogue',
    BusinessSetupCategory.governance => 'Governance',
    BusinessSetupCategory.filesAndData => 'Files & data',
    BusinessSetupCategory.reports => 'Reports',
  };

  String get description => switch (this) {
    BusinessSetupCategory.finance => 'Books, periods, currency and tax.',
    BusinessSetupCategory.parties => 'Customers, suppliers and contacts.',
    BusinessSetupCategory.catalogue => 'Products and measurement rules.',
    BusinessSetupCategory.governance => 'Numbering, workflow and approvals.',
    BusinessSetupCategory.filesAndData => 'Documents, notices and data jobs.',
    BusinessSetupCategory.reports => 'Reusable, permission-aware views.',
  };

  IconData get icon => switch (this) {
    BusinessSetupCategory.finance => Icons.account_balance_outlined,
    BusinessSetupCategory.parties => Icons.groups_outlined,
    BusinessSetupCategory.catalogue => Icons.inventory_2_outlined,
    BusinessSetupCategory.governance => Icons.policy_outlined,
    BusinessSetupCategory.filesAndData => Icons.folder_copy_outlined,
    BusinessSetupCategory.reports => Icons.query_stats_outlined,
  };
}

extension on BusinessSetupResource {
  IconData get icon => switch (this) {
    BusinessSetupResource.currencies => Icons.currency_exchange,
    BusinessSetupResource.exchangeRates => Icons.swap_horiz,
    BusinessSetupResource.taxDefinitions => Icons.percent,
    BusinessSetupResource.accounts => Icons.account_tree_outlined,
    BusinessSetupResource.fiscalPeriods => Icons.calendar_month_outlined,
    BusinessSetupResource.parties => Icons.domain_outlined,
    BusinessSetupResource.contacts => Icons.contact_page_outlined,
    BusinessSetupResource.units => Icons.straighten_outlined,
    BusinessSetupResource.products => Icons.inventory_2_outlined,
    BusinessSetupResource.warehouses => Icons.warehouse_outlined,
    BusinessSetupResource.documentSequences => Icons.numbers_outlined,
    BusinessSetupResource.workflowDefinitions => Icons.account_tree,
    BusinessSetupResource.approvalMatrixSteps => Icons.approval_outlined,
    BusinessSetupResource.attachments => Icons.attach_file,
    BusinessSetupResource.notifications => Icons.notifications_none,
    BusinessSetupResource.importJobs => Icons.upload_file_outlined,
    BusinessSetupResource.exportJobs => Icons.download_outlined,
    BusinessSetupResource.reportDefinitions => Icons.table_chart_outlined,
  };

  String get description => switch (this) {
    BusinessSetupResource.warehouses =>
      'Scoped stock locations for the selected business and branch.',
    BusinessSetupResource.currencies =>
      'ISO reference currencies and precision.',
    BusinessSetupResource.exchangeRates =>
      'Dated direct rates for legal-entity books.',
    BusinessSetupResource.taxDefinitions =>
      'Versioned tax treatments and effective dates.',
    BusinessSetupResource.accounts =>
      'Posting structure for the immutable ledger.',
    BusinessSetupResource.fiscalPeriods =>
      'Open and locked accounting windows.',
    BusinessSetupResource.parties =>
      'Canonical customer and supplier identities.',
    BusinessSetupResource.contacts =>
      'People and channels linked to each party.',
    BusinessSetupResource.units =>
      'Measurement categories, symbols and precision.',
    BusinessSetupResource.products =>
      'Stocked, non-stock and service catalogue.',
    BusinessSetupResource.documentSequences =>
      'Atomic document-number policies.',
    BusinessSetupResource.workflowDefinitions =>
      'Versioned business lifecycles.',
    BusinessSetupResource.approvalMatrixSteps =>
      'Ordered role and value thresholds.',
    BusinessSetupResource.attachments =>
      'Private business files and upload state.',
    BusinessSetupResource.notifications => 'Your actionable operating notices.',
    BusinessSetupResource.importJobs => 'Atomic setup-data import history.',
    BusinessSetupResource.exportJobs => 'Auditable setup-data export history.',
    BusinessSetupResource.reportDefinitions =>
      'Safe reusable reporting contracts.',
  };

  bool get supportsImport => switch (this) {
    BusinessSetupResource.exchangeRates ||
    BusinessSetupResource.taxDefinitions ||
    BusinessSetupResource.accounts ||
    BusinessSetupResource.fiscalPeriods ||
    BusinessSetupResource.parties ||
    BusinessSetupResource.contacts ||
    BusinessSetupResource.units ||
    BusinessSetupResource.products => true,
    _ => false,
  };

  bool get supportsExport => switch (this) {
    BusinessSetupResource.exchangeRates ||
    BusinessSetupResource.taxDefinitions ||
    BusinessSetupResource.accounts ||
    BusinessSetupResource.fiscalPeriods ||
    BusinessSetupResource.parties ||
    BusinessSetupResource.contacts ||
    BusinessSetupResource.units ||
    BusinessSetupResource.products ||
    BusinessSetupResource.documentSequences ||
    BusinessSetupResource.workflowDefinitions ||
    BusinessSetupResource.approvalMatrixSteps ||
    BusinessSetupResource.reportDefinitions => true,
    _ => false,
  };

  List<String> get filterStatuses => switch (this) {
    BusinessSetupResource.workflowDefinitions => const [
      'draft',
      'active',
      'inactive',
    ],
    BusinessSetupResource.attachments => const ['staged', 'ready', 'rejected'],
    BusinessSetupResource.notifications => const ['unread', 'read'],
    BusinessSetupResource.importJobs ||
    BusinessSetupResource.exportJobs => const ['completed', 'failed'],
    _ => const ['active', 'inactive'],
  };

  List<_SetupField> get fields => switch (this) {
    BusinessSetupResource.warehouses => const [
      _SetupField('code', 'Warehouse code', autofocus: true),
      _SetupField('name', 'Warehouse name'),
      _SetupField('branch_id', 'Branch', wide: true),
    ],
    BusinessSetupResource.exchangeRates => const [
      _SetupField('source_currency_code', 'Source currency', autofocus: true),
      _SetupField('target_currency_code', 'Target currency'),
      _SetupField('rate', 'Direct rate', numeric: true),
      _SetupField('effective_date', 'Effective date', helper: 'YYYY-MM-DD'),
      _SetupField(
        'rate_type',
        'Rate type',
        options: ['spot', 'average', 'closing', 'custom'],
      ),
      _SetupField('source', 'Source', defaultValue: 'manual'),
    ],
    BusinessSetupResource.taxDefinitions => const [
      _SetupField(
        'code',
        'Tax code',
        key: Key('setup-code-field'),
        autofocus: true,
      ),
      _SetupField('name', 'Name', key: Key('setup-name-field')),
      _SetupField('rate', 'Rate %', numeric: true),
      _SetupField(
        'kind',
        'Kind',
        options: ['input', 'output', 'withholding', 'zero', 'exempt'],
      ),
      _SetupField(
        'inclusive',
        'Prices include tax',
        options: ['false', 'true'],
        defaultValue: 'false',
        boolean: true,
      ),
      _SetupField(
        'recoverable',
        'Tax is recoverable',
        options: ['false', 'true'],
        defaultValue: 'false',
        boolean: true,
      ),
      _SetupField('valid_from', 'Valid from', helper: 'YYYY-MM-DD'),
      _SetupField('valid_to', 'Valid to', helper: 'YYYY-MM-DD', optional: true),
    ],
    BusinessSetupResource.accounts => const [
      _SetupField(
        'code',
        'Account code',
        key: Key('setup-code-field'),
        autofocus: true,
      ),
      _SetupField('name', 'Account name', key: Key('setup-name-field')),
      _SetupField(
        'account_type',
        'Account type',
        options: ['asset', 'liability', 'equity', 'revenue', 'expense'],
      ),
      _SetupField(
        'normal_balance',
        'Normal balance',
        options: ['debit', 'credit'],
      ),
      _SetupField('parent_id', 'Parent account ID', optional: true, wide: true),
      _SetupField('currency_code', 'Currency', optional: true),
      _SetupField(
        'is_posting',
        'Allow posting',
        options: ['true', 'false'],
        defaultValue: 'true',
        boolean: true,
      ),
    ],
    BusinessSetupResource.fiscalPeriods => const [
      _SetupField('name', 'Period name', autofocus: true, wide: true),
      _SetupField('start_date', 'Start date', helper: 'YYYY-MM-DD'),
      _SetupField('end_date', 'End date', helper: 'YYYY-MM-DD'),
      _SetupField(
        'state',
        'State',
        options: ['open', 'soft_locked', 'hard_locked'],
      ),
    ],
    BusinessSetupResource.parties => const [
      _SetupField('code', 'Party code', autofocus: true),
      _SetupField(
        'kind',
        'Party type',
        options: ['customer', 'supplier', 'both'],
      ),
      _SetupField('legal_name', 'Legal name', wide: true),
      _SetupField('display_name', 'Display name', wide: true),
      _SetupField('tax_identifier', 'Tax identifier', optional: true),
      _SetupField('email', 'Email', optional: true),
      _SetupField('phone', 'Phone', optional: true),
      _SetupField(
        'address_line_1',
        'Address line 1',
        optional: true,
        wide: true,
      ),
      _SetupField(
        'address_line_2',
        'Address line 2',
        optional: true,
        wide: true,
      ),
      _SetupField('city', 'City', optional: true),
      _SetupField('country_code', 'Country', defaultValue: 'LK'),
      _SetupField(
        'credit_limit',
        'Credit limit',
        defaultValue: '0.000000',
        numeric: true,
      ),
      _SetupField(
        'credit_currency_code',
        'Credit currency',
        defaultValue: 'LKR',
      ),
      _SetupField(
        'payment_terms_days',
        'Payment terms (days)',
        defaultValue: '0',
        integer: true,
        numeric: true,
      ),
    ],
    BusinessSetupResource.contacts => const [
      _SetupField('party_id', 'Party ID', wide: true),
      _SetupField('name', 'Contact name', autofocus: true, wide: true),
      _SetupField('role', 'Role', optional: true),
      _SetupField('email', 'Email', optional: true),
      _SetupField('phone', 'Phone', optional: true),
      _SetupField(
        'is_primary',
        'Primary contact',
        options: ['false', 'true'],
        boolean: true,
      ),
    ],
    BusinessSetupResource.units => const [
      _SetupField('code', 'Unit code', autofocus: true),
      _SetupField('name', 'Unit name'),
      _SetupField('symbol', 'Symbol'),
      _SetupField(
        'category',
        'Measurement category',
        options: [
          'quantity',
          'weight',
          'length',
          'area',
          'volume',
          'time',
          'service',
        ],
      ),
      _SetupField(
        'precision',
        'Decimal precision',
        defaultValue: '0',
        integer: true,
        numeric: true,
      ),
    ],
    BusinessSetupResource.products => const [
      _SetupField('sku', 'SKU', autofocus: true),
      _SetupField('name', 'Product name'),
      _SetupField(
        'kind',
        'Kind',
        options: ['stocked', 'non_stocked', 'service'],
      ),
      _SetupField('base_unit_id', 'Base unit ID'),
      _SetupField(
        'tracking_mode',
        'Tracking',
        options: ['none', 'lot', 'serial'],
      ),
      _SetupField('description', 'Description', optional: true, wide: true),
      _SetupField(
        'can_sell',
        'Can sell',
        options: ['true', 'false'],
        defaultValue: 'true',
        boolean: true,
      ),
      _SetupField(
        'can_purchase',
        'Can purchase',
        options: ['true', 'false'],
        defaultValue: 'true',
        boolean: true,
      ),
      _SetupField('tax_definition_id', 'Tax definition ID', optional: true),
      _SetupField('revenue_account_id', 'Revenue account ID', optional: true),
      _SetupField('expense_account_id', 'Expense account ID', optional: true),
      _SetupField(
        'inventory_account_id',
        'Inventory account ID',
        optional: true,
      ),
      _SetupField('cogs_account_id', 'COGS account ID', optional: true),
    ],
    BusinessSetupResource.documentSequences => const [
      _SetupField(
        'document_type',
        'Document type',
        autofocus: true,
        wide: true,
      ),
      _SetupField('prefix', 'Prefix', optional: true),
      _SetupField('suffix', 'Suffix', optional: true),
      _SetupField(
        'padding',
        'Number padding',
        defaultValue: '5',
        integer: true,
        numeric: true,
      ),
      _SetupField(
        'reset_policy',
        'Reset policy',
        options: ['never', 'yearly', 'monthly'],
      ),
      _SetupField(
        'next_value',
        'Next number',
        defaultValue: '1',
        integer: true,
        numeric: true,
      ),
    ],
    BusinessSetupResource.workflowDefinitions => const [
      _SetupField('document_type', 'Document type', autofocus: true),
      _SetupField('name', 'Workflow name'),
      _SetupField(
        'revision',
        'Revision',
        defaultValue: '1',
        integer: true,
        numeric: true,
      ),
      _SetupField(
        'lifecycle',
        'Lifecycle contract',
        helper: 'JSON states and transition pairs',
        wide: true,
        multiline: true,
        json: true,
        defaultValue:
            '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["draft","cancelled"],["submitted","approved"],["submitted","rejected"],["submitted","cancelled"],["rejected","draft"],["rejected","cancelled"],["approved","posted"],["approved","cancelled"],["posted","settled"],["posted","fulfilled"],["posted","closed"],["posted","reversed"],["settled","closed"],["fulfilled","closed"]]}',
      ),
    ],
    BusinessSetupResource.approvalMatrixSteps => const [
      _SetupField('workflow_definition_id', 'Workflow ID', wide: true),
      _SetupField('role_id', 'Approver role ID', wide: true),
      _SetupField(
        'step_order',
        'Step order',
        defaultValue: '1',
        integer: true,
        numeric: true,
      ),
      _SetupField('currency_code', 'Currency', defaultValue: 'LKR'),
      _SetupField(
        'minimum_amount',
        'Minimum amount',
        numeric: true,
        optional: true,
      ),
      _SetupField(
        'maximum_amount',
        'Maximum amount',
        numeric: true,
        optional: true,
      ),
    ],
    BusinessSetupResource.attachments => const [
      _SetupField('aggregate_type', 'Record type', autofocus: true),
      _SetupField('aggregate_id', 'Record ID'),
      _SetupField('file_name', 'File name', wide: true),
      _SetupField('mime_type', 'MIME type', wide: true),
      _SetupField('byte_size', 'File size', integer: true, numeric: true),
    ],
    BusinessSetupResource.reportDefinitions => const [
      _SetupField('code', 'Report code', autofocus: true),
      _SetupField('title', 'Report title'),
      _SetupField('source_view', 'API source view', wide: true),
      _SetupField(
        'columns',
        'Columns',
        helper: 'Comma-separated allowlisted fields',
        wide: true,
        list: true,
      ),
      _SetupField(
        'filters',
        'Filters',
        helper: 'JSON object with allowlisted fields',
        defaultValue: '{}',
        wide: true,
        multiline: true,
        json: true,
      ),
      _SetupField(
        'sort',
        'Sort fields',
        helper: 'Comma-separated allowlisted fields',
        wide: true,
        list: true,
      ),
      _SetupField(
        'row_limit',
        'Row limit',
        defaultValue: '100',
        integer: true,
        numeric: true,
      ),
      _SetupField(
        'is_shared',
        'Share with permitted users',
        options: ['false', 'true'],
        defaultValue: 'false',
        boolean: true,
      ),
    ],
    _ => const [],
  };
}

extension on SetupRecord {
  String get detail {
    const preferred = [
      'account_type',
      'kind',
      'rate',
      'state',
      'symbol',
      'tracking_mode',
      'document_type',
      'source_view',
      'role',
      'format',
      'mime_type',
    ];
    for (final key in preferred) {
      final value = fields[key];
      if (value != null && value.toString().isNotEmpty) {
        return _titleCase(value.toString().replaceAll('_', ' '));
      }
    }
    return 'Version $version';
  }

  JentraStatusTone get statusTone => switch (status) {
    'active' || 'ready' || 'completed' || 'open' => JentraStatusTone.success,
    'draft' ||
    'unread' ||
    'pending' ||
    'soft_locked' => JentraStatusTone.warning,
    'failed' || 'hard_locked' => JentraStatusTone.danger,
    _ => JentraStatusTone.neutral,
  };
}

String _titleCase(String value) => value
    .split(RegExp(r'[ _]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
