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
    child: Material(
      color: context.jentraColors.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.jentraColors.border),
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
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.jentraColors.textSecondary,
                ),
              ),
              const SizedBox(width: JentraSpacing.x2),
              Text(label),
            ],
          )
        : Text(label);
    if (icon != null && !loading) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: child,
      );
    }
    return Semantics(
      liveRegion: loading,
      label: loading ? '$label, in progress' : null,
      excludeSemantics: loading,
      button: loading,
      enabled: loading ? false : null,
      child: FilledButton(onPressed: loading ? null : onPressed, child: child),
    );
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
        colors.success,
        colors.successSurface,
        Icons.check_circle_outline,
      ),
      JentraStatusTone.warning => (
        colors.warning,
        colors.warningSurface,
        Icons.warning_amber_rounded,
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
          borderRadius: BorderRadius.circular(6),
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
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value, $helper',
    excludeSemantics: true,
    child: JentraPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.jentraColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: JentraSpacing.x2),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: context.jentraColors.infoSurface,
                  borderRadius: BorderRadius.circular(JentraRadii.control),
                ),
                child: Icon(icon, size: 17, color: context.jentraColors.info),
              ),
            ],
          ),
          const SizedBox(height: JentraSpacing.x2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: JentraTypography.monoFamily,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.8,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: JentraSpacing.x3),
          JentraStatusBadge(label: helper, tone: tone),
        ],
      ),
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
            Icon(icon, size: 36, color: context.jentraColors.action),
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
