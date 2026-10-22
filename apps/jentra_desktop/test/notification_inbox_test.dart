import 'dart:async';

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
    for (final r in rows.take(limit)) InboxNotice.fromJson(r),
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

class DeferredInbox extends FakeInbox {
  final reads = <Completer<List<InboxNotice>>>[];
  Completer<int>? deferredCount;
  int countCalls = 0;

  @override
  Future<List<InboxNotice>> latest(String tenantId, {int limit = 20}) {
    final request = Completer<List<InboxNotice>>();
    reads.add(request);
    return request.future;
  }

  @override
  Future<int> unreadCount(String tenantId) {
    countCalls++;
    return deferredCount?.future ?? super.unreadCount(tenantId);
  }
}

class DeferredMarkInbox extends FakeInbox {
  final submitted = <String>[];
  final writes = <Completer<void>>[];
  int latestCalls = 0;

  @override
  Future<List<InboxNotice>> latest(String tenantId, {int limit = 20}) {
    latestCalls++;
    return super.latest(tenantId, limit: limit);
  }

  @override
  Future<void> markRead(String tenantId, InboxNotice notice) async {
    submitted.add(notice.id);
    final request = Completer<void>();
    writes.add(request);
    await request.future;
    await super.markRead(tenantId, notice);
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

  test('mark loaded read marks each loaded unread notice once', () async {
    gateway.rows = [notice(1), notice(3), notice(4, unread: false)];
    await c.refresh();
    await c.markLoadedRead();
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

  test(
    'bulk read stays busy and serializes repeated bulk and single actions',
    () async {
      c.dispose();
      final deferred = DeferredMarkInbox()..rows = [notice(1), notice(2)];
      c = InboxController(tenantId: tenant, gateway: deferred, online: true);
      await c.refresh();
      final pending = c.markLoadedRead();
      expect(c.busy, isTrue);
      await c.markLoadedRead();
      await c.markRead(c.notices.first);
      expect(deferred.submitted, [uid(1)]);
      deferred.writes[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, isTrue);
      expect(deferred.submitted, [uid(1), uid(2)]);
      deferred.writes[1].complete();
      await pending;
      expect(c.busy, isFalse);
      expect(deferred.marked, [uid(1), uid(2)]);
      expect(deferred.latestCalls, 2);
      expect(c.unread, 0);
    },
  );

  test('disconnect stops a pending bulk read before further writes', () async {
    c.dispose();
    final deferred = DeferredMarkInbox()..rows = [notice(1), notice(2)];
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    await c.refresh();
    final pending = c.markLoadedRead();
    c.setOnline(false);
    deferred.writes.single.complete();
    await pending;
    expect(deferred.submitted, [uid(1)]);
    expect(deferred.latestCalls, 1);
    expect(c.notices, isEmpty);
    expect(c.unread, 0);
    expect(c.busy, isFalse);
  });

  test(
    'scope disposal stops a pending bulk read before further writes',
    () async {
      final deferred = DeferredMarkInbox()..rows = [notice(1), notice(2)];
      final previousScope = InboxController(
        tenantId: tenant,
        gateway: deferred,
        online: true,
      );
      await previousScope.refresh();
      final pending = previousScope.markLoadedRead();
      previousScope.dispose();
      deferred.writes.single.complete();
      await pending;
      expect(deferred.submitted, [uid(1)]);
      expect(deferred.latestCalls, 1);
      expect(previousScope.busy, isFalse);
    },
  );

  test('offline shows nothing and explains why', () async {
    c.dispose();
    c = InboxController(tenantId: tenant, gateway: gateway, online: false);
    await c.refresh();
    expect(c.notices, isEmpty);
    expect(c.unread, 0);
    expect(c.status, 'Notifications are unavailable offline.');
  });

  test('going offline invalidates an in-flight notice read', () async {
    c.dispose();
    final deferred = DeferredInbox();
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    final pending = c.refresh();
    c.setOnline(false);
    deferred.reads.single.complete([InboxNotice.fromJson(notice(1))]);
    await pending;
    expect(c.notices, isEmpty);
    expect(c.unread, 0);
    expect(c.busy, isFalse);
    expect(c.error, isNull);
    expect(deferred.countCalls, 0);
  });

  test('going offline invalidates an in-flight unread count', () async {
    c.dispose();
    final deferred = DeferredInbox()..deferredCount = Completer<int>();
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    final pending = c.refresh();
    deferred.reads.single.complete([InboxNotice.fromJson(notice(1))]);
    await Future<void>.value();
    expect(deferred.countCalls, 1);
    c.setOnline(false);
    deferred.deferredCount!.complete(1);
    await pending;
    expect(c.notices, isEmpty);
    expect(c.unread, 0);
    expect(c.busy, isFalse);
  });

  test('a slower earlier refresh cannot replace the newer list', () async {
    c.dispose();
    final deferred = DeferredInbox()..rows = [notice(2)];
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    final older = c.refresh();
    final newer = c.refresh();
    deferred.reads[1].complete([InboxNotice.fromJson(notice(2))]);
    await newer;
    deferred.reads[0].complete([InboxNotice.fromJson(notice(1))]);
    await older;
    expect(c.notices.map((n) => n.id), [uid(2)]);
    expect(c.unread, 1);
    expect(deferred.countCalls, 1);
    expect(c.busy, isFalse);
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
    await c.markLoadedRead();
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

  testWidgets('notice rows do not open during a pending refresh', (t) async {
    c.dispose();
    final deferred = DeferredInbox()..rows = [notice(1)];
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    final initial = c.refresh();
    deferred.reads.single.complete([InboxNotice.fromJson(notice(1))]);
    await initial;
    String? opened;
    await pump(
      t,
      SizedBox(
        width: 520,
        child: InboxPanel(controller: c, onOpenEngagement: (id) => opened = id),
      ),
    );
    final pending = c.refresh();
    await t.pump();
    final row = find.ancestor(
      of: find.text('Evidence request overdue'),
      matching: find.byType(InkWell),
    );
    expect(t.widget<InkWell>(row).onTap, isNull);
    await t.tap(find.text('Evidence request overdue'));
    expect(opened, isNull);
    expect(deferred.marked, isEmpty);
    deferred.reads.last.complete([InboxNotice.fromJson(notice(1))]);
    await pending;
    await t.pumpAndSettle();
    expect(t.widget<InkWell>(row).onTap, isNotNull);
  });

  testWidgets('notice rows do not open during a pending bulk write', (t) async {
    c.dispose();
    final deferred = DeferredMarkInbox()..rows = [notice(1)];
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    await c.refresh();
    String? opened;
    await pump(
      t,
      SizedBox(
        width: 520,
        child: InboxPanel(controller: c, onOpenEngagement: (id) => opened = id),
      ),
    );
    final pending = c.markLoadedRead();
    await t.pump();
    await t.tap(find.text('Evidence request overdue'));
    expect(opened, isNull);
    expect(deferred.submitted, [uid(1)]);
    deferred.writes.single.complete();
    await pending;
    await t.pumpAndSettle();
    expect(opened, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('dismissing a pending notice does not reopen its engagement', (
    t,
  ) async {
    c.dispose();
    final deferred = DeferredMarkInbox()..rows = [notice(1)];
    c = InboxController(tenantId: tenant, gateway: deferred, online: true);
    await c.refresh();
    String? opened;
    await pump(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialog) => Dialog(
              child: SizedBox(
                width: 520,
                child: InboxPanel(
                  controller: c,
                  onOpenEngagement: (id) {
                    opened = id;
                    Navigator.of(dialog).pop();
                  },
                ),
              ),
            ),
          ),
          child: const Text('Open inbox'),
        ),
      ),
    );
    await t.tap(find.text('Open inbox'));
    await t.pumpAndSettle();
    await t.tap(find.text('Evidence request overdue'));
    await t.pump();
    expect(deferred.submitted, [uid(1)]);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(InboxPanel), findsNothing);
    deferred.writes.single.complete();
    await t.pumpAndSettle();
    expect(opened, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'bulk read names its loaded scope and leaves older notices unread',
    (t) async {
      gateway.rows = [for (var i = 1; i <= 25; i++) notice(i)];
      await c.refresh();
      await pump(
        t,
        SizedBox(
          width: 520,
          child: InboxPanel(controller: c, onOpenEngagement: (_) {}),
        ),
      );
      expect(c.notices, hasLength(20));
      expect(c.unread, 25);
      expect(find.text('Mark all read'), findsNothing);
      expect(
        find.byTooltip('Mark unread notices in this list as read.'),
        findsOneWidget,
      );
      await t.tap(find.text('Mark loaded read'));
      await t.pumpAndSettle();
      expect(gateway.marked, [for (var i = 1; i <= 20; i++) uid(i)]);
      expect(c.unread, 5);
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Mark loaded read'),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );

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
