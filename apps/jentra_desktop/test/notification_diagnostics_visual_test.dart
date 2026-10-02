import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/operations/notification_admin_controller.dart';
import 'package:jentra_desktop/src/features/operations/notification_admin_screen.dart';

import 'notification_admin_workspace_test.dart' show QueueDiagnostics;
import 'support/procurement_fakes.dart' show Keys;

void main() {
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
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        final tag =
            '${size.width.toInt()}_${dark ? 'dark' : 'light'}_${compact ? 'compact' : 'comfortable'}_200';
        testWidgets('queue diagnostics $tag status, access and semantics', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final db = JentraLocalDatabase(NativeDatabase.memory());
            final c = NotificationAdminController(
              scope: const TenantContext(
                tenantId: 't',
                actorId: 'a',
                legalEntityId: 'e',
                branchId: 'b',
              ),
              gateway: QueueDiagnostics(),
              drafts: QuotationDraftStore(
                EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
              ),
              online: true,
              permissions: {'core.roles.manage'},
            );
            addTearDown(() async {
              c.dispose();
              await db.close();
            });
            await c.initialize();
            final theme = dark ? JentraTheme.dark() : JentraTheme.light();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme.copyWith(
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const Key('queue-preview'),
                  child: Scaffold(
                    body: NotificationAdminWorkspace(controller: c),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final status = find.text('Undelivered events awaiting review: 2');
            expect(status, findsOneWidget);
            expect(
              tester.getSemantics(status).flagsCollection.isLiveRegion,
              isTrue,
            );
            final refresh = find.widgetWithText(
              TextButton,
              'Refresh delivery queue status',
            );
            expect(tester.widget<TextButton>(refresh).onPressed, isNotNull);
            await tester.tap(refresh);
            await tester.pumpAndSettle();
            expect(status, findsOneWidget);
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('queue-preview')),
            );
            await tester.runAsync(() async {
              final rendered = await boundary.toImage();
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              rendered.dispose();
              final file = File(
                '../../build/remaining-wave3/visual/queue_diagnostics_$tag.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            });
            c.setOnline(false);
            await tester.pumpAndSettle();
            expect(status, findsNothing);
            expect(tester.widget<TextButton>(refresh).onPressed, isNull);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
