import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

class EmployeeHeading extends StatelessWidget {
  const EmployeeHeading(this.text, {this.large = false, super.key});
  final String text;
  final bool large;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: large
          ? Theme.of(context).textTheme.headlineMedium
          : Theme.of(context).textTheme.titleLarge,
    ),
  );
}

class EmployeeMessage extends StatelessWidget {
  const EmployeeMessage({
    required this.title,
    this.message,
    this.icon = Icons.info_outline,
    this.warning = false,
    this.error = false,
    this.action,
    super.key,
  });
  final String title;
  final String? message;
  final IconData icon;
  final bool warning, error;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final colors = context.jentraColors;
    final ink = error
        ? colors.danger
        : warning
        ? colors.warning
        : colors.info;
    final fill = error
        ? colors.dangerSurface
        : warning
        ? colors.warningSurface
        : colors.infoSurface;
    return Semantics(
      container: true,
      liveRegion: error,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, color: ink, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: ink),
                  ),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: ink),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class EmployeeActionTile extends StatelessWidget {
  const EmployeeActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.jentraColors.panel,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.jentraColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: context.jentraColors.action, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class EmployeeStatus extends StatelessWidget {
  const EmployeeStatus(
    this.label, {
    this.icon = Icons.info_outline,
    this.warning = false,
    super.key,
  });
  final String label;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final colors = context.jentraColors;
    final ink = warning ? colors.warning : colors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warning ? colors.warningSurface : colors.infoSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeePageBody extends StatelessWidget {
  const EmployeePageBody({required this.children, this.onRefresh, super.key});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final scroll = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ],
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}
