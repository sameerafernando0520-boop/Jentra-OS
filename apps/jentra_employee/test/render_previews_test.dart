import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/employee_app.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_photo.dart';
import 'package:jentra_employee/src/ui/employee_theme.dart';
import 'package:jentra_employee/src/ui/sign_in_screen.dart';

import 'support/employee_fixture.dart';
import 'employee_ux_features_test.dart' show ReviewSearchGateway;
import 'employee_photo_test.dart' show fixturePhoto;

// These are current-source layout renders with labeled test fixtures. They are
// review artifacts, not golden comparisons or authenticated device acceptance.
void main() {
  setUpAll(() async {
    for (final entry in {
      'Manrope': 'Manrope-Regular.ttf',
      'IBM Plex Mono': 'IBMPlexMono-Regular.ttf',
      'Noto Sans Sinhala': 'NotoSansSinhala-Regular.ttf',
      'Noto Sans Tamil': 'NotoSansTamil-Regular.ttf',
    }.entries) {
      final font = FontLoader('packages/jentra_design_system/${entry.key}');
      font.addFont(
        rootBundle.load(
          'packages/jentra_design_system/assets/fonts/${entry.value}',
        ),
      );
      await font.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final sample in [
    (
      name: 'profile-light',
      width: 390.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'profile',
    ),
    (
      name: 'profile-photo-dark',
      width: 390.0,
      locale: 'en',
      dark: true,
      scale: 1.0,
      page: 'photo',
    ),
    (
      name: 'profile-large-si',
      width: 360.0,
      locale: 'si',
      dark: false,
      scale: 2.0,
      page: 'profile',
    ),
    (
      name: 'profile-large-ta',
      width: 360.0,
      locale: 'ta',
      dark: true,
      scale: 2.0,
      page: 'photo',
    ),
    (
      name: 'home-light-en',
      width: 390.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'home',
    ),
    (
      name: 'home-dark-en',
      width: 430.0,
      locale: 'en',
      dark: true,
      scale: 1.0,
      page: 'home',
    ),
    (
      name: 'home-large-si',
      width: 360.0,
      locale: 'si',
      dark: false,
      scale: 2.0,
      page: 'home',
    ),
    (
      name: 'home-large-ta',
      width: 360.0,
      locale: 'ta',
      dark: true,
      scale: 2.0,
      page: 'home',
    ),
    (
      name: 'leave-draft',
      width: 390.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'draft',
    ),
    (
      name: 'pay-availability',
      width: 360.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'pay',
    ),
    (
      name: 'activity',
      width: 390.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'activity',
    ),
    (
      name: 'more-dark',
      width: 390.0,
      locale: 'en',
      dark: true,
      scale: 1.0,
      page: 'more',
    ),
    (
      name: 'review-search',
      width: 390.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'search',
    ),
    (
      name: 'hr-help',
      width: 390.0,
      locale: 'en',
      dark: false,
      scale: 1.0,
      page: 'help',
    ),
    (
      name: 'shared-review',
      width: 390.0,
      locale: 'en',
      dark: true,
      scale: 1.0,
      page: 'review',
    ),
  ]) {
    testWidgets('render ${sample.name} without layout exceptions', (
      tester,
    ) async {
      tester.view.physicalSize = Size(sample.width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = sample.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = ReviewSearchGateway();
      final store = FixtureStore();
      final controller = await fixtureController(
        gateway: gateway,
        store: store,
      );
      if (sample.page == 'photo') {
        await EmployeePhotoStore(store)
            .save(controller.identity!, normalizeEmployeePhoto(fixturePhoto()));
        await controller.refresh();
      }
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      if (sample.page == 'activity') {
        await controller.saveLeaveDraft(
          EmployeeLeaveDraft(
            leaveType: 'Annual leave',
            reason: 'Family appointment',
            startDate: DateTime(2026, 10, 12),
            endDate: DateTime(2026, 10, 14),
          ),
        );
      }
      const renderKey = Key('employee-render');
      await tester.pumpWidget(
        RepaintBoundary(
          key: renderKey,
          child: EmployeeApp(
            controller: controller,
            observeLifecycle: false,
            initialLocale: Locale(sample.locale),
            initialThemeMode: sample.dark ? ThemeMode.dark : ThemeMode.light,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _readyBrand(tester);
      if (sample.page == 'profile' || sample.page == 'photo') {
        await tester.tap(find.byKey(const Key('employee-open-profile')));
        await tester.pumpAndSettle();
      } else if (sample.page == 'draft') {
        await tester.tap(find.byKey(const Key('employee-nav-leave')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Prepare a leave draft'),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Prepare a leave draft'));
        await tester.pumpAndSettle();
      } else if (sample.page == 'pay') {
        await tester.tap(find.byKey(const Key('employee-nav-more')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('employee-more-pay')),
          180,
        );
        await tester.tap(find.byKey(const Key('employee-more-pay')));
        await tester.pumpAndSettle();
        expect(
          find.text('Your payslips are not available here yet'),
          findsOneWidget,
        );
        expect(find.text('0.00'), findsNothing);
      } else if (sample.page == 'activity' || sample.page == 'more') {
        await tester.tap(find.byKey(Key('employee-nav-${sample.page}')));
        await tester.pumpAndSettle();
      } else if (sample.page == 'help') {
        await tester.tap(find.byKey(const Key('employee-nav-more')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('HR help').hitTestable(),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('HR help'));
        await tester.pumpAndSettle();
        expect(find.text('How can we help?'), findsOneWidget);
      } else if (sample.page == 'review' || sample.page == 'search') {
        await tester.tap(find.byKey(const Key('employee-open-reviews')));
        await tester.pumpAndSettle();
        if (sample.page == 'search') {
          await tester.enterText(
            find.byKey(const Key('employee-review-search')),
            'planning',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        } else {
          await tester.scrollUntilVisible(
            find.byKey(
              const Key('employee-review-10000000-0000-4000-8000-000000000006'),
            ),
            120,
            scrollable: find
                .byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                )
                .last,
          );
          await tester.tap(
            find.byKey(
              const Key('employee-review-10000000-0000-4000-8000-000000000006'),
            ),
          );
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(Scaffold).first);
      expect(MediaQuery.textScalerOf(context).scale(16), 16 * sample.scale);
      await _capture(tester, renderKey, sample.name);
      controller.lock();
    });
  }

  for (final large in [false, true]) {
    testWidgets(
      'render sign in ${large ? 'at 200 percent with keyboard' : 'at phone size'}',
      (tester) async {
        tester.view.physicalSize = Size(large ? 360 : 390, 800);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: large ? 280 : 0);
        tester.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const renderKey = Key('employee-render');
        await tester.pumpWidget(
          RepaintBoundary(
            key: renderKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: employeeTheme(Brightness.light),
              home: EmployeeSignInScreen(
                connected: true,
                busy: false,
                onSignIn: (_, _) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _readyBrand(tester);
        if (large) {
          await tester.ensureVisible(find.byKey(const Key('employee-sign-in')));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          renderKey,
          large ? 'sign-in-large-keyboard' : 'sign-in',
        );
      },
    );
  }
}

Future<void> _readyBrand(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(() async {
    for (final asset in ['jentra-mark.png', 'jentra-logo-board.png']) {
      await precacheImage(
        AssetImage('assets/brand/$asset', package: 'jentra_design_system'),
        context,
        onError: (error, stack) => fail('Brand asset did not decode: $asset'),
      );
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  // Image.memory decoding uses engine work outside the fake test clock. Wait
  // for the visible photo provider, so an empty loading circle cannot pass as
  // a rendered photo merely because an Image widget exists.
  for (final avatar in tester.widgetList<Image>(
    find.byKey(const Key('employee-avatar-image')),
  )) {
    final context = tester.element(
      find.byKey(const Key('employee-avatar-image')),
    );
    await tester.runAsync(
      () => precacheImage(
        avatar.image,
        context,
        onError: (error, stack) =>
            fail('Profile avatar did not decode: $error'),
      ),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final pixels = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final file = File(
        '../../docs/verification/employee-app/profile-ui-20261009/previews/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      pixels.dispose();
    }
  });
}
