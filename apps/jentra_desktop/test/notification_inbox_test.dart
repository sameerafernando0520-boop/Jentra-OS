import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/shell/notification_inbox.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

String uid(int n) => '96000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final tenant = uid(90);

Map<String, Object?> notice(
  int n, {
  bool unread = true,
  String type = 'assurance.reminder',
  String? aggregate = 'assurance_engagement',
  String title = 'Evidence request overdue',
  String created = '2026-10-20T07:30:00Z',
}) => {
  'id': uid(n),
  'notification_type': type,
  'title': title,
  'body': 'Treasury review: an evidence request is overdue.',
  'aggregate_type': aggregate,
  'aggregate_id': aggregate == null ? null : uid(50),
  'status': unread ? 'unread' : 'read',
  'version': 1,
  'created_at': created,
};

class FakeInbox implements NotificationInboxGateway {
  List<Map<String, Object?>> rows = [];
  final marked = <String>[];
  String? failMark;

  @override
  Future<List<InboxNotice>> latest(String tenantId, {int limit = 20}) async => [
    for (final r in rows) InboxNotice.fromJson(r),
  ];

  @override
  Future<int> unreadCount(String tenantId) async =>
      rows.where((r) => r['status'] == 'unread').length;

  @override
  Future<void> markRead(String tenantId, InboxNotice n) async {
    if (failMark != null) {
      throw DomainError(code: failMark!, message: 'Refused: $failMark');
    }
    marked.add(n.id);
    rows = [
      for (final r in rows)
        r['id'] == n.id ? {...r, 'status': 'read', 'version': 2} : r,
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeInbox gateway;
  late InboxController c;
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  setUp(() {
    gateway = FakeInbox()
      ..rows = [
        notice(1),
        notice(
          2,
          unread: false,
          type: 'wave3.due',
          aggregate: 'sales_invoice',
          title: 'Invoice due for review',
          created: '2026-10-19T09:00:00Z',
        ),
      ];
    c = InboxController(tenantId: tenant, gateway: gateway, online: true);
  });
  tearDown(() => c.dispose());

  test('refresh loads notices and the unread count', () async {
    await c.refresh();
    expect(c.notices.map((n) => n.title), [
      'Evidence request overdue',
      'Invoice due for review',
    ]);
    expect(c.unread, 1);
  });

  test('mark all read marks each unread notice once', () async {
    gateway.rows = [notice(1), notice(3), notice(4, unread: false)];
    await c.refresh();
    await c.markAllRead();
    expect(gateway.marked, [uid(1), uid(3)]);
    expect(c.unread, 0);
  });

  test('a notice that changed elsewhere refreshes the list', () async {
    await c.refresh();
    gateway.failMark = 'VERSION_CONFLICT';
    await c.markRead(c.notices.first);
    expect(c.error, isNull);
    expect(c.notices, hasLength(2));
  });

  test('offline shows nothing and explains why', () async {
    c.dispose();
    c = InboxController(tenantId: tenant, gateway: gateway, online: false);
    await c.refresh();
    expect(c.notices, isEmpty);
    expect(c.unread, 0);
    expect(c.status, 'Notifications are unavailable offline.');
  });

  test('initials come from the name, then the e-mail', () {
    expect(userInitials(name: 'Nadeesha Perera', email: 'np@x.test'), 'NP');
    expect(userInitials(name: null, email: 'kasun.silva@x.test'), 'KS');
    expect(userInitials(name: '', email: 'admin@x.test'), 'AD');
    expect(userInitials(name: null, email: null), '?');
  });

  test('initials preserve complete Unicode graphemes', () {
    expect(userInitials(name: '👩🏽‍💻 Silva'), '👩🏽‍💻S');
    expect(userInitials(name: 'A\u0301 Silva'), 'A\u0301S');
    expect(userInitials(name: '👩🏽‍💻'), '👩🏽‍💻');
    expect(userInitials(email: '👩🏽‍💻.silva@example.test'), '👩🏽‍💻S');
  });

  Future<void> pump(WidgetTester t, Widget child, {bool dark = false}) async {
    t.view.physicalSize = const Size(1024, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('the badge is hidden at zero and shows the unread count', (
    t,
  ) async {
    await c.refresh();
    await pump(t, NotificationBellButton(controller: c, onOpen: () {}));
    expect(find.text('1'), findsOneWidget);
    await c.markAllRead();
    await t.pump();
    expect(find.text('1'), findsNothing);
    expect(find.byTooltip('Notifications, none unread'), findsOneWidget);
  });

  testWidgets('opening a reminder marks it read and opens its engagement', (
    t,
  ) async {
    await c.refresh();
    String? opened;
    await pump(
      t,
      SizedBox(
        width: 520,
        child: InboxPanel(controller: c, onOpenEngagement: (id) => opened = id),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('^Unread')), findsOneWidget);
    await t.tap(find.text('Evidence request overdue'));
    await t.pumpAndSettle();
    expect(gateway.marked, [uid(1)]);
    expect(opened, uid(50));
  });

  for (final dark in [false, true]) {
    testWidgets('inbox ${dark ? 'dark' : 'light'} 200 percent', (t) async {
      await c.refresh();
      await pump(
        t,
        SizedBox(
          width: 520,
          child: InboxPanel(
            controller: c,
            onOpenEngagement: (_) {},
            displayTime: (t) => t,
          ),
        ),
        dark: dark,
      );
      await expectLater(
        find.byType(InboxPanel),
        matchesGoldenFile('goldens/inbox_${dark ? 'dark' : 'light'}_200.png'),
      );
    });
  }
}
