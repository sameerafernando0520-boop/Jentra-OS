import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import '../../app_providers.dart';
import 'assurance_metrics_controller.dart';

class AssuranceMetricsScreen extends ConsumerWidget {
  const AssuranceMetricsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return JentraEmptyState(
        title: 'Access could not be checked',
        description: 'Check your connection, then try again.',
        icon: Icons.cloud_off_outlined,
        action: OutlinedButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(assuranceMetricsControllerProvider);
    return c == null
        ? const JentraEmptyState(
            title: 'Audit metrics are for audit teams',
            description: 'Ask an organisation owner for an assurance role to see how audits are running.',
            icon: Icons.insights_outlined,
          )
        : AssuranceMetricsView(key: ValueKey(c), controller: c);
  }
}

String _number(double d) =>
    d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
String _days(double d) => '${_number(d)} ${d == 1 ? 'day' : 'days'}';
String _percent(double v) => '${(v * 100).round()}%';
String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

String _severity(AssuranceSeverity s) => switch (s) {
  AssuranceSeverity.low => 'Low',
  AssuranceSeverity.medium => 'Medium',
  AssuranceSeverity.high => 'High',
  AssuranceSeverity.critical => 'Critical',
};

class AssuranceMetricsView extends StatelessWidget {
  const AssuranceMetricsView({super.key, required this.controller});
  final AssuranceMetricsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, m = c.metrics, theme = Theme.of(context);
      final colors = context.jentraColors;
      if (c.accessDenied) {
        return JentraEmptyState(
          title: 'Access changed',
          description: 'Audit metrics have been cleared. ${c.error ?? ''}',
          icon: Icons.lock_outline,
          action: OutlinedButton(
            onPressed: c.busy || !c.online ? null : c.load,
            child: const Text('Recheck access'),
          ),
        );
      }
      final format = DateFormat('d MMM y');
      final r = c.range;
      return ListView(
        padding: const EdgeInsets.all(JentraSpacing.x6),
        children: [
          JentraSectionHeader(
            title: 'Audit metrics',
            description:
                'How audits move from planning to report, measured from '
                'recorded events. Times show the median, with the 90th '
                'percentile beneath. A metric with no samples shows as not '
                'measured, never as zero.',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: c.busy || !c.online ? null : c.load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: JentraSpacing.x4),
          Semantics(
            container: true,
            label: 'Period',
            child: Wrap(
              spacing: JentraSpacing.x2,
              runSpacing: JentraSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Period', style: theme.textTheme.labelLarge),
                for (final p in MetricsPeriod.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p == c.period,
                    onSelected: c.online ? (_) => c.choose(p) : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: JentraSpacing.x2),
          Text(
            '${format.format(r.from)} – ${format.format(r.to)}'
            '${m == null ? '' : ' · ${_count(m.engagements, 'engagement')} in this period'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const JentraStatusBadge(
              label: 'Offline — metrics load when you reconnect',
              tone: JentraStatusTone.warning,
            ),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Wrap(
                spacing: JentraSpacing.x3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(c.error!, style: TextStyle(color: colors.danger)),
                  TextButton(
                    onPressed: c.busy || !c.online ? null : c.load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          if (m != null && m.engagements == 0)
            const JentraEmptyState(
              title: 'No engagements in this period',
              description: 'Choose a longer period, or plan an engagement to start measuring.',
              icon: Icons.event_busy_outlined,
            ),
          if (m != null && m.engagements > 0) ..._sections(context, m),
        ],
      );
    },
  );

  List<Widget> _sections(BuildContext context, AssuranceMetrics m) {
    MetricCard spread(String label, Spread s, String noun, String about) =>
        MetricCard(
          label: label,
          value: s.measured ? _days(s.p50!) : null,
          detail: s.measured
              ? '90th percentile ${_days(s.p90!)} · ${_count(s.samples, noun)}'
              : null,
          definition: about,
        );
    MetricCard rate(String label, Measured v, String noun, String about) =>
        MetricCard(
          label: label,
          value: v.measured ? _percent(v.value!) : null,
          detail: v.measured ? _count(v.samples, noun) : null,
          definition: about,
        );
    final a = m.requestAgeing;
    return [
      MetricSection(
        title: 'Engagement stages',
        cards: [
          spread(
            'Planning',
            m.stages['planning']!,
            'engagement',
            'Time an engagement spends in planning.',
          ),
          spread(
            'Fieldwork',
            m.stages['fieldwork']!,
            'engagement',
            'Time an engagement spends in fieldwork.',
          ),
          spread(
            'Reporting',
            m.stages['reporting']!,
            'engagement',
            'Time an engagement spends in reporting.',
          ),
          spread(
            'Report issuance',
            m.reportIssuance,
            'report',
            'From entering reporting to issuing the report.',
          ),
        ],
      ),
      MetricSection(
        title: 'Evidence',
        cards: [
          spread(
            'Waiting for evidence',
            m.evidenceWaiting,
            'request',
            'From a request to its first submission.',
          ),
          spread(
            'Review time',
            m.evidenceReview,
            'request',
            'From the latest submission to acceptance.',
          ),
          rate(
            'First time right',
            m.firstTimeRight,
            'accepted request',
            'Accepted requests that needed no rework.',
          ),
          MetricCard(
            label: 'Open requests by age',
            value: '${a.samples} open',
            detail: a.d31plus > 0
                ? '${a.d31plus} over 30 days'
                : a.samples == 0
                ? 'No open requests'
                : null,
            definition: 'Days since each open request was made.',
            attention: a.d31plus > 0,
            rows: a.samples == 0
                ? null
                : [
                    ('Up to 7 days', '${a.d0to7}'),
                    ('8–30 days', '${a.d8to30}'),
                    ('Over 30 days', '${a.d31plus}'),
                  ],
          ),
        ],
      ),
      MetricSection(
        title: 'Testing',
        cards: [
          rate(
            'Test completion',
            m.testCompletion,
            'procedure',
            'Test procedures that have been reviewed.',
          ),
          rate(
            'Control coverage',
            m.controlCoverage,
            'control',
            'Controls with at least one reviewed test.',
          ),
          rate(
            'Retest pass rate',
            m.retestPassRate,
            'retest',
            'Retests of findings that passed.',
          ),
        ],
      ),
      MetricSection(
        title: 'Findings',
        cards: [
          MetricCard(
            label: 'Open high-risk findings',
            value: '${m.openHighRisk}',
            detail: m.openHighRisk == 0 ? 'None open' : 'Needs attention',
            definition: 'High and critical findings not yet closed.',
            attention: m.openHighRisk > 0,
          ),
          MetricCard(
            label: 'Overdue remediation',
            value: '${m.overdueRemediation}',
            detail: m.overdueRemediation == 0 ? 'None overdue' : 'Past due',
            definition: 'Findings past their remediation date.',
            attention: m.overdueRemediation > 0,
          ),
          MetricCard(
            label: 'Recurrence',
            value: m.recurrence.measured
                ? m.recurrence.value!.toStringAsFixed(2)
                : null,
            detail: m.recurrence.measured
                ? 'Reopens per finding · ${_count(m.recurrence.samples, 'finding')}'
                : null,
            definition: 'Times findings were reopened, per finding.',
          ),
          MetricCard(
            label: 'Finding age',
            value: null,
            detail: null,
            definition: 'Average days open, by severity.',
            rows: [
              for (final s in AssuranceSeverity.values.reversed)
                (_severity(s), m.findingAge(s)),
            ],
          ),
        ],
      ),
      _Workload(metrics: m),
    ];
  }
}

extension on AssuranceMetrics {
  String findingAge(AssuranceSeverity s) {
    final v = findingAgeing[s]!;
    return v.measured ? '${_days(v.value!)} · ${v.samples} open' : 'None open';
  }
}

class MetricSection extends StatelessWidget {
  const MetricSection({super.key, required this.title, required this.cards});
  final String title;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: JentraSpacing.x6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: JentraSpacing.x3),
        // Columns narrow as text grows, so values never truncate.
        LayoutBuilder(
          builder: (context, box) {
            const gap = JentraSpacing.x3;
            final min = MediaQuery.textScalerOf(context).scale(220);
            final columns = ((box.maxWidth + gap) / (min + gap)).floor().clamp(
              1,
              cards.length,
            );
            final width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in cards) SizedBox(width: width, child: c),
              ],
            );
          },
        ),
      ],
    ),
  );
}

