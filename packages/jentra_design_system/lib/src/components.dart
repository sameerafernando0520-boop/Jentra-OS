import 'package:flutter/material.dart';

import 'tokens.dart';

class JentraPanel extends StatelessWidget {
  const JentraPanel({
    required this.child,
    this.padding = const EdgeInsets.all(JentraSpacing.x5),
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.jentraColors.panel,
        border: Border.all(color: context.jentraColors.border),
        borderRadius: BorderRadius.circular(JentraRadii.card),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class JentraPrimaryButton extends StatelessWidget {
  const JentraPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    if (icon != null && !loading) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: child,
      );
    }
    return FilledButton(onPressed: onPressed, child: child);
  }
}

enum JentraStatusTone { neutral, success, warning, danger, info }

class JentraStatusBadge extends StatelessWidget {
  const JentraStatusBadge({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  final String label;
  final JentraStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.jentraColors;
    final (foreground, background, fallbackIcon) = switch (tone) {
      JentraStatusTone.success => (
        JentraColors.success,
        colors.successSurface,
        Icons.check_circle_outline,
      ),
      JentraStatusTone.warning => (
        JentraColors.warning,
        colors.warningSurface,
        Icons.warning_amber_rounded,
      ),
      JentraStatusTone.danger => (
        JentraColors.danger,
        colors.dangerSurface,
        Icons.error_outline,
      ),
      JentraStatusTone.info => (
        JentraColors.info,
        colors.infoSurface,
        Icons.info_outline,
      ),
      JentraStatusTone.neutral => (
        colors.textSecondary,
        colors.border.withValues(alpha: 0.35),
        Icons.circle_outlined,
      ),
    };

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Status: $label',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon ?? fallbackIcon, size: 13, color: foreground),
              const SizedBox(width: JentraSpacing.x1),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JentraKpiCard extends StatelessWidget {
  const JentraKpiCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    this.tone = JentraStatusTone.neutral,
    super.key,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final JentraStatusTone tone;

  @override
  Widget build(BuildContext context) => JentraPanel(
    semanticsLabel: '$label: $value, $helper',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.jentraColors.infoSurface,
            borderRadius: BorderRadius.circular(JentraRadii.control),
          ),
          child: Icon(icon, size: 19, color: JentraColors.navy700),
        ),
        const SizedBox(width: JentraSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: JentraSpacing.x1),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: JentraTypography.monoFamily,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: JentraSpacing.x2),
              JentraStatusBadge(label: helper, tone: tone),
            ],
          ),
        ),
      ],
    ),
  );
}

class JentraSectionHeader extends StatelessWidget {
  const JentraSectionHeader({
    required this.title,
    this.description,
    this.trailing,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (description case final description?) ...[
              const SizedBox(height: JentraSpacing.x1),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.jentraColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class JentraEmptyState extends StatelessWidget {
  const JentraEmptyState({
    required this.title,
    required this.description,
    required this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(JentraSpacing.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: JentraColors.navy700),
            const SizedBox(height: JentraSpacing.x4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: JentraSpacing.x2),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.jentraColors.textSecondary,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: JentraSpacing.x5),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}
