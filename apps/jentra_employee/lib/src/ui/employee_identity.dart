import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../data/employee_gateway.dart';
import '../l10n/employee_strings.dart';

class EmployeeAvatar extends StatefulWidget {
  const EmployeeAvatar({
    required this.name,
    this.photo,
    this.size = 64,
    super.key,
  });
  final String name;
  final Uint8List? photo;
  final double size;
  @override
  State<EmployeeAvatar> createState() => _EmployeeAvatarState();
}

class _EmployeeAvatarState extends State<EmployeeAvatar> {
  void _evict(Uint8List? bytes) {
    if (bytes != null) unawaited(MemoryImage(bytes).evict().then<void>((_) {}));
  }

  @override
  void didUpdateWidget(EmployeeAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.photo, widget.photo)) _evict(oldWidget.photo);
  }

  @override
  void dispose() {
    // Do not retain private photo pixels in Flutter's shared image cache after
    // account masking, replacement or removal. Evict only this owned provider.
    _evict(widget.photo);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final photo = widget.photo;
    final size = widget.size;
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : [
            words.first,
            if (words.length > 1) words.last,
          ].map((w) => w.characters.first).join().toUpperCase();
    return Semantics(
      image: true,
      label: EmployeeStrings.of(context)('profilePhoto'),
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .25),
          ),
          child: ClipOval(
            child: photo != null
                ? Image.memory(
                    photo,
                    key: const Key('employee-avatar-image'),
                    fit: BoxFit.cover,
                    gaplessPlayback: false,
                    errorBuilder: (_, _, _) => _initials(initials),
                  )
                : _initials(initials),
          ),
        ),
      ),
    );
  }

  Widget _initials(String initials) => ColoredBox(
    color: const Color(0xFFDCEAFF),
    child: Center(
      child: Text(
        initials,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: JentraTypography.sansFamily,
          fontFamilyFallback: JentraTypography.fallbackFamilies,
          color: const Color(0xFF10283F),
          fontSize: widget.size * .3,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// Original arc motif and personal hierarchy shared by Home and Profile.
class EmployeeIdentityHero extends StatelessWidget {
  const EmployeeIdentityHero({
    required this.identity,
    this.photo,
    this.onOpen,
    this.centered = false,
    super.key,
  });
  final EmployeeIdentity identity;
  final Uint8List? photo;
  final VoidCallback? onOpen;
  final bool centered;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    final stacked = centered || MediaQuery.textScalerOf(context).scale(14) > 20;
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          identity.displayName,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontSize: centered ? 26 : 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          identity.workspace.branchName,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: const Color(0xFFC9DAEA)),
        ),
      ],
    );
    return Material(
      color: const Color(0xFF10283F),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('employee-open-profile'),
        onTap: onOpen,
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _IdentityArcs()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: centered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  if (!centered) ...[
                    Text(
                      s('mySpace'),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: const Color(0xFFC9DAEA)),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (stacked) ...[
                    EmployeeAvatar(
                      name: identity.displayName,
                      photo: photo,
                      size: centered ? 96 : 64,
                    ),
                    const SizedBox(height: 16),
                    details,
                  ] else
                    Row(
                      children: [
                        EmployeeAvatar(
                          name: identity.displayName,
                          photo: photo,
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: details),
                      ],
                    ),
                  const SizedBox(height: 22),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: .16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: Color(0xFFC9DAEA),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          centered
                              ? s('connectedProfile')
                              : identity.workspace.tenantName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFFC9DAEA)),
                        ),
                      ),
                      if (onOpen != null) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityArcs extends CustomPainter {
  const _IdentityArcs();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;
    final origin = Offset(size.width + 12, -32);
    canvas.drawCircle(origin, 110, paint);
    canvas.drawCircle(origin, 163, paint);
    canvas.drawCircle(origin, 216, paint);
  }

  @override
  bool shouldRepaint(_IdentityArcs oldDelegate) => false;
}

class EmployeeServiceGroup extends StatelessWidget {
  const EmployeeServiceGroup({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    color: context.jentraColors.panel,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              indent: 72,
              endIndent: 18,
              color: context.jentraColors.border.withValues(alpha: .7),
            ),
          children[i],
        ],
      ],
    ),
  );
}

class EmployeeServiceRow extends StatelessWidget {
  const EmployeeServiceRow({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 78),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.jentraColors.infoSurface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 22, color: context.jentraColors.action),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.jentraColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.jentraColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
