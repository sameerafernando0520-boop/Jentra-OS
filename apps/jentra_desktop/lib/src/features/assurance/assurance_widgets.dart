import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import 'assurance_format.dart';

/// The header every audit screen shares: title, what the screen is for, a
/// refresh button and, where the screen has them, its sections.
class AuditScreenHeader extends StatelessWidget {
  const AuditScreenHeader({
    super.key,
    required this.title,
    required this.description,
    required this.onRefresh,
    this.sections = const [],
    this.selected,
    this.onSelect,
  });

  final String title;
  final String description;

  /// Null while the screen is busy or offline.
  final VoidCallback? onRefresh;

  /// (key, label) pairs.
  final List<(String, String)> sections;
  final String? selected;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      JentraSectionHeader(
        title: title,
        description: description,
        trailing: IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
      if (sections.isNotEmpty) ...[
        const SizedBox(height: JentraSpacing.x4),
        Semantics(
          container: true,
          label: 'Sections',
          child: Wrap(
            spacing: JentraSpacing.x2,
            runSpacing: JentraSpacing.x2,
            children: [
              for (final (key, label) in sections)
                ChoiceChip(
                  label: Text(label),
                  selected: selected == key,
                  onSelected: onSelect == null ? null : (_) => onSelect!(key),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}

/// One tone per status across the audit screens: done is success, waiting on
/// someone else is info, needing a decision or response is warning, critical
/// is danger and anything settled or not started is neutral.
JentraStatusTone auditTone(Object status) => switch (status) {
  EngagementStatus.issued ||
  EvidenceRequestStatus.accepted ||
  TestProcedureStatus.reviewed ||
  FindingStatus.closed ||
  PlanStatus.approved => JentraStatusTone.success,
  EngagementStatus.fieldwork ||
  EngagementStatus.reporting ||
  EvidenceRequestStatus.open ||
  EvidenceRequestStatus.submitted ||
  TestProcedureStatus.executed ||
  ExceptionStatus.promoted ||
  FindingStatus.remediating ||
  FindingStatus.retestPending ||
  PlanStatus.submitted ||
  AssuranceSeverity.medium => JentraStatusTone.info,
  ExceptionStatus.candidate ||
  FindingStatus.issued ||
  FindingStatus.riskPending ||
  AssuranceSeverity.high => JentraStatusTone.warning,
  AssuranceSeverity.critical => JentraStatusTone.danger,
  _ => JentraStatusTone.neutral,
};

/// A status badge in words, e.g. `FindingStatus.riskAccepted` → "Risk accepted".
JentraStatusBadge auditBadge(Object status, {String? label}) =>
    JentraStatusBadge(
      label:
          label ??
          auditLabel(switch (status) {
            final FindingStatus s => s.wire,
            final Enum e => e.name,
            _ => '$status',
          }),
      tone: auditTone(status),
    );

/// A date chosen from a calendar and shown as "8 Oct 2026"; the form keeps
/// the civil date (`2026-10-08`) the server takes.
class AuditDateField extends StatelessWidget {
  const AuditDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.firstDate,
  });

  final String label;

  /// `YYYY-MM-DD`, or empty when not chosen yet.
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// The earliest date offered, e.g. a period end no earlier than its start.
  final String? firstDate;

  @override
  Widget build(BuildContext context) {
    final current = DateTime.tryParse(value ?? '');
    final shown = current == null ? 'Not set' : auditDate(current);
    Future<void> pick() async {
      final earliest = DateTime.tryParse(firstDate ?? '');
      final first = earliest ?? DateTime(2000);
      final last = DateTime(2100, 12, 31);
      final now = DateTime.now();
      // An unset end date opens at its start, e.g. the period start.
      var initial =
          current ?? earliest ?? DateTime(now.year, now.month, now.day);
      if (initial.isBefore(first)) initial = first;
      if (initial.isAfter(last)) initial = last;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first,
        lastDate: last,
        helpText: label,
      );
      if (picked != null) onChanged(auditIsoDate(picked));
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: '$label, $shown',
      child: InkWell(
        onTap: enabled ? pick : null,
        borderRadius: BorderRadius.circular(JentraRadii.control),
        child: ExcludeSemantics(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              enabled: enabled,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(shown),
          ),
        ),
      ),
    );
  }
}

/// A list item on the audit screens: a title with status badges, a line of
/// details, an optional digest and its actions. With [onOpen] the whole
/// panel is one button that opens the item.
class AuditItemPanel extends StatelessWidget {
  const AuditItemPanel({
    super.key,
    required this.title,
    this.badges = const [],
    this.details = const [],
    this.digest,
    this.actions = const [],
    this.onOpen,
    this.openLabel,
  });

  final String title;
  final List<Widget> badges;
  final List<String> details;
  final String? digest;
  final List<Widget> actions;

  /// Opens the item; null while that is unavailable (busy or unverified).
  final VoidCallback? onOpen;

  /// What a screen reader announces for opening, e.g. "Open FY27 Treasury";
  /// set for every openable item so the panel keeps its look when disabled.
  final String? openLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = context.jentraColors;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: JentraSpacing.x2,
          runSpacing: JentraSpacing.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            ...badges,
          ],
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: JentraSpacing.x1),
          Text(
            details.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
        if (digest case final digest?) ...[
          const SizedBox(height: JentraSpacing.x1),
          DigestText(digest, style: theme.textTheme.bodySmall),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: JentraSpacing.x2),
          Wrap(
            spacing: JentraSpacing.x2,
            runSpacing: JentraSpacing.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );
    const padding = EdgeInsets.all(JentraSpacing.x4);
    // An openable item keeps its look while opening is briefly unavailable.
    final openable = onOpen != null || openLabel != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: JentraSpacing.x2),
      child: !openable
          ? JentraPanel(padding: padding, child: body)
          : JentraPanel(
              padding: EdgeInsets.zero,
              child: Semantics(
                button: true,
                enabled: onOpen != null,
                label: openLabel,
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(JentraRadii.card),
                  child: Padding(
                    padding: padding,
                    child: Row(
                      children: [
                        Expanded(child: body),
                        const SizedBox(width: JentraSpacing.x2),
                        Icon(Icons.chevron_right, color: colors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The empty state when nothing could be read: offline, a load that failed,
/// or nothing loaded yet. Each says what to do next.
class AuditNotLoaded extends StatelessWidget {
  const AuditNotLoaded({
    super.key,
    required this.what,
    required this.online,
    required this.failed,
    required this.onRefresh,
  });

  /// What is missing, e.g. "your audit work".
  final String what;
  final bool online;
  final bool failed;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final (title, description, icon) = !online
        ? (
            'You are offline',
            'Reconnect, then refresh to load $what. Saved drafts stay on '
                'this device.',
            Icons.cloud_off_outlined,
          )
        : failed
        ? (
            'This could not be loaded',
            'Try again. If it keeps failing, check your connection or ask an '
                'organisation owner about your access.',
            Icons.sync_problem_outlined,
          )
        : ('Nothing loaded yet', 'Refresh to load $what.', Icons.refresh);
    return JentraEmptyState(
      title: title,
      description: description,
      icon: icon,
      action: OutlinedButton(
        onPressed: online ? onRefresh : null,
        child: Text(failed ? 'Try again' : 'Refresh'),
      ),
    );
  }
}

/// A status line that wraps rather than cutting long text: offline, errors
/// and confirmations.
class AuditNotice extends StatelessWidget {
  const AuditNotice(this.text, {super.key, required this.tone});
  final String text;
  final JentraStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.jentraColors;
    final (foreground, background, icon) = switch (tone) {
      JentraStatusTone.success => (
        colors.success,
        colors.successSurface,
        Icons.check_circle_outline,
      ),
      JentraStatusTone.warning => (
        colors.warning,
        colors.warningSurface,
        Icons.cloud_off_outlined,
      ),
      JentraStatusTone.danger => (
        colors.danger,
        colors.dangerSurface,
        Icons.error_outline,
      ),
      JentraStatusTone.info => (
        colors.info,
        colors.infoSurface,
        Icons.info_outline,
      ),
      JentraStatusTone.neutral => (
        colors.textSecondary,
        colors.neutralSurface,
        Icons.info_outline,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: JentraSpacing.x2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(JentraRadii.control),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: JentraSpacing.x3,
              vertical: JentraSpacing.x2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 18, color: foreground),
                ),
                const SizedBox(width: JentraSpacing.x2),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
