import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_mfa.dart';
import 'package:jentra_employee/src/ui/employee_mfa_panel.dart';

class _Gateway implements EmployeeMfaGateway {
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  String? actorId = 'original';
  @override
  bool isVerifiedSession = false;
  bool failVerify = false, promote = true;
  int reads = 0, enrollments = 0, verifications = 0;
  final cancelled = <String>[];
  List<EmployeeMfaFactor> available = [
    const EmployeeMfaFactor('verified', 'Authenticator'),
  ];
  Completer<void>? readGate, enrollGate, verifyGate;
  @override
  Stream<String?> get actorChanges => changes.stream;
  void changeActor(String? actor) {
    actorId = actor;
    changes.add(actor);
  }

  @override
  Future<List<EmployeeMfaFactor>> factors() async {
    reads++;
    await readGate?.future;
    return available;
  }

  @override
  Future<EmployeeMfaEnrollment> enroll() async {
    enrollments++;
    await enrollGate?.future;
    available = [
      const EmployeeMfaFactor('new-setup', 'Setup', verified: false),
    ];
    return const EmployeeMfaEnrollment('new-setup', 'SYNTHETICSETUPKEY');
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {
    cancelled.add(factorId);
    available = available.where((factor) => factor.id != factorId).toList();
  }

  @override
  Future<void> verify(String factorId, String code) async {
    verifications++;
    await verifyGate?.future;
    if (failVerify) throw StateError('Synthetic failure');
    isVerifiedSession = promote;
  }
}

void main() {
  late _Gateway gateway;
  late EmployeeMfaController controller;
  setUp(() {
    gateway = _Gateway();
    controller = EmployeeMfaController(gateway);
  });
  tearDown(() async {
    controller.dispose();
    await gateway.changes.close();
  });

  test(
    'loading factors never enrolls and hides unrelated unfinished setups',
    () async {
      gateway.available.add(
        const EmployeeMfaFactor(
          'unfinished-elsewhere',
          'Elsewhere',
          verified: false,
        ),
      );
      await controller.load();
      expect(controller.factors.map((factor) => factor.id), ['verified']);
      expect(gateway.enrollments, 0);
      expect(controller.enrollment, isNull);
    },
  );

  test('enrollment requires an explicit action after an empty verified-factor read', () async {
    gateway.available = [];
    await controller.load();
    expect(gateway.enrollments, 0);
    await controller.enroll();
    expect(gateway.enrollments, 1);
    expect(controller.enrollment?.secret, 'SYNTHETICSETUPKEY');
    expect(controller.hasPendingSetup, isTrue);
  });

  test('background clears setup key while preserving bounded original setup verification', () async {
    gateway.available = [];
    await controller.load();
    await controller.enroll();
    controller.suspend();
    expect(controller.enrollment, isNull);
    expect(controller.factors, isEmpty);
    expect(controller.selectedFactorId, isNull);
    await controller.resume();
    expect(controller.selectedFactorId, 'new-setup');
    expect(controller.enrollment, isNull);
    expect(await controller.verify('123456'), isTrue);
    expect(controller.verified, isTrue);
    expect(controller.hasPendingSetup, isFalse);
  });

  test(
    'explicit cancel removes only the current unfinished setup intent',
    () async {
      gateway.available = [];
      await controller.load();
      await controller.enroll();
      await controller.cancelSetup();
      expect(gateway.cancelled, ['new-setup']);
      expect(controller.enrollment, isNull);
      expect(controller.hasPendingSetup, isFalse);
      expect(controller.loaded, isTrue);
    },
  );

  test('invalid code never reaches the verification gateway', () async {
    await controller.load();
    expect(await controller.verify('12'), isFalse);
    expect(gateway.verifications, 0);
    expect(
      controller.error,
      'Enter the six-digit code from your authenticator.',
    );
  });

  test('successful challenge still requires an AAL2 session', () async {
    await controller.load();
    gateway.promote = false;
    expect(await controller.verify('123456'), isFalse);
    expect(controller.verified, isFalse);
    expect(controller.error, contains('verified session'));
  });

  test(
    'verification failures do not echo codes or SDK exception text',
    () async {
      await controller.load();
      gateway.failVerify = true;
      expect(await controller.verify('123456'), isFalse);
      expect(controller.error, isNot(contains('123456')));
      expect(controller.error, isNot(contains('Synthetic failure')));
      expect(controller.busy, isFalse);
    },
  );

  test(
    'overlapping verification does not dispatch a second challenge',
    () async {
      await controller.load();
      gateway.verifyGate = Completer<void>();
      final first = controller.verify('123456');
      expect(await controller.verify('654321'), isFalse);
      gateway.verifyGate!.complete();
      expect(await first, isTrue);
      expect(gateway.verifications, 1);
    },
  );

  test('late challenge cannot complete after backgrounding', () async {
    await controller.load();
    gateway.verifyGate = Completer<void>();
    final pending = controller.verify('123456');
    controller.suspend();
    gateway.verifyGate!.complete();
    expect(await pending, isFalse);
    expect(controller.verified, isFalse);
    expect(controller.enrollment, isNull);
  });

  test('late challenge cannot complete after its owner is disposed', () async {
    await controller.load();
    gateway.verifyGate = Completer<void>();
    final pending = controller.verify('123456');
    controller.dispose();
    gateway.verifyGate!.complete();
    expect(await pending, isFalse);
    // Replace the disposed owner so shared teardown remains valid.
    controller = EmployeeMfaController(gateway);
  });

  test('account change is latched even if a late auth response restores the old actor', () async {
    await controller.load();
    gateway.verifyGate = Completer<void>();
    final pending = controller.verify('123456');
    gateway.changeActor('different');
    gateway.changeActor('original');
    gateway.verifyGate!.complete();
    expect(await pending, isFalse);
    expect(controller.current, isFalse);
    expect(controller.factors, isEmpty);
  });

  test('late setup after pause never restores its key and cancels its unverified factor', () async {
    gateway.available = [];
    await controller.load();
    gateway.enrollGate = Completer<void>();
    final pending = controller.enroll();
    controller.suspend();
    gateway.enrollGate!.complete();
    await pending;
    expect(controller.enrollment, isNull);
    expect(gateway.cancelled, ['new-setup']);
  });

  testWidgets('setup expiry still clears private details after a failed code', (
    tester,
  ) async {
    gateway.available = [];
    await controller.load();
    await controller.enroll();
    gateway.failVerify = true;
    expect(await controller.verify('123456'), isFalse);
    await tester.pump(const Duration(minutes: 5));
    expect(controller.enrollment, isNull);
    expect(controller.hasPendingSetup, isFalse);
  });

  testWidgets('large-text panel setup and verification remain reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    gateway.available = [];
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: EmployeeMfaPanel(
                gateway: gateway,
                observeLifecycle: false,
                onVerified: () async {
                  completed++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.enrollments, 0);
    await tester.ensureVisible(find.byKey(const Key('employee-mfa-enroll')));
    await tester.tap(find.byKey(const Key('employee-mfa-enroll')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('employee-mfa-setup-key')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('employee-mfa-code')));
    await tester.enterText(
      find.byKey(const Key('employee-mfa-code')),
      '123456',
    );
    await tester.ensureVisible(find.byKey(const Key('employee-mfa-verify')));
    await tester.tap(find.byKey(const Key('employee-mfa-verify')));
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(find.byKey(const Key('employee-mfa-setup-key')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('panel masks codes and enrollment on lifecycle background', (
    tester,
  ) async {
    gateway.available = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmployeeMfaPanel(gateway: gateway, onVerified: () async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('employee-mfa-enroll')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('employee-mfa-code')),
      '123456',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byKey(const Key('employee-mfa-setup-key')), findsNothing);
    expect(find.byKey(const Key('employee-mfa-code')), findsNothing);
    expect(gateway.verifications, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('employee-mfa-code')),
    );
    expect(field.controller?.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'verified callback failure can be retried without a second challenge',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EmployeeMfaPanel(
                gateway: gateway,
                observeLifecycle: false,
                onVerified: () async {
                  attempts++;
                  if (attempts == 1) {
                    throw StateError('Synthetic refresh outage');
                  }
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('employee-mfa-code')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('employee-mfa-verify')));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(
        find.textContaining('Refresh employee access again'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('employee-mfa-verify')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(gateway.verifications, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
