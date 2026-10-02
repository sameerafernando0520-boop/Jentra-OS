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
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_screen.dart';

import 'financial_statement_workspace_test.dart' show FinancialStatementFake;
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
        testWidgets('report progress and cancellation $tag', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = JentraLocalDatabase(NativeDatabase.memory());
          final c = FinancialStatementController(
            scope: const TenantContext(
              tenantId: 'tenant',
              actorId: 'actor',
              legalEntityId: 'entity',
              branchId: 'branch',
            ),
            gateway: FinancialStatementFake(),
            drafts: QuotationDraftStore(
              EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
            ),
            online: true,
          );
          addTearDown(() async {
            c.dispose();
            await db.close();
          });
          await c.initialize();
          // Synthetic presentation fixture; delayed-response tests exercise RPC ordering.
          c.busy = true;
          c.reportWait.begin();
          c.reportWait.generating();
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
                key: const Key('report-preview'),
                child: Scaffold(
                  body: FinancialStatementWorkspace(controller: c),
                ),
              ),
            ),
          );
          await tester.pump();
          Future<void> capture(String phase) async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('report-preview')),
            );
            await tester.runAsync(() async {
              final rendered = await boundary.toImage();
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              rendered.dispose();
              final file = File(
                '../../build/remaining-wave3/visual/report_${phase}_$tag.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            });
          }

          expect(find.text('Generating report'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture('waiting');
          await tester.tap(find.text('Cancel report waiting'));
          await tester.pump();
          expect(c.reportWait.cancelled, isTrue);
          expect(await c.canLeave(), isTrue);
          expect(
            find.textContaining('A dispatched request may still complete'),
            findsOneWidget,
          );
          expect(find.text('Cancel report waiting'), findsNothing);
          expect(tester.takeException(), isNull);
          await capture('cancelled');
        });
      }
    }
  }
}
