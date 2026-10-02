import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_controller.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_screen.dart';

import 'reservation_workspace_test.dart' show Reservations, reservation;
import 'reservation_recovery_access_test.dart' show inputs;
import 'support/procurement_fakes.dart' show Keys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late Reservations gateway;
  late ReservationController c;
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
    db = JentraLocalDatabase(NativeDatabase.memory());
    gateway = Reservations();
    c = ReservationController(
      scope: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'b',
      ),
      gateway: gateway,
      drafts: QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      ),
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  for (final reconnect in [false, true]) {
    testWidgets(
      'reservation confirmation hides stale reads after ${reconnect ? 'reconnect' : 'disconnect'}',
      (t) async {
        c.form = {...reservation, ...inputs};
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ReservationWorkspace(controller: c)),
          ),
        );
        await t.tap(find.text('Release reservation'));
        await t.pumpAndSettle();
        expect(find.textContaining('9007199254.740993'), findsWidgets);
        c.setOnline(false);
        if (reconnect) c.setOnline(true);
        await t.pumpAndSettle();
        expect(find.text('Confirm release'), findsNothing);
        expect(find.textContaining('9007199254.740993'), findsNothing);
        expect(gateway.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final density in JentraDensity.values) {
        testWidgets(
          'reservation recovery ${size.width.toInt()} ${dark ? 'dark' : 'light'} ${density.name} 200 percent',
          (t) async {
            c.form = {...inputs};
            c.setOnline(false);
            t.view.physicalSize = size;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            final key = GlobalKey();
            await t.pumpWidget(
              MaterialApp(
                theme: dark
                    ? JentraTheme.dark(density: density)
                    : JentraTheme.light(density: density),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: RepaintBoundary(
                    key: key,
                    child: Scaffold(body: ReservationWorkspace(controller: c)),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(find.text('Reservation reservation'), findsOneWidget);
            expect(find.textContaining('9007199254.740993'), findsNothing);
            expect(find.textContaining('null'), findsNothing);
            await t.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '../../build/remaining-wave3/visual/reservation_recovery_${size.width.toInt()}_${dark ? 'dark' : 'light'}_${density.name}_200.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await t.scrollUntilVisible(
              find.text('Release reservation'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              t
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Release reservation'),
                  )
                  .onPressed,
              isNull,
            );
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