/// One metric: a value with its unit, the samples behind it and a one-line
/// definition. A null [value] without [rows] is "not measured".
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.definition,
    this.attention = false,
    this.rows,
  });
  final String label;
  final String? value;
  final String? detail;
  final String definition;
  final bool attention;
  final List<(String, String)>? rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = context.jentraColors;
    final measured = value != null || rows != null;
    final shown = value ?? (rows == null ? 'Not measured' : null);
    final note = detail ?? (measured ? null : 'No samples in this period');
    return Semantics(
      container: true,
      label: [
        label,
        ?shown,
        ?note,
        for (final (k, v) in rows ?? const <(String, String)>[]) '$k: $v',
        definition,
      ].join('. '),
      excludeSemantics: true,
      child: JentraPanel(
        padding: const EdgeInsets.all(JentraSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (shown != null) ...[
              const SizedBox(height: JentraSpacing.x2),
              Text(
                shown,
                style: measured
                    ? theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: JentraTypography.monoFamily,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )
                    : theme.textTheme.titleMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
              ),
            ],
            for (final (k, v) in rows ?? const <(String, String)>[])
              Padding(
                padding: const EdgeInsets.only(top: JentraSpacing.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(k, style: theme.textTheme.bodyMedium)),
                    const SizedBox(width: JentraSpacing.x2),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          v,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (note != null) ...[
              const SizedBox(height: JentraSpacing.x2),
              attention
                  ? JentraStatusBadge(
                      label: note,
                      tone: JentraStatusTone.warning,
                    )
                  : Text(note, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: JentraSpacing.x2),
            Text(
              definition,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Workload extends StatelessWidget {
  const _Workload({required this.metrics});
  final AssuranceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = context.jentraColors;
    return Padding(
      padding: const EdgeInsets.only(top: JentraSpacing.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Workload', style: theme.textTheme.titleMedium),
          ),
          Text(
            'Open evidence requests and findings by owner, busiest first.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (metrics.workload.isEmpty)
            const JentraEmptyState(
              title: 'No open work is assigned',
              description: 'Open evidence requests and findings with an owner appear here.',
              icon: Icons.assignment_ind_outlined,
            ),
          for (final w in metrics.workload)
            Padding(
              padding: const EdgeInsets.only(bottom: JentraSpacing.x2),
              child: JentraPanel(
                semanticsLabel:
                    '${w.label}: ${_count(w.openRequests, 'open request')}, '
                    '${_count(w.openFindings, 'open finding')}',
                padding: const EdgeInsets.all(JentraSpacing.x4),
                child: Wrap(
                  spacing: JentraSpacing.x3,
                  runSpacing: JentraSpacing.x2,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(w.label, style: theme.textTheme.titleSmall),
                    Wrap(
                      spacing: JentraSpacing.x2,
                      runSpacing: JentraSpacing.x2,
                      children: [
                        JentraStatusBadge(
                          label: _count(w.openRequests, 'open request'),
                          tone: JentraStatusTone.info,
                        ),
                        JentraStatusBadge(
                          label: _count(w.openFindings, 'open finding'),
                          tone: w.openFindings > 0
                              ? JentraStatusTone.warning
                              : JentraStatusTone.neutral,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
