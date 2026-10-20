import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../app_providers.dart';

final notificationInboxGatewayProvider = Provider<NotificationInboxGateway?>(
  (ref) => null,
);

final inboxControllerProvider = Provider.autoDispose<InboxController?>((ref) {
  final scope = ref.watch(activeTenantContextProvider),
      gateway = ref.watch(notificationInboxGatewayProvider);
  if (scope == null || gateway == null) return null;
  final c = InboxController(
    tenantId: scope.tenantId,
    gateway: gateway,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(
    connectivityStateProvider,
    (_, s) => c.setOnline(s.value == ConnectivityState.online),
  );
  ref.onDispose(c.dispose);
  unawaited(c.refresh());
  return c;
});

/// Two letters for the avatar: from the person's name, else their e-mail.
String userInitials({String? name, String? email}) {
  final words = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 2) {
    return (words.first[0] + words.last[0]).toUpperCase();
  }
  if (words.length == 1 && words.first.length >= 2) {
    return words.first.substring(0, 2).toUpperCase();
  }
  final local = (email ?? '').split('@').first;
  final parts = local
      .split(RegExp(r'[._\-+]'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length >= 2) return (parts.first[0] + parts[1][0]).toUpperCase();
  if (local.length >= 2) return local.substring(0, 2).toUpperCase();
  return '?';
}

/// The signed-in person for the shell avatar; null before sign-in.
final signedInUserProvider = Provider<({String initials, String tooltip})?>((
  ref,
) {
  ref.watch(authSessionRevisionProvider);
  final user = ref.watch(foundationGatewayProvider)?.currentUser;
  if (user == null) return null;
  final meta = user.userMetadata ?? const <String, dynamic>{};
  final name = (meta['full_name'] ?? meta['name']) as String?;
  final email = user.email;
  return (
    initials: userInitials(name: name, email: email),
    tooltip: [?name, ?email].where((s) => s.isNotEmpty).join(' · '),
  );
});

/// The signed-in user's notices: newest first, unread count, mark read.
final class InboxController extends ChangeNotifier {
  InboxController({
    required this.tenantId,
    required this.gateway,
    required this.online,
  });

  final String tenantId;
  final NotificationInboxGateway gateway;
  bool online;
  bool busy = false;
  bool _disposed = false;
  List<InboxNotice> notices = [];
  int unread = 0;
  String? error;

  String? get status =>
      online ? null : 'Notifications are unavailable offline.';

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    if (!value) {
      notices = [];
      unread = 0;
    }
    _emit();
    if (value) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!online) {
      notices = [];
      unread = 0;
      _emit();
      return;
    }
    busy = true;
    error = null;
    _emit();
    try {
      final list = await gateway.latest(tenantId);
      final count = await gateway.unreadCount(tenantId);
      if (_disposed) return;
      notices = list;
      unread = count;
    } on DomainError catch (e) {
      error = e.message;
    } on FormatException {
      error = 'Notifications could not be read.';
    } catch (_) {
      error = 'Notifications could not be loaded. Try again.';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<String?> _mark(InboxNotice n) async {
    try {
      await gateway.markRead(tenantId, n);
      return null;
    } on DomainError catch (e) {
      // Someone else changed it: the refresh shows its current state.
      return e.code == 'VERSION_CONFLICT' ? null : e.message;
    } catch (_) {
      return 'The notice could not be updated. Try again.';
    }
  }

  Future<void> markRead(InboxNotice n) async {
    if (!n.unread || !online) return;
    final failure = await _mark(n);
    await refresh();
    error = failure ?? error;
    _emit();
  }

  Future<void> markAllRead() async {
    if (!online) return;
    String? failure;
    for (final n in notices.where((n) => n.unread).toList()) {
      failure = await _mark(n);
      if (failure != null) break;
    }
    await refresh();
    error = failure ?? error;
    _emit();
  }
}

/// The bell with an unread badge; [onOpen] shows the inbox.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final InboxController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final n = controller.unread;
      return Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        child: IconButton(
          tooltip: n == 0
              ? 'Notifications, none unread'
              : 'Notifications, $n unread',
          onPressed: onOpen,
          icon: Icon(
            n > 0 ? Icons.notifications : Icons.notifications_none,
            size: 20,
          ),
        ),
      );
    },
  );
}

/// The shell's bell: opens the inbox beside the command bar; a reminder opens
/// its engagement in Governance & Audit.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(inboxControllerProvider);
    if (c == null) {
      return const IconButton(
        tooltip: 'Notifications are unavailable until you sign in',
        onPressed: null,
        icon: Icon(Icons.notifications_none, size: 20),
      );
    }
    return NotificationBellButton(
      controller: c,
      onOpen: () {
        unawaited(c.refresh());
        final router = GoRouter.of(context);
        showDialog<void>(
          context: context,
          barrierColor: Colors.black12,
          builder: (dialog) => Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 64, right: 16),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: 420,
                  child: InboxPanel(
                    controller: c,
                    onOpenEngagement: (id) {
                      Navigator.of(dialog).pop();
                      router.go('/governance/audit?engagement=$id');
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _when(DateTime l) {
  const months = [
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
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.day} ${months[l.month - 1]} ${two(l.hour)}:${two(l.minute)}';
}

/// The newest notices with unread styling and mark-as-read.
class InboxPanel extends StatelessWidget {
  const InboxPanel({
    super.key,
    required this.controller,
    required this.onOpenEngagement,
    this.displayTime = _local,
  });
  final InboxController controller;
  final void Function(String engagementId) onOpenEngagement;

  /// Converts a notice time for display (local time; tests pin it).
  final DateTime Function(DateTime) displayTime;

  static DateTime _local(DateTime t) => t.toLocal();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, theme = Theme.of(context);
      final colors = context.jentraColors;
      return JentraPanel(
        semanticsLabel: 'Notifications',
        padding: const EdgeInsets.all(JentraSpacing.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: JentraSpacing.x2,
              children: [
                Text('Notifications', style: theme.textTheme.titleLarge),
                TextButton(
                  onPressed: c.unread == 0 || c.busy || !c.online
                      ? null
                      : c.markAllRead,
                  child: const Text('Mark all read'),
                ),
              ],
            ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.status != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: JentraSpacing.x2),
                child: Text(c.status!),
              ),
            if (c.error != null)
              Semantics(
                liveRegion: true,
                child: Text(c.error!, style: TextStyle(color: colors.danger)),
              ),
            if (c.online && !c.busy && c.notices.isEmpty && c.error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: JentraSpacing.x4),
                child: Text(
                  'You are all caught up.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final n in c.notices)
                    Semantics(
                      button: true,
                      label:
                          '${n.unread ? 'Unread notice' : 'Notice'}: ${n.title}',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          JentraRadii.control,
                        ),
                        onTap: () async {
                          await c.markRead(n);
                          final id = n.engagementId;
                          if (id != null) onOpenEngagement(id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: JentraSpacing.x2,
                            horizontal: JentraSpacing.x1,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: JentraSpacing.x2,
                                  right: JentraSpacing.x2,
                                ),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: n.unread
                                      ? colors.action
                                      : Colors.transparent,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n.title,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: n.unread
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                    ),
                                    Text(
                                      n.body,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    Text(
                                      _when(displayTime(n.createdAt)),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (n.engagementId != null)
                                Icon(
                                  Icons.chevron_right,
                                  color: colors.textSecondary,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
