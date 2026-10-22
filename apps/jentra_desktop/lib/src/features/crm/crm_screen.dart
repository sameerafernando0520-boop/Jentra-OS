import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'crm_controller.dart';

class CrmScreen extends ConsumerWidget {
  const CrmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(businessCapabilitiesProvider);
    return capabilities.when(
      loading: _CrmLoading.new,
      error: (error, _) => _CrmError(
        error: error,
        onRetry: () => ref.invalidate(businessCapabilitiesProvider),
      ),
      data: (value) {
        if (!_canViewCrm(value)) {
          return const Padding(
            padding: EdgeInsets.all(JentraSpacing.x5),
            child: JentraPanel(
              child: JentraEmptyState(
                icon: Icons.lock_outline,
                title: 'Access is restricted',
                description: 'Your role does not include permission to view CRM records.',
              ),
            ),
          );
        }
        return const _AuthorizedCrm();
      },
    );
  }

  static bool _canViewCrm(Set<String> capabilities) => const {
    'crm.leads.view',
    'crm.leads.manage',
    'crm.opportunities.view',
    'crm.opportunities.manage',
  }.any(capabilities.contains);
}

class _AuthorizedCrm extends ConsumerWidget {
  const _AuthorizedCrm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crm = ref.watch(crmControllerProvider);
    return crm.when(
      loading: _CrmLoading.new,
      error: (error, _) => _CrmError(
        error: error,
        onRetry: () => ref.invalidate(crmControllerProvider),
      ),
      data: (state) => _CrmWorkspace(state: state),
    );
  }
}

class _CrmLoading extends StatelessWidget {
  const _CrmLoading();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading CRM pipeline',
    excludeSemantics: true,
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _CrmError extends StatelessWidget {
  const _CrmError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(JentraSpacing.x5),
    child: JentraPanel(
      child: JentraEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'CRM data unavailable',
        description: error is DomainError
            ? (error as DomainError).message
            : 'Jentra could not load the CRM workspace.',
        action: JentraPrimaryButton(label: 'Try again', onPressed: onRetry),
      ),
    ),
  );
}

class _CrmWorkspace extends ConsumerWidget {
  const _CrmWorkspace({required this.state});

  final CrmWorkspaceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessible = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Padding(
      padding: const EdgeInsets.all(JentraSpacing.x5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = accessible || constraints.maxWidth < 1080;
          if (stacked) {
            return ListView(
              children: [
                _PageHeader(state: state),
                const SizedBox(height: JentraSpacing.x4),
                _PipelineSummary(summary: state.summary),
                const SizedBox(height: JentraSpacing.x4),
                SizedBox(
                  height: accessible ? 560 : 440,
                  child: _PipelinePanel(state: state),
                ),
                const SizedBox(height: JentraSpacing.x4),
                SizedBox(
                  height: accessible ? 500 : 400,
                  child: _RecordDetail(state: state),
                ),
                const SizedBox(height: JentraSpacing.x4),
                SizedBox(
                  height: accessible ? 440 : 360,
                  child: _ActivityTimeline(state: state),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PageHeader(state: state),
              const SizedBox(height: JentraSpacing.x4),
              _PipelineSummary(summary: state.summary),
              const SizedBox(height: JentraSpacing.x4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 10, child: _PipelinePanel(state: state)),
                    const SizedBox(width: JentraSpacing.x3),
                    Expanded(flex: 11, child: _RecordDetail(state: state)),
                    const SizedBox(width: JentraSpacing.x3),
                    Expanded(flex: 9, child: _ActivityTimeline(state: state)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PageHeader extends ConsumerWidget {
  const _PageHeader({required this.state});

  final CrmWorkspaceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 760 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.5;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: JentraSpacing.x3,
            runSpacing: JentraSpacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Pipeline control centre',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              JentraStatusBadge(
                label: state.isOnline
                    ? ref.watch(runtimeConfigProvider).workspaceLabel
                    : 'Offline',
                tone: state.isOnline
                    ? JentraStatusTone.success
                    : JentraStatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: JentraSpacing.x1),
          Text(
            'As of ${_formatDate(state.summary.asOfDate)}',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: context.jentraColors.textSecondary),
          ),
        ],
      );
      final actions = Wrap(
        spacing: JentraSpacing.x2,
        runSpacing: JentraSpacing.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (state.canManageLeads && state.isOnline)
            JentraPrimaryButton(
              label: 'New lead',
              icon: Icons.add,
              onPressed: () => _showCreateLead(context, ref),
            ),
          IconButton(
            tooltip: 'Refresh CRM pipeline',
            onPressed: () => ref.read(crmControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: JentraSpacing.x3),
            actions,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          const SizedBox(width: JentraSpacing.x4),
          actions,
        ],
      );
    },
  );

  Future<void> _showCreateLead(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateLeadDialog(),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lead saved.')));
    }
  }
}

class _PipelineSummary extends StatelessWidget {
  const _PipelineSummary({required this.summary});

