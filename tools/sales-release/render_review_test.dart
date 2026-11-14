import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/sales_app.dart';
import 'package:jentra_sales/src/sales_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manrope = FontLoader('packages/jentra_design_system/Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      manrope.addFont(
        rootBundle.load(
          'packages/jentra_design_system/assets/fonts/Manrope-$weight.ttf',
        ),
      );
    }
    await manrope.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final item in [
    (
      name: 'login-phone-light',
      size: const Size(390, 940),
      preview: false,
      dark: false,
    ),
    (
      name: 'login-phone-dark',
      size: const Size(390, 940),
      preview: false,
      dark: true,
    ),
    (
      name: 'preview-phone',
      size: const Size(390, 940),
      preview: true,
      dark: false,
    ),
    (
      name: 'preview-wide',
      size: const Size(1440, 1000),
      preview: true,
      dark: false,
    ),
    (
      name: 'preview-short',
      size: const Size(1440, 320),
      preview: true,
      dark: false,
    ),
  ]) {
    testWidgets('render current release ${item.name}', (tester) async {
      tester.view.physicalSize = item.size;
      tester.view.devicePixelRatio = 1;
      if (item.name == 'preview-short') {
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = SalesController(store: MemorySalesStore());
      addTearDown(controller.dispose);
      if (item.dark) controller.toggleTheme();
      if (item.preview) await controller.enterPreview();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: SalesApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (!item.preview)
        expect(
          find.text(
            'Use your Jentra OS work account. Your company controls access to customers and orders.',
          ),
          findsOneWidget,
        );
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory(
          const String.fromEnvironment('SALES_REVIEW_OUTPUT'),
        );
        await output.create(recursive: true);
        await File(
          '${output.path}/${item.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
