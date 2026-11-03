import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/sales_controller.dart';
import 'package:jentra_sales/src/ui/components.dart';
import 'package:jentra_sales/src/ui/field_sales_workspace.dart';
import 'package:jentra_sales/src/ui/login.dart';

import 'support/field_sales_fixture.dart';

void main() {
  for (final width in [768.0, 1024.0]) {
    testWidgets(
      'live Sales navigation remains usable in short windows at $width and 200% text',
      (tester) async {
        tester.view.physicalSize = Size(width, 360);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = FieldSalesController(
          gateway: FakeFieldSalesGateway(),
          store: MemorySalesStore(),
        );
        addTearDown(controller.dispose);
        await controller.open();
        await tester.pumpWidget(
          MaterialApp(
            theme: salesTheme(Brightness.light),
            home: FieldSalesWorkspace(controller, onLeave: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final page in ['Customers', 'Orders', 'More', 'Today']) {
          final destination = find.text(page).last;
          await tester.ensureVisible(destination);
          await tester.tap(destination.hitTestable());
          await tester.pumpAndSettle();
          expect(find.text(page), findsNWidgets(2));
          expect(tester.takeException(), isNull, reason: page);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.clear();
      },
    );
  }

  for (final (size, scale, split) in [
    (const Size(1050, 800), 1.4, false),
    (const Size(1050, 800), 1.49, false),
    (const Size(1600, 1200), 1.4, true),
  ]) {
    testWidgets(
      'Sales sign-in remains usable at ${size.width.toInt()} by ${size.height.toInt()} and ${scale * 100}% text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = SalesController(store: MemorySalesStore());
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: salesTheme(Brightness.light),
            home: SalesLogin(controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Less admin.\nMore connections.'),
          split ? findsOneWidget : findsNothing,
        );
        final signIn = find.text('Sign in to your company');
        await tester.ensureVisible(signIn);
        expect(signIn.hitTestable(), findsOneWidget);
        final preview = find.text('Explore the preview');
        await tester.ensureVisible(preview);
        await tester.pumpAndSettle();
        expect(preview.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