  final CrmPipelineSummary summary;

  @override
  Widget build(BuildContext context) => JentraPanel(
    padding: const EdgeInsets.symmetric(
      horizontal: JentraSpacing.x4,
      vertical: JentraSpacing.x3,
    ),
    semanticsLabel: 'Currency-separated CRM pipeline summary',
    child: Wrap(
      spacing: JentraSpacing.x6,
      runSpacing: JentraSpacing.x3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final total in summary.currencyTotals)
          _SummaryMetric(
            label: '${total.currencyCode} pipeline',
            value: _formatMoney(total.expectedValue),
            helper:
                '${total.opportunityCount} opportunities · weighted ${_formatMoney(total.weightedValue)}',
          ),
        _SummaryMetric(
          label: 'Lead conversion',
          value: '${summary.conversion.rate.toDecimalString()}%',
          helper:
              '${summary.conversion.convertedLeads} of ${summary.conversion.totalLeads} converted',
        ),
        _SummaryMetric(
          label: 'Decided outcomes',
          value: '${summary.winLoss.won} won · ${summary.winLoss.lost} lost',
          helper: '${summary.winLoss.decided} closed decisions',
        ),
        _SummaryMetric(
          label: 'Pipeline aging',
          value: '${summary.aging.averageAgeDays.toDecimalString()} days',
          helper:
              'Aging basis: created at · stale after ${summary.aging.staleAfterDays} days',
        ),
      ],
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 170, maxWidth: 255),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.jentraColors.textSecondary,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: JentraSpacing.x1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFamily: JentraTypography.monoFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          helper,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.jentraColors.textSecondary),
        ),
      ],
    ),
  );
}

class _PipelinePanel extends ConsumerWidget {
  const _PipelinePanel({required this.state});

  final CrmWorkspaceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => JentraPanel(
    padding: const EdgeInsets.all(JentraSpacing.x3),
    semanticsLabel: 'CRM pipeline records',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraSectionHeader(
          title: 'Pipeline',
          description: 'Leads and opportunities in one working queue.',
        ),
        const SizedBox(height: JentraSpacing.x3),
        _PipelineSearch(initialValue: state.query.search),
        const SizedBox(height: JentraSpacing.x3),
        Expanded(
          child: state.page.items.isEmpty
              ? const JentraEmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No pipeline records',
                  description: 'Adjust the search or create the first lead.',
                )
              : ListView.separated(
                  itemCount: state.page.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = state.page.items[index];
                    return _PipelineTile(
                      entry: entry,
                      selected: state.selectedEntry?.id == entry.id,
                      onTap: () => ref
                          .read(crmControllerProvider.notifier)
                          .selectEntry(entry),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _PipelineSearch extends ConsumerStatefulWidget {
  const _PipelineSearch({required this.initialValue});

  final String initialValue;

  @override
  ConsumerState<_PipelineSearch> createState() => _PipelineSearchState();
}

class _PipelineSearchState extends ConsumerState<_PipelineSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('crm-search'),
    controller: _controller,
    textInputAction: TextInputAction.search,
    onSubmitted: _submit,
    decoration: InputDecoration(
      hintText: 'Search code or name',
      prefixIcon: const Icon(Icons.search, size: 18),
      suffixIcon: IconButton(
        tooltip: 'Search pipeline',
        onPressed: () => _submit(_controller.text),
        icon: const Icon(Icons.arrow_forward, size: 18),
      ),
    ),
  );

  void _submit(String value) {
    ref.read(crmControllerProvider.notifier).applySearch(value);
  }
}

class _PipelineTile extends StatelessWidget {
  const _PipelineTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final CrmPipelineEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${entry.code}, ${entry.name}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JentraRadii.control),
      child: AnimatedContainer(
        duration: JentraMotion.fast,
        padding: const EdgeInsets.all(JentraSpacing.x3),
        decoration: BoxDecoration(
          color: selected
              ? JentraColors.green600.withValues(alpha: 0.09)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? JentraColors.green500
                : context.jentraColors.border,
          ),
          borderRadius: BorderRadius.circular(JentraRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.code,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontFamily: JentraTypography.monoFamily,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                JentraStatusBadge(
                  label: entry.stage,
                  tone: _stageTone(entry.stage),
                ),
              ],
            ),
            const SizedBox(height: JentraSpacing.x2),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: JentraSpacing.x1),
            Text(
              '${_formatMoney(entry.expectedValue)} · closes ${_formatDate(entry.expectedCloseDate)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.jentraColors.textSecondary,
                fontFamily: JentraTypography.monoFamily,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecordDetail extends StatelessWidget {
  const _RecordDetail({required this.state});

  final CrmWorkspaceState state;

  @override
  Widget build(BuildContext context) => JentraPanel(
    padding: const EdgeInsets.all(JentraSpacing.x4),
    semanticsLabel: 'Selected CRM record detail',
    child: state.selectedEntry == null
        ? const JentraEmptyState(
            icon: Icons.touch_app_outlined,
            title: 'Choose a pipeline record',
            description: 'Select a lead or opportunity to inspect its detail.',
          )
        : state.detailLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(child: _DetailBody(state: state)),
  );
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.state});

