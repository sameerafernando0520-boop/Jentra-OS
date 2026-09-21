import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_controller.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'support/procurement_fakes.dart' show Keys;

const reservation = <String, Object?>{
  'id': 'reservation',
  'version': 8,
  'status': 'active',
  'document_number': 'SO-0042',
  'product_name': 'Recycled office paper',
  'warehouse_name': 'Colombo warehouse',
  'base_quantity': '9007199254.740993',
  'expires_at': '2026-09-19T18:00:00Z',
};

class Reservations implements ReservationGateway {
  final reportCalls = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> asOf(
    TenantContext scope,
    String instant, {
    String? after,
  }) async {
    reportCalls.add({'instant': instant, 'after': after});
    return {
      'items': [reservation],
      'next_cursor': after == null ? 'page2' : null,
      'coverage_start': '2026-09-18T00:00:00Z',
      'as_of': instant,
    };
  }

  String? failure;
  bool refreshFails = false;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final filters = <String>[];
  @override
  Future<Map<String, Object?>> queue(
    TenantContext scope, {
    required String filter,
    String? after,
  }) async {
    filters.add(filter);
    if (refreshFails) throw StateError('offline');
    return {
      'items': [reservation],
    };
  }

  @override
  Future<Map<String, Object?>> history(
    TenantContext scope,
    String id, {
    int? beforeVersion,
  }) async => {
    'coverage_start': '2026-09-18T00:00:00Z',
    'items': [
      {
        'version': 8,
        'recorded_at': '2026-09-18T12:00:00Z',
        'baseline': false,
        'snapshot': {'status': 'active', 'base_quantity': '9007199254.740993'},
      },
    ],
  };
  @override
  Future<Map<String, Object?>> release(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return {
      ...reservation,
      'version': 9,
      'status': 'released',
      'release_reason': command.payload['reason'],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late Reservations gateway;
  late ReservationController c;
  ReservationController make({TenantContext context = scope}) =>
      ReservationController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = Reservations();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> open() async {
    await c.initialize();
    await c.open(reservation);
    c.update('reason', 'Customer requested a later delivery');
  }

  test('dated report pins its cutoff while loading next page', () async {
    c.reportInstant = '2026-09-19T12:00:00Z';
    await c.loadReport();
    c.reportInstant = '2026-09-19T13:00:00Z';
    await c.loadReport(more: true);
    expect(gateway.reportCalls.last, {
      'instant': '2026-09-19T12:00:00Z',
      'after': 'page2',
    });
    expect(c.reportRows.length, 2);
    expect(gateway.commands, isEmpty);
    expect(c.reportRows.first['base_quantity'], '9007199254.740993');
  });
  test('dated report rejects timezone-less and impossible dates', () async {
    for (final value in ['2026-09-19T12:00:00', '2026-02-30T12:00:00Z']) {
      c.reportInstant = value;
      await c.loadReport();
      expect(c.error, contains('valid UTC'));
    }
    expect(gateway.reportCalls, isEmpty);
  });

  test('release sends only identity mode reason and pinned version', () async {
    await open();
    await c.release();
    expect(gateway.commands.single.payload, {
      'id': 'reservation',
      'mode': 'manual',
      'reason': 'Customer requested a later delivery',
    });
    expect(gateway.commands.single.expectedEntityVersion, 8);
    expect(c.form!['status'], 'released');
    expect(c.error, isNull);
  });
  test(
    'uncertain restart retains exact sealed request and blocks discard',
    () async {
      await open();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.release();
      final original = jsonEncode(gateway.commands.single.toJson((v) => v));
      expect(c.local?.pending, isNotNull);
      await c.close();
      expect(c.form, isNotNull);
      c.dispose();
      c = make();
      await c.initialize();
      c.update('reason', 'Changed reason');
      c.update('mode', 'expired');
      gateway.failure = null;
      await c.release();
      expect(jsonEncode(gateway.commands.last.toJson((v) => v)), original);
    },
  );
  test(
    'definite conflict preserves reason without retrying stale edit',
    () async {
      await open();
      gateway.failure = 'VERSION_CONFLICT';
      await c.release();
      expect(c.local?.pending, isNull);
      expect(c.form!['reason'], 'Customer requested a later delivery');
      gateway.failure = null;
      await c.release();
      expect(gateway.commands.length, 1);
      await c.close();
      await c.refresh();
      await c.open({...reservation, 'version': 9});
      c.update('reason', 'Reviewed changed reservation');
      await c.release();
      expect(gateway.commands.last.expectedEntityVersion, 9);
    },
  );
  test('confirmed result survives refresh failure', () async {
    await open();
    gateway.refreshFails = true;
    await c.release();
    expect(c.form!['status'], 'released');
    expect(c.message, contains('confirmed'));
    expect(c.error, contains('Release confirmed'));
    expect(c.local?.pending, isNull);
  });
  test(
    'confirmed release banner cannot carry over to another reservation',
    () async {
      await open();
      await c.release();
      expect(c.message, contains('confirmed'));
      await c.close();
      await c.open({...reservation, 'id': 'another'});
      expect(c.message, isNull);
      expect(c.form!['status'], 'active');
    },
  );
  test('offline reason persists and does not execute', () async {
    await open();
    c.setOnline(false);
    await c.release();
    expect(gateway.commands, isEmpty);
    expect(await c.canLeave(), true);
    c.dispose();
    c = make();
    c.setOnline(false);
    await c.initialize();
    expect(c.form!['reason'], 'Customer requested a later delivery');
  });
  test('draft is isolated across branch scope', () async {
    await open();
    await c.save();
    c.dispose();
    c = make(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await c.initialize();
    expect(c.form, isNull);
  });
  test('expired filter selects corresponding release mode', () async {
    await c.initialize();
    await c.refresh(selection: 'expired');
    await c.open(reservation);
    expect(c.form!['mode'], 'expired');
    expect(gateway.filters.last, 'expired');
  });
  test('navigation requires reservation permission', () {
    expect(
      visibleJentraDestinations(
        {},
      ).any((d) => d.path == '/inventory/reservations'),
      false,
    );
    expect(
      visibleJentraDestinations({
        'inventory.reservations.manage',
      }).any((d) => d.path == '/inventory/reservations'),
      true,
    );
  });
  for (final dark in [false, true]) {
    testWidgets(
      'dated reservation queue ${dark ? 'dark' : 'light'} 200 percent',
      (tester) async {
        await c.initialize();
        c.reportInstant = '2026-09-19T12:00:00Z';
        await c.loadReport();
        tester.view.physicalSize = const Size(1024, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: ReservationWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/reservation_report_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        expect(find.text('Release reservation'), findsNothing);
      },
    );
    testWidgets('reservation ${dark ? 'dark' : 'light'} 200 percent review', (
      tester,
    ) async {
      await open();
      await c.history();
      tester.view.physicalSize = const Size(1024, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: ReservationWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/reservation_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      await tester.tap(find.text('Release reservation'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      expect(find.text('Confirm release'), findsOneWidget);
      await tester.tap(find.text('Confirm release'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(gateway.commands.length, 1);
    });
  }
  testWidgets('minimum desktop permits scrolling to release action', (
    tester,
  ) async {
    await open();
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: ReservationWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Release reservation'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
