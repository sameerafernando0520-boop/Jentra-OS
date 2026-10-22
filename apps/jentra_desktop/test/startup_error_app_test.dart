import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/startup_error_app.dart';
import 'package:jentra_platform/jentra_platform.dart';

void main() {
  testWidgets(
    'initialization failure offers a deliberate retry at enlarged text',
    (tester) async {
      var retries = 0;
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        JentraStartupErrorApp(
          failure: RuntimeStartupFailure.initializationFailed,
          onRetry: () => retries++,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.text('Jentra OS could not start')),
        ).scale(1),
        2,
      );
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
      expect(find.text('Support code: initializationFailed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