  final CrmWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final entry = state.selectedEntry!;
    final opportunity = state.selectedOpportunity;
    final lead = state.selectedLead;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.jentraColors.infoSurface,
                borderRadius: BorderRadius.circular(JentraRadii.control),
              ),
              child: Icon(
                entry.entryType == CrmEntryType.opportunity
                    ? Icons.trending_up
                    : Icons.person_add_alt_1_outlined,
                color: JentraColors.navy700,
                size: 19,
              ),
            ),
            const SizedBox(width: JentraSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.code} · ${entry.entryType.apiValue}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.jentraColors.textSecondary,
                      fontFamily: JentraTypography.monoFamily,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: JentraSpacing.x5),
        _DetailRow(label: 'Stage', value: entry.stage),
        _DetailRow(label: 'Status', value: entry.status),
        _DetailRow(
          label: 'Expected value',
          value: _formatMoney(entry.expectedValue),
        ),
        _DetailRow(
          label: 'Expected close',
          value: _formatDate(entry.expectedCloseDate),
        ),
        if (opportunity != null) ...[
          _DetailRow(
            label: 'Probability',
            value: '${opportunity.probability.toDecimalString()}%',
          ),
          _DetailRow(label: 'Forecast', value: opportunity.forecastBucket),
          _DetailRow(
            label: 'Next action',
            value: opportunity.nextAction ?? 'Not scheduled',
            emphasize: true,
          ),
        ],
        if (lead != null) ...[
          _DetailRow(label: 'Lead source', value: lead.source),
          _DetailRow(label: 'Lead type', value: lead.leadType),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: JentraSpacing.x2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.jentraColors.textSecondary),
          ),
        ),
        const SizedBox(width: JentraSpacing.x3),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? JentraColors.green700 : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.state});

  final CrmWorkspaceState state;

  @override
  Widget build(BuildContext context) => JentraPanel(
    padding: const EdgeInsets.all(JentraSpacing.x4),
    semanticsLabel: 'CRM activity timeline',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraSectionHeader(
          title: 'Activity',
          description: 'Most recent customer work first.',
        ),
        const SizedBox(height: JentraSpacing.x4),
        Expanded(
          child: state.selectedEntry == null
              ? const JentraEmptyState(
                  icon: Icons.history_outlined,
                  title: 'No record selected',
                  description: 'Choose a record to see its activity.',
                )
              : state.activities.isEmpty
              ? const JentraEmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'No activity yet',
                  description:
                      'Calls, meetings and follow-ups will appear here.',
                )
              : ListView.separated(
                  itemCount: state.activities.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: JentraSpacing.x5),
                  itemBuilder: (context, index) =>
                      _ActivityItem(activity: state.activities[index]),
                ),
        ),
      ],
    ),
  );
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.activity});

  final CrmActivity activity;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: JentraColors.green600.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          activity.activityType == 'call'
              ? Icons.call_outlined
              : Icons.event_note_outlined,
          color: JentraColors.green700,
          size: 16,
        ),
      ),
      const SizedBox(width: JentraSpacing.x3),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activity.subject,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: JentraSpacing.x1),
            Text(
              '${_formatDate(activity.activityAt)} · ${activity.status}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.jentraColors.textSecondary),
            ),
            if (activity.outcome case final outcome?) ...[
              const SizedBox(height: JentraSpacing.x2),
              Text(outcome, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    ],
  );
}

class _CreateLeadDialog extends ConsumerStatefulWidget {
  const _CreateLeadDialog();

  @override
  ConsumerState<_CreateLeadDialog> createState() => _CreateLeadDialogState();
}

