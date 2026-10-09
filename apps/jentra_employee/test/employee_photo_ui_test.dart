import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_photo.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_app.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'employee_photo_test.dart' show ControlledPhotoPicker, fixturePhoto;
import 'support/employee_fixture.dart';

void main() {
  testWidgets(
    'employee chooses, replaces and removes their own photo on Profile and Home',
    (tester) async {
      final gateway = FixtureGateway();
      final picker = ControlledPhotoPicker();
      final store = FixtureStore();
      final controller = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(store),
        photoPicker: picker,
        photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await controller.start();
      await tester.pumpWidget(
        EmployeeApp(controller: controller, observeLifecycle: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-open-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Make it yours'), findsOneWidget);
      expect(find.textContaining('Not shared with HR'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('employee-choose-photo')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-choose-photo')));
      picker.result.complete(fixturePhoto());
      await tester.pumpAndSettle();
      final firstPhoto = controller.profilePhoto;
      expect(firstPhoto, isNotNull);
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('employee-avatar-image')), findsOneWidget);
      expect(find.text('Change photo'), findsOneWidget);
      picker.result = Completer<Uint8List?>();
      await tester.ensureVisible(
        find.byKey(const Key('employee-choose-photo')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-choose-photo')));
      picker.result.complete(fixturePhoto(tint: 50));
      await tester.pumpAndSettle();
      expect(controller.profilePhoto, isNot(equals(firstPhoto)));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('employee-avatar-image')), findsOneWidget);
      await tester.tap(find.byKey(const Key('employee-open-profile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('employee-remove-photo')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-remove-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('employee-avatar-image')), findsNothing);
      expect(find.text('Choose a photo'), findsOneWidget);
      expect(controller.identity!.employeeId, fixtureEmployee);
      controller.lock();
    },
  );

  testWidgets(
    'gallery background destroys the private route and reopens Profile only after own access check',
    (tester) async {
      final gateway = FixtureGateway();
      final picker = ControlledPhotoPicker();
      final controller = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(FixtureStore()),
        photoPicker: picker,
        photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await controller.start();
      await tester.pumpWidget(
        EmployeeApp(controller: controller, observeLifecycle: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-open-profile')));
      await tester.pumpAndSettle();
      final originalContext = tester.element(
        find.byKey(const Key('employee-choose-photo')),
      );
      final selection = controller.chooseProfilePhoto();
      controller.background();
      await tester.pumpAndSettle();
      expect(originalContext.mounted, isFalse);
      expect(find.text('Preview employee'), findsNothing);
      expect(find.byKey(const Key('employee-avatar-image')), findsNothing);
      picker.result.complete(fixturePhoto());
      await tester.pump();
      await controller.resume();
      await selection;
      await tester.pumpAndSettle();
      expect(find.text('Make it yours'), findsOneWidget);
      expect(find.byKey(const Key('employee-avatar-image')), findsOneWidget);
      controller.lock();
    },
  );

  for (final language in ['en', 'si', 'ta']) {
    testWidgets('photo controls remain reachable at 200 percent in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = FixtureGateway();
      final store = FixtureStore();
      final controller = await fixtureController(
        gateway: gateway,
        store: store,
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await EmployeePhotoStore(store)
          .save(controller.identity!, normalizeEmployeePhoto(fixturePhoto()));
      await controller.refresh();
      await tester.pumpWidget(
        EmployeeApp(
          controller: controller,
          observeLifecycle: false,
          initialLocale: Locale(language),
          initialThemeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-open-profile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('employee-choose-photo')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('employee-choose-photo')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('employee-remove-photo')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('employee-remove-photo')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('employee-remove-photo')));
      await tester.pumpAndSettle();
      expect(controller.profilePhoto, isNull);
      expect(tester.takeException(), isNull);
      controller.lock();
    });
  }
}
