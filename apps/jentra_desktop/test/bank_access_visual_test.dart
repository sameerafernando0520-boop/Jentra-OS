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
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_screen.dart';

import 'bank_access_interaction_test.dart' show InteractiveBank;
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
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        final tag =
            '${size.width.toInt()}_${dark ? "dark" : "light"}_${compact ? "compact" : "comfortable"}_200';
        testWidgets(
          'bank denied preview at $tag requires keyboard verification',
          (t) async {
            final db = JentraLocalDatabase(NativeDatabase.memory());
            final gateway = InteractiveBank();
            final c = BankReconciliationController(
              scope: scope,
              gateway: gateway,
              drafts: QuotationDraftStore(
                EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
              ),
              online: true,
              capabilities: const {
                'finance.view',
                'finance.bank.import',
                'finance.bank.reconcile',
              },
            );
            final boundary = GlobalKey();
            t.view.physicalSize = size;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            try {
              await c.initialize();
              await c.selectBank('bank');
              c.setOnline(false);
              c.setOnline(true);
              await t.pumpWidget(
                MaterialApp(
                  theme: (dark ? JentraTheme.dark() : JentraTheme.light())
                      .copyWith(
                        visualDensity: compact
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                      ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true,
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Scaffold(
                    body: BankReconciliationWorkspace(controller: c),
                  ),
                ),
              );
              await t.pumpAndSettle();
              expect(find.textContaining('Operating bank'), findsNothing);
              expect(find.textContaining('0.000001'), findsNothing);
              final verify = find.widgetWithText(TextButton, 'Verify access');
              expect(verify, findsOneWidget);
              expect(t.widget<TextButton>(verify).onPressed, isNotNull);
              expect(t.takeException(), isNull);
              await t.runAsync(() async {
                final render =
                    boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                final img = await render.toImage();
                final bytes = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                img.dispose();
                final f = File(
                  '../../build/remaining-wave3/visual/bank_access_$tag.png',
                );
                await f.parent.create(recursive: true);
                await f.writeAsBytes(bytes!.buffer.asUint8List());
              });
              await t.sendKeyEvent(LogicalKeyboardKey.tab);
              await t.pump();
              await t.runAsync(() async {
                await t.sendKeyEvent(LogicalKeyboardKey.enter);
                while (c.busy) {
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                }
              });
              await t.pumpAndSettle();
              expect(c.verified, isTrue);
              expect(c.pages, isNotEmpty);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox.shrink());
              c.dispose();
              await db.close();
            }
          },
        );
      }
    }
  }
}