class _CreateLeadDialogState extends ConsumerState<_CreateLeadDialog> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _source = TextEditingController();
  final _value = TextEditingController();
  final _currency = TextEditingController(text: 'LKR');
  final _closeDate = TextEditingController();
  late final String _commandId = _uuid.v4();
  late final String _idempotencyKey = _uuid.v4();
  bool _saving = false;
  String? _submissionError;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _source.dispose();
    _value.dispose();
    _currency.dispose();
    _closeDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create lead'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start in Draft. Jentra will preserve the same request identity if you retry.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.jentraColors.textSecondary),
              ),
              const SizedBox(height: JentraSpacing.x4),
              TextFormField(
                key: const Key('crm-lead-code'),
                controller: _code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Lead code'),
                validator: (value) =>
                    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{1,31}$')
                        .hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Use 2–32 letters, numbers, dots, dashes, or underscores.',
              ),
              const SizedBox(height: JentraSpacing.x3),
              TextFormField(
                key: const Key('crm-lead-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Lead name'),
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  return length >= 2 && length <= 180
                      ? null
                      : 'Enter a name from 2 to 180 characters.';
                },
              ),
              const SizedBox(height: JentraSpacing.x3),
              TextFormField(
                key: const Key('crm-lead-source'),
                controller: _source,
                decoration: const InputDecoration(labelText: 'Lead source'),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'Enter a lead source.',
              ),
              const SizedBox(height: JentraSpacing.x3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const Key('crm-lead-value'),
                      controller: _value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Expected value',
                      ),
                      validator: _validateAmount,
                    ),
                  ),
                  const SizedBox(width: JentraSpacing.x3),
                  Expanded(
                    child: TextFormField(
                      key: const Key('crm-lead-currency'),
                      controller: _currency,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      validator: (value) =>
                          RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Use a 3-letter code.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: JentraSpacing.x3),
              TextFormField(
                key: const Key('crm-lead-close-date'),
                controller: _closeDate,
                decoration: const InputDecoration(
                  labelText: 'Expected close date',
                  hintText: 'YYYY-MM-DD',
                ),
                validator: (value) =>
                    _parseDateOnly(value?.trim() ?? '') == null
                    ? 'Enter a valid date as YYYY-MM-DD.'
                    : null,
              ),
              if (_submissionError case final error?) ...[
                const SizedBox(height: JentraSpacing.x3),
                Text(
                  error,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: JentraColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      JentraPrimaryButton(
        label: 'Save lead',
        loading: _saving,
        onPressed: _saving ? null : _save,
      ),
    ],
  );

  Future<void> _save() async {
    setState(() => _submissionError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final contextScope = ref.read(activeTenantContextProvider);
    if (contextScope == null) {
      setState(() => _submissionError = 'Choose a business scope first.');
      return;
    }
    final closeDate = _parseDateOnly(_closeDate.text.trim())!;
    final expectedValue = Money.parse(
      _value.text.trim(),
      _currency.text.trim(),
    );
    final draft = CrmLeadDraft(
      code: _code.text,
      leadType: 'organization',
      name: _name.text,
      source: _source.text,
      ownerId: contextScope.actorId,
      stage: 'draft',
      expectedValue: expectedValue,
      expectedCloseDate: closeDate,
    );

    setState(() => _saving = true);
    final result = await ref
        .read(crmControllerProvider.notifier)
        .createLead(
          draft: draft,
          commandId: _commandId,
          idempotencyKey: _idempotencyKey,
        );
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _submissionError = result.error?.message ?? 'The lead was not saved.';
    });
  }

  static String? _validateAmount(String? value) {
    final normalized = value?.trim() ?? '';
    if (!RegExp(r'^\d{1,14}(?:\.\d{1,6})?$').hasMatch(normalized)) {
      return 'Enter a non-negative value with up to 6 decimals.';
    }
    return null;
  }
}

JentraStatusTone _stageTone(String stage) => switch (stage) {
  'approved' || 'won' || 'fulfilled' => JentraStatusTone.success,
  'rejected' || 'lost' || 'cancelled' => JentraStatusTone.danger,
  'submitted' || 'qualified' => JentraStatusTone.info,
  _ => JentraStatusTone.neutral,
};

String _formatMoney(Money money) {
  final raw = money.toDecimalString();
  final negative = raw.startsWith('-');
  final unsigned = negative ? raw.substring(1) : raw;
  final parts = unsigned.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${money.currencyCode} ${negative ? '-' : ''}$grouped.${parts.last}';
}

String _formatDate(DateTime value) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day.toString().padLeft(2, '0')} ${months[value.month - 1]} ${value.year}';
}

DateTime? _parseDateOnly(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}
