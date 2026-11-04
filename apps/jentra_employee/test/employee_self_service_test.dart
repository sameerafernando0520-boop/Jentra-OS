import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_self_service.dart';
import 'package:jentra_employee/src/data/employee_workplace_time.dart';
import 'package:jentra_employee/src/employee_controller.dart';
import 'package:jentra_employee/src/employee_self_service_controller.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';

import 'support/employee_fixture.dart';
import 'support/employee_self_fixture.dart';

const _rpc = 'employee_case_command';
Map<String, Object?> _case() => {
  'p_action': 'create',
  'p_payload': {
    'id': selfRecordId,
    'category': 'general',
    'subject': 'PRIVATE_CASE_SUBJECT',
    'body': 'PRIVATE_CASE_BODY',
  },
};

class _FailStore extends FixtureStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Synthetic storage failure');
}

class _AuthErrorGateway extends FixtureGateway {
  final events = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get actorChanges => events.stream;
  @override
  Future<void> close() async {
    await events.close();
    await super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureStore store;
  late SelfGateway gateway;
  late EmployeeIdentity? current;
  late EmployeeSelfServiceController controller;
  var now = DateTime.utc(2026, 10, 26);
  setUp(() {
    store = FixtureStore();
    gateway = SelfGateway();
    current = selfIdentity;
    now = DateTime.utc(2026, 10, 26);
    controller = EmployeeSelfServiceController(
      gateway: gateway,
      store: store,
      currentIdentity: () => current,
      now: () => now,
    );
  });
  tearDown(() => controller.dispose());

  test('all service pages parse exact own scope and retain decimal payroll strings', () {
    for (final service in EmployeeService.values) {
      final page = parseEmployeeServicePage(
        {
          ...selfEnvelope(),
          'items': [serviceRow(service)],
          'next_cursor': null,
        },
        selfIdentity,
        service,
      );
      expect(page.items.single.id, selfRecordId);
    }
    expect(serviceRow(EmployeeService.payslips)['net'], '90000.000000');
  });
  test('foreign envelope/row, duplicate IDs, malformed components and unfenced foreign notices fail closed', () {
    for (final service in EmployeeService.values) {
      expect(
        () => parseEmployeeServicePage(
          {
            ...selfEnvelope(),
            'employee_id': selfSecondId,
            'items': [serviceRow(service)],
          },
          selfIdentity,
          service,
        ),
        throwsFormatException,
      );
      expect(
        () => parseEmployeeServicePage(
          {
            ...selfEnvelope(),
            'items': [
              {...serviceRow(service), 'employee_id': selfSecondId},
            ],
          },
          selfIdentity,
          service,
        ),
        throwsFormatException,
      );
      expect(
        () => parseEmployeeServicePage(
          {
            ...selfEnvelope(),
            'items': [serviceRow(service), serviceRow(service)],
          },
          selfIdentity,
          service,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => validateEmployeeServiceRecord(
        EmployeeServiceRecord({
          ...serviceRow(EmployeeService.payslips),
          'lines': [
            {'code': 'BASIC', 'amount': double.nan},
          ],
        }),
        EmployeeService.payslips,
        selfIdentity,
        detail: true,
      ),
      throwsFormatException,
    );
    expect(
      () => parseEmployeeServicePage(
        {
          ...selfEnvelope(),
          'items': [
            {
              ...serviceRow(EmployeeService.inbox),
              'recipient_id': selfSecondId,
            },
          ],
        },
        selfIdentity,
        EmployeeService.inbox,
      ),
      throwsFormatException,
    );
  });
  test('late page and balance completions cannot restore revoked or superseded state', () async {
    final page = Completer<EmployeeServicePage>();
    gateway.onPage = (_, _, _) => page.future;
    final loading = controller.load(EmployeeService.cases);
    current = null;
    controller.synchronize();
    page.complete(servicePage(EmployeeService.cases));
    await loading;
    expect(controller.pages, isEmpty);
    expect(controller.loading, isEmpty);
    current = selfIdentity;
    final first = Completer<EmployeeLeaveBalance>();
    gateway.onBalance = (id, date) async => date == '2026-10-27'
        ? await first.future
        : EmployeeLeaveBalance(
            policyId: id,
            asOf: date,
            availableSeconds: 20,
            reservedSeconds: 0,
            version: 2,
          );
    final earlier = controller.loadBalance(selfRecordId, '2026-10-27');
    await controller.loadBalance(selfRecordId, '2026-10-28');
    first.complete(
      const EmployeeLeaveBalance(
        policyId: selfRecordId,
        asOf: '2026-10-27',
        availableSeconds: 10,
        reservedSeconds: 0,
        version: 1,
      ),
    );
    expect(await earlier, isNull);
    expect(controller.balances[selfRecordId]!.asOf, '2026-10-28');
  });
  test(
    'background calls safely stop rather than emit unhandled identity errors',
    () async {
      current = null;
      await controller.load(EmployeeService.cases);
      await controller.restorePending();
      expect(await controller.submit(_rpc, _case()), isFalse);
      expect(
        await controller.loadDetail(EmployeeService.cases, selfRecordId),
        isNull,
      );
      expect(gateway.sends, 0);
    },
  );
  test(
    'detail cache separates services and hides stale content while refreshing',
    () async {
      await controller.loadDetail(EmployeeService.cases, selfRecordId);
      await controller.loadDetail(EmployeeService.payslips, selfRecordId);
      expect(
        controller
            .detailFor(EmployeeService.cases, selfRecordId)!
            .values['subject'],
        'HR question',
      );
      expect(
        controller
            .detailFor(EmployeeService.payslips, selfRecordId)!
            .values['net'],
        '90000.000000',
      );

      final earlier = Completer<EmployeeServiceRecord>();
      final later = Completer<EmployeeServiceRecord>();
      var reads = 0;
      gateway.onDetail = (_, _) => ++reads == 1 ? earlier.future : later.future;
      final firstRead = controller.loadDetail(
        EmployeeService.cases,
        selfRecordId,
      );
      expect(controller.detailFor(EmployeeService.cases, selfRecordId), isNull);
      expect(
        controller.detailFor(EmployeeService.payslips, selfRecordId),
        isNotNull,
      );
      final secondRead = controller.loadDetail(
        EmployeeService.cases,
        selfRecordId,
      );
      later.complete(
        EmployeeServiceRecord({
          ...serviceRow(EmployeeService.cases),
          'version': 3,
          'subject': 'Current HR question',
        }),
      );
      await secondRead;
      earlier.complete(
        EmployeeServiceRecord({
          ...serviceRow(EmployeeService.cases),
          'version': 2,
          'subject': 'Superseded question',
        }),
      );
      expect(await firstRead, isNull);
      expect(
        controller
            .detailFor(EmployeeService.cases, selfRecordId)!
            .values['subject'],
        'Current HR question',
      );
    },
  );
  test('secure write/readback happens before command and request body is deeply immutable', () async {
    gateway.onCommand = (identity, rpc, parameters) async {
      expect(
        store.values.values.any((wire) => wire.contains('PRIVATE_CASE_BODY')),
        isTrue,
      );
      expect(
        () => selfMap(parameters['p_payload'])['body'] = 'changed',
        returnsNormally,
      );
      expect(
        () => (parameters['p_payload']! as Map)['body'] = 'changed',
        throwsUnsupportedError,
      );
      return serviceReceipt(identity, rpc, parameters);
    };
    expect(await controller.submit(_rpc, _case()), isTrue);
    expect(gateway.sends, 1);
    expect(controller.pending, isNull);
    expect(controller.confirmed, isTrue);
    final failing = EmployeeSelfServiceController(
      gateway: gateway,
      store: _FailStore(),
      currentIdentity: () => current,
    );
    expect(await failing.submit(_rpc, _case()), isFalse);
    expect(gateway.sends, 1);
    failing.dispose();
  });
  test('uncertain result survives restart with exact IDs and later endpoint rejection cannot erase it', () async {
    gateway.onCommand = (_, _, _) async =>
        throw const EmployeeFailure('UNCERTAIN_RESULT', 'Synthetic timeout');
    expect(await controller.submit(_rpc, _case()), isFalse);
    final first = jsonEncode(gateway.sent);
    controller.dispose();
    controller = EmployeeSelfServiceController(
      gateway: gateway,
      store: store,
      currentIdentity: () => current,
      now: () => now,
    );
    await controller.restorePending();
    gateway.onCommand = (_, _, _) async => throw const EmployeeFailure(
      'FEATURE_NOT_INSTALLED',
      'Endpoint changed',
    );
    expect(await controller.reconcile(), isFalse);
    expect(jsonEncode(gateway.sent), first);
    expect(controller.pending, isNotNull);
    expect(await controller.submit(_rpc, _case()), isFalse);
    expect(gateway.sends, 2);
    gateway.onCommand = null;
    expect(await controller.reconcile(), isTrue);
    expect(controller.pending, isNull);
  });
  test('expiry erases sensitive body but keeps original opaque IDs and blocks unverified absence', () async {
    gateway.onCommand = (_, _, _) async =>
        throw const EmployeeFailure('UNCERTAIN_RESULT', 'Synthetic timeout');
    await controller.submit(_rpc, _case());
    final commandId = controller.pending!.commandId;
    now = now.add(const Duration(hours: 23));
    await controller.restorePending();
    expect(controller.pending!.receiptOnly, isTrue);
    expect(controller.pending!.commandId, commandId);
    expect(
      store.values.values.any(
        (wire) =>
            wire.contains('PRIVATE_CASE_BODY') ||
            wire.contains('PRIVATE_CASE_SUBJECT'),
      ),
      isFalse,
    );
    expect(await controller.reconcile(), isFalse);
    expect(controller.pending, isNotNull);
    expect(gateway.sends, 1);
    gateway.lookup = const EmployeeReceiptLookup(
      receipt: null,
      abandoned: true,
    );
    expect(await controller.reconcile(), isFalse);
    expect(controller.pending, isNull);
    expect(controller.notApplied, isTrue);
    expect(controller.confirmed, isFalse);
  });
  test('identity-change privacy barrier erases body and cannot replay the redacted command', () async {
    gateway.onCommand = (_, _, _) async =>
        throw const EmployeeFailure('UNCERTAIN_RESULT', 'Synthetic timeout');
    await controller.submit(_rpc, _case());
    await controller.protectPendingForIdentityChange();
    expect(
      store.values.values.any((wire) => wire.contains('PRIVATE_CASE_BODY')),
      isFalse,
    );
    await controller.restorePending();
    expect(controller.pending!.receiptOnly, isTrue);
    await controller.reconcile();
    expect(gateway.sends, 1);
  });
  test('receipt and cancellation fence require exact original scope/RPC/command/target', () {
    final lookup = {
      ...selfEnvelope(),
      'command_id': selfCommandId,
      'request_id': selfRecordId,
      'rpc': _rpc,
      'abandoned': true,
      'receipt': null,
    };
    expect(
      parseEmployeeReceiptLookup(
        lookup,
        selfIdentity,
        _rpc,
        selfCommandId,
        selfRecordId,
      ).abandoned,
      isTrue,
    );
    for (final field in [
      'employee_id',
      'branch_id',
      'command_id',
      'request_id',
      'rpc',
    ]) {
      expect(
        () => parseEmployeeReceiptLookup(
          {...lookup, field: selfSecondId},
          selfIdentity,
          _rpc,
          selfCommandId,
          selfRecordId,
        ),
        throwsFormatException,
      );
    }
    final params = {'p_command_id': selfCommandId, ..._case()};
    expect(
      () => validateEmployeeCommandReceipt(
        {...serviceReceipt(selfIdentity, _rpc, params), 'version': 2},
        selfIdentity,
        _rpc,
        params,
      ),
      throwsFormatException,
    );
    expect(
      () => validateEmployeeCommandParameters(_rpc, {
        ...params,
        'p_employee_id': fixtureEmployee,
      }),
      throwsFormatException,
    );
  });
  test('named workplace zones reject DST gaps/repeats and show correct cross-date instant', () {
    final colombo = employeeWorkplaceInstant(
      DateTime(2026, 10, 26, 9),
      'Asia/Colombo',
    );
    expect(colombo.utc, DateTime.utc(2026, 10, 26, 3, 30));
    expect(colombo.offsetSeconds, 19800);
    expect(
      () => employeeWorkplaceInstant(
        DateTime(2026, 3, 8, 2, 30),
        'America/New_York',
      ),
      throwsA(isA<EmployeeFailure>()),
    );
    expect(
      () => employeeWorkplaceInstant(
        DateTime(2026, 11, 1, 1, 30),
        'America/New_York',
      ),
      throwsA(isA<EmployeeFailure>()),
    );
    final wall = employeeWorkplaceTime(
      DateTime.utc(2026, 10, 25, 23),
      'Asia/Colombo',
    );
    expect(wall.day, 26);
    expect(wall.hour, 4);
    expect(wall.minute, 30);
  });
  test('document chooser masks private state then saves only after same-owner fresh authorization', () async {
    final exporter = TestDocumentExporter();
    controller.dispose();
    controller = EmployeeSelfServiceController(
      gateway: gateway,
      store: store,
      currentIdentity: () => current,
      documentExporter: exporter,
    );
    exporter.onChooser = () async {
      current = null;
      controller.synchronize();
      scheduleMicrotask(() {
        current = selfIdentity;
        controller.synchronize();
      });
    };
    expect(
      await controller.saveDocument(
        EmployeeServiceRecord(serviceRow(EmployeeService.documents)),
      ),
      isTrue,
    );
    expect(exporter.writes, 1);
    expect(controller.exportSaved, isTrue);
    expect(gateway.reads, greaterThan(0));
  });
  test('document lock after asynchronous reauthorization still blocks the actual write', () async {
    final exporter = TestDocumentExporter();
    controller.dispose();
    controller = EmployeeSelfServiceController(
      gateway: gateway,
      store: store,
      currentIdentity: () => current,
      documentExporter: exporter,
    );
    exporter.afterAuthorization = () {
      controller.invalidateExports();
      current = null;
      controller.synchronize();
    };
    expect(
      await controller.saveDocument(
        EmployeeServiceRecord(serviceRow(EmployeeService.documents)),
      ),
      isFalse,
    );
    expect(exporter.writes, 0);
    expect(controller.exportSaved, isFalse);
  });

  test('document save denies switched identity, new publication and expired return lease', () async {
    final exporter = TestDocumentExporter();
    controller.dispose();
    controller = EmployeeSelfServiceController(
      gateway: gateway,
      store: store,
      currentIdentity: () => current,
      documentExporter: exporter,
      exportReturnTimeout: const Duration(milliseconds: 15),
    );
    exporter.onChooser = () async {
      current = null;
      controller.synchronize();
      current = const EmployeeIdentity(
        workspace: fixtureWorkspace,
        actorId: fixtureActor,
        employeeId: selfSecondId,
        displayName: 'Other',
      );
      controller.synchronize();
    };
    expect(
      await controller.saveDocument(
        EmployeeServiceRecord(serviceRow(EmployeeService.documents)),
      ),
      isFalse,
    );
    current = selfIdentity;
    controller.synchronize();
    exporter.onChooser = null;
    gateway.onPage = (_, _, _) async => EmployeeServicePage([
      EmployeeServiceRecord({
        ...serviceRow(EmployeeService.documents),
        'publication_version': 4,
      }),
    ], null);
    expect(
      await controller.saveDocument(
        EmployeeServiceRecord(serviceRow(EmployeeService.documents)),
      ),
      isFalse,
    );
    gateway.onPage = null;
    exporter.onChooser = () async {
      current = null;
      controller.synchronize();
    };
    expect(
      await controller.saveDocument(
        EmployeeServiceRecord(serviceRow(EmployeeService.documents)),
      ),
      isFalse,
    );
    expect(exporter.writes, 0);
  });
  test('auth stream errors mask private state without unhandled provider text or remote logout', () async {
    final authGateway = _AuthErrorGateway();
    final app = EmployeeController(
      gateway: authGateway,
      draftStore: EmployeeDraftStore(FixtureStore()),
    );
    await app.start();
    expect(app.phase, EmployeePhase.ready);
    authGateway.events.addError(
      StateError('private callback https://example.test/?code=do-not-display'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(app.phase, EmployeePhase.locked);
    expect(app.identity, isNull);
    expect(app.error!.code, 'SIGN_IN_FAILED');
    expect(app.error!.message, isNot(contains('do-not-display')));
    expect(authGateway.actorId, fixtureActor);
    await app.resume();
    expect(app.phase, EmployeePhase.ready);
    app.dispose();
    await authGateway.close();
  });
}
