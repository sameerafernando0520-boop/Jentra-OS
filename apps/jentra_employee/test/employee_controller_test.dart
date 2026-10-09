import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'employee_gateway_test.dart' show ws, person, actor, employee, record;
import 'secure_storage_test.dart' show MemoryStore;

class Gateway implements EmployeeGateway {
  @override
  String? actorId = actor;
  @override
  Stream<String?> get actorChanges => const Stream.empty();
  bool linked = true;
  bool receipt = false;
  int sends = 0;
  int receipts = 0;
  Completer<EmployeeIdentity>? identityGate;
  EmployeePendingCommand? sent;
  EmployeeIdentity personResult = person;
  EmployeeFailure? reviewsFailure;
  EmployeeFailure executeFailure = const EmployeeFailure(
    'UNCERTAIN_RESULT',
    'Confirmation uncertain.',
  );
  EmployeeFailure? receiptFailure;
  EmployeeReviewPage reviewPage = const EmployeeReviewPage([], null);
  Completer<EmployeeReviewPage>? reviewsGate;
  int reviewReads = 0;
  bool signOutFails = false;
  DateTime linkExpiresAt = DateTime.utc(2027);
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {
    actorId = null;
    if (signOutFails) {
      throw const EmployeeFailure(
        'UNCERTAIN_RESULT',
        'Remote logout unavailable.',
      );
    }
  }

  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() async => [ws];
  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace w) async {
    if (identityGate != null) return identityGate!.future;
    if (!linked) {
      throw const EmployeeFailure('SELF_LINK_REQUIRED', 'Accept a link.');
    }
    return personResult;
  }

  @override
  Future<List<EmployeeLink>> listLinks(EmployeeWorkspace w) async => [
    EmployeeLink(
      id: record,
      employeeId: employee,
      displayName: 'Employee',
      version: 1,
      expiresAt: linkExpiresAt,
    ),
  ];
  @override
  Future<EmployeeReviewPage> listReviews(
    EmployeeIdentity i, {
    String? after,
  }) async {
    reviewReads++;
    if (reviewsFailure != null) throw reviewsFailure!;
    if (after != null && reviewsGate != null) return reviewsGate!.future;
    return reviewPage;
  }

  @override
  Future<void> execute(EmployeePendingCommand command) async {
    sends++;
    sent = command;
    throw executeFailure;
  }

  @override
  Future<bool> hasReceipt(EmployeePendingCommand command) async {
    receipts++;
    if (receiptFailure != null) throw receiptFailure!;
    return receipt;
  }
}

void main() {
  final sharedReview = EmployeeReview(
    id: record,
    status: 'reviewed',
    version: 1,
    startDate: DateTime(2026, 10, 1),
    endDateExclusive: DateTime(2026, 11, 1),
    objectives: const ['Shared objective'],
  );
  EmployeeLeaveDraft draft() => EmployeeLeaveDraft(
    leaveType: 'Annual',
    reason: 'Family',
    startDate: DateTime(2026, 10, 12),
    endDate: DateTime(2026, 10, 13),
  );
  test('accepted self required and missing link gives exact inbox', () async {
    final gateway = Gateway()..linked = false;
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
    );
    await c.start();
    expect(c.phase, EmployeePhase.linkRequired);
    expect(c.identity, isNull);
    expect(c.links.single.employeeId, employee);
    c.dispose();
  });
  test('uncertain action blocks another action and checks receipt before exact retry', () async {
    final gateway = Gateway()..linked = false;
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
    );
    await c.start();
    final link = c.links.single;
    await c.respondToLink(link, accept: true);
    expect(c.hasPendingCommand, isTrue);
    final original = gateway.sent!.envelope.commandId;
    await c.respondToLink(link, accept: false);
    expect(gateway.sends, 1);
    await c.retryPendingCommand();
    expect(gateway.receipts, greaterThan(0));
    expect(gateway.sent!.envelope.commandId, original);
    gateway.receipt = true;
    await c.reconcileCommand();
    expect(c.hasPendingCommand, isFalse);
    c.dispose();
  });
  test('secure persistence failure blocks dispatch', () async {
    final gateway = Gateway()..linked = false;
    final memory = MemoryStore()..fail = true;
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(memory),
    );
    await c.start();
    await c.respondToLink(c.links.single, accept: true);
    expect(gateway.sends, 0);
    expect(c.error?.code, 'STORAGE_UNAVAILABLE');
    c.dispose();
  });
  test(
    'background masks sensitive state and ignores delayed identity',
    () async {
      final gateway = Gateway();
      final c = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(MemoryStore()),
      );
      await c.start();
      expect(c.phase, EmployeePhase.ready);
      gateway.identityGate = Completer();
      final refresh = c.refresh();
      await Future<void>.delayed(Duration.zero);
      c.lock();
      gateway.identityGate!.complete(person);
      await refresh;
      expect(c.phase, EmployeePhase.locked);
      expect(c.identity, isNull);
      expect(c.reviews, isEmpty);
      c.dispose();
    },
  );
  test('calendar draft bounds use inclusive calendar dates', () {
    expect(
      EmployeeLeaveDraft(
        leaveType: 'Annual',
        reason: 'Family',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2027, 1, 2),
      ).validationError,
      isNotNull,
    );
  });
  test('untrusted account identity never restores a local draft', () async {
    final gateway = Gateway()
      ..personResult = const EmployeeIdentity(
        workspace: ws,
        actorId: record,
        employeeId: employee,
        displayName: 'Other',
      );
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
    );
    await c.start();
    expect(c.identity, isNull);
    expect(c.phase, EmployeePhase.chooseWorkspace);
    expect(c.error?.code, 'INVALID_RESPONSE');
    c.dispose();
  });
  test('permission loss during reviews masks names and draft', () async {
    final gateway = Gateway()
      ..reviewsFailure = const EmployeeFailure('PERMISSION_DENIED', 'Changed');
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
    );
    await c.start();
    expect(c.phase, EmployeePhase.locked);
    expect(c.identity, isNull);
    expect(c.workspace, isNull);
    expect(c.workspaces, isEmpty);
    expect(c.error?.code, 'PERMISSION_DENIED');
    c.dispose();
  });
  test('resume rechecks identity before draft restoration', () async {
    final gateway = Gateway();
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
    );
    await c.start();
    await c.saveLeaveDraft(
      EmployeeLeaveDraft(
        leaveType: 'Annual',
        reason: 'Family',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 13),
      ),
    );
    c.lock();
    expect(c.leaveDraft, isNull);
    gateway.linked = false;
    await c.resume();
    expect(c.phase, EmployeePhase.linkRequired);
    expect(c.leaveDraft, isNull);
    c.dispose();
  });
  test('link cannot dispatch after its expiry while displayed', () async {
    var now = DateTime.utc(2026, 10, 9);
    final gateway = Gateway()
      ..linked = false
      ..linkExpiresAt = now.add(const Duration(minutes: 5));
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
      now: () => now,
    );
    await c.start();
    final proposal = c.links.single;
    now = now.add(const Duration(minutes: 5));
    await c.respondToLink(proposal, accept: true);
    expect(gateway.sends, 0);
    expect(c.error?.code, 'STALE_LINK');
    c.dispose();
  });
  test('offline remote logout still masks and signs out locally', () async {
    final gateway = Gateway()..signOutFails = true;
    final memory = MemoryStore();
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(memory),
    );
    await c.start();
    await c.saveLeaveDraft(
      EmployeeLeaveDraft(
        leaveType: 'Annual',
        reason: 'Family',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 13),
      ),
    );
    await c.signOut();
    expect(c.phase, EmployeePhase.signedOut);
    expect(c.identity, isNull);
    expect(c.leaveDraft, isNull);
    expect(memory.values, isEmpty);
    expect(c.notice, contains('Server session revocation'));
    c.dispose();
  });

  testWidgets(
    'foreground authorization expiry masks all private state without an action',
    (tester) async {
      var now = DateTime.utc(2026, 10, 9);
      final gateway = Gateway()
        ..reviewPage = EmployeeReviewPage([sharedReview], record);
      final c = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(MemoryStore(), now: () => now),
        now: () => now,
      );
      await c.start();
      await c.saveLeaveDraft(draft());
      expect(c.identity, isNotNull);
      expect(c.reviews, isNotEmpty);
      now = now.add(const Duration(hours: 24));
      await tester.pump(const Duration(hours: 24));
      expect(c.phase, EmployeePhase.locked);
      expect(c.identity, isNull);
      expect(c.workspace, isNull);
      expect(c.workspaces, isEmpty);
      expect(c.reviews, isEmpty);
      expect(c.leaveDraft, isNull);
      expect(c.error?.code, 'AUTHORIZATION_EXPIRED');
      c.dispose();
    },
  );

  testWidgets(
    'late review results cannot repopulate after foreground lease expiry',
    (tester) async {
      var now = DateTime.utc(2026, 10, 9);
      final gateway = Gateway()
        ..reviewPage = EmployeeReviewPage([sharedReview], record);
      final c = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(MemoryStore(), now: () => now),
        now: () => now,
      );
      await c.start();
      gateway.reviewsGate = Completer();
      final page = c.loadMoreReviews();
      await tester.pump();
      now = now.add(const Duration(hours: 24));
      await tester.pump(const Duration(hours: 24));
      gateway.reviewsGate!.complete(
        EmployeeReviewPage([
          EmployeeReview(
            id: employee,
            status: 'reviewed',
            version: 1,
            startDate: DateTime(2026, 10, 1),
            endDateExclusive: DateTime(2026, 11, 1),
            objectives: const ['Late private objective'],
          ),
        ], null),
      );
      await page;
      expect(c.phase, EmployeePhase.locked);
      expect(c.reviews, isEmpty);
      expect(c.identity, isNull);
      c.dispose();
    },
  );

  for (final action in [
    'save',
    'discard',
    'page',
    'acknowledge',
    'reconcile',
    'retry',
  ]) {
    test('clock rollback fails closed before private $action', () async {
      var now = DateTime.utc(2026, 10, 9);
      final gateway = Gateway()
        ..reviewPage = EmployeeReviewPage([sharedReview], record);
      final c = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(MemoryStore(), now: () => now),
        now: () => now,
      );
      await c.start();
      if (action == 'reconcile' || action == 'retry') {
        await c.acknowledgeReview(sharedReview);
      }
      final beforeSends = gateway.sends;
      final beforeReads = gateway.reviewReads;
      now = now.subtract(const Duration(seconds: 1));
      switch (action) {
        case 'save':
          await c.saveLeaveDraft(draft());
          break;
        case 'discard':
          await c.discardLeaveDraft();
          break;
        case 'page':
          await c.loadMoreReviews();
          break;
        case 'acknowledge':
          await c.acknowledgeReview(sharedReview);
          break;
        case 'reconcile':
          await c.reconcileCommand();
          break;
        case 'retry':
          await c.retryPendingCommand();
          break;
      }
      expect(c.phase, EmployeePhase.locked);
      expect(c.error?.code, 'AUTHORIZATION_EXPIRED');
      expect(c.identity, isNull);
      expect(c.reviews, isEmpty);
      expect(gateway.sends, beforeSends);
      expect(gateway.reviewReads, beforeReads);
      expect(gateway.receipts, 0);
      c.dispose();
    });
  }

  for (final code in [
    'PERMISSION_DENIED',
    'SELF_LINK_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'SESSION_CHANGED',
  ]) {
    test('command access loss $code masks existing private data', () async {
      final gateway = Gateway()
        ..reviewPage = EmployeeReviewPage([sharedReview], record)
        ..executeFailure = EmployeeFailure(code, 'Access changed.');
      final store = EmployeeDraftStore(MemoryStore());
      final c = EmployeeController(gateway: gateway, draftStore: store);
      await c.start();
      await c.saveLeaveDraft(draft());
      await c.acknowledgeReview(sharedReview);
      expect(c.phase, EmployeePhase.locked);
      expect(c.identity, isNull);
      expect(c.workspace, isNull);
      expect(c.reviews, isEmpty);
      expect(c.leaveDraft, isNull);
      expect(c.error?.code, code);
      if (code == 'AUTHENTICATION_REQUIRED' || code == 'SESSION_CHANGED') {
        expect(await store.loadPending(ws, actor), isNotNull);
      }
      c.dispose();
    });
    test(
      'receipt access loss $code masks data and preserves original recovery metadata',
      () async {
        final gateway = Gateway()
          ..reviewPage = EmployeeReviewPage([sharedReview], record);
        final store = EmployeeDraftStore(MemoryStore());
        final c = EmployeeController(gateway: gateway, draftStore: store);
        await c.start();
        await c.saveLeaveDraft(draft());
        await c.acknowledgeReview(sharedReview);
        final commandId = gateway.sent!.envelope.commandId;
        gateway.receiptFailure = EmployeeFailure(code, 'Access changed.');
        await c.reconcileCommand();
        expect(c.phase, EmployeePhase.locked);
        expect(c.identity, isNull);
        expect(c.workspace, isNull);
        expect(c.reviews, isEmpty);
        expect(c.leaveDraft, isNull);
        expect(c.error?.code, code);
        expect(
          (await store.loadPending(ws, actor))!.envelope.commandId,
          commandId,
        );
        expect(gateway.sends, 1);
        c.dispose();
      },
    );
  }

  test('authorization lease rejects nonpositive or longer than 24 hours', () {
    for (final duration in [
      Duration.zero,
      const Duration(seconds: -1),
      const Duration(hours: 25),
    ]) {
      expect(
        () => EmployeeController(
          gateway: Gateway(),
          draftStore: EmployeeDraftStore(MemoryStore()),
          authorizationLease: duration,
        ),
        throwsArgumentError,
      );
    }
  });

  testWidgets('short lease timer masks even when the wall clock is frozen', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 9);
    final c = EmployeeController(
      gateway: Gateway(),
      draftStore: EmployeeDraftStore(MemoryStore()),
      now: () => now,
      authorizationLease: const Duration(minutes: 5),
    );
    await c.start();
    await tester.pump(const Duration(minutes: 5));
    expect(c.phase, EmployeePhase.locked);
    expect(c.identity, isNull);
    c.dispose();
  });

  testWidgets(
    'fresh online self revalidation renews and replaces the lease timer',
    (tester) async {
      var now = DateTime.utc(2026, 10, 9);
      final c = EmployeeController(
        gateway: Gateway(),
        draftStore: EmployeeDraftStore(MemoryStore()),
        now: () => now,
        authorizationLease: const Duration(hours: 1),
      );
      await c.start();
      now = now.add(const Duration(minutes: 50));
      await tester.pump(const Duration(minutes: 50));
      await c.refresh();
      now = now.add(const Duration(minutes: 11));
      await tester.pump(const Duration(minutes: 11));
      expect(c.phase, EmployeePhase.ready);
      now = now.add(const Duration(minutes: 49));
      await tester.pump(const Duration(minutes: 49));
      expect(c.phase, EmployeePhase.locked);
      c.dispose();
    },
  );

  test('clock rollback blocks a pending link action', () async {
    var now = DateTime.utc(2026, 10, 9);
    final gateway = Gateway()..linked = false;
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
      now: () => now,
    );
    await c.start();
    final link = c.links.single;
    now = now.subtract(const Duration(seconds: 1));
    await c.respondToLink(link, accept: true);
    expect(c.phase, EmployeePhase.locked);
    expect(c.links, isEmpty);
    expect(gateway.sends, 0);
    c.dispose();
  });

  test('wall-clock expiry blocks a private action before the scheduled callback runs', () async {
    var now = DateTime.utc(2026, 10, 9);
    final gateway = Gateway()
      ..reviewPage = EmployeeReviewPage([sharedReview], record);
    final c = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(MemoryStore()),
      now: () => now,
    );
    await c.start();
    now = now.add(const Duration(hours: 24));
    await c.acknowledgeReview(sharedReview);
    expect(c.phase, EmployeePhase.locked);
    expect(gateway.sends, 0);
    expect(c.reviews, isEmpty);
    c.dispose();
  });

  test(
    'rollback from the last valid private access also fails closed',
    () async {
      var now = DateTime.utc(2026, 10, 9);
      final c = EmployeeController(
        gateway: Gateway(),
        draftStore: EmployeeDraftStore(MemoryStore(), now: () => now),
        now: () => now,
      );
      await c.start();
      now = now.add(const Duration(minutes: 10));
      await c.saveLeaveDraft(draft());
      now = now.subtract(const Duration(seconds: 1));
      await c.discardLeaveDraft();
      expect(c.phase, EmployeePhase.locked);
      expect(c.leaveDraft, isNull);
      expect(c.error?.code, 'AUTHORIZATION_EXPIRED');
      c.dispose();
    },
  );
  testWidgets(
    'a draft restored at age 23 hours masks at its original expiry despite fresh authorization',
    (tester) async {
      var now = DateTime.utc(2026, 10, 9);
      final store = EmployeeDraftStore(MemoryStore(), now: () => now);
      await store.saveDraft(person, draft());
      now = now.add(const Duration(hours: 23));
      final gateway = Gateway()
        ..reviewPage = EmployeeReviewPage([sharedReview], record);
      final c = EmployeeController(
        gateway: gateway,
        draftStore: store,
        now: () => now,
      );
      await c.start();
      expect(c.leaveDraft, isNotNull);
      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      expect(c.phase, EmployeePhase.ready);
      expect(c.identity, isNotNull);
      expect(c.reviews, isNotEmpty);
      expect(c.leaveDraft, isNull);
      expect(gateway.sends, 0);
      c.dispose();
    },
  );
}
