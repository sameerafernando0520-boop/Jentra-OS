import 'dart:convert';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/operations/notification_admin_controller.dart';

import 'support/procurement_fakes.dart' show Keys;

class Notifications implements Wave3NotificationGateway {
  bool uncertain = true;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String resource, {
    String? after,
  }) async => {'items': [], 'next_cursor': null};
  @override
  Future<Map<String, Object?>> execute(
    String operation,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry original notice command.',
      );
    }
    return operation == 'configure'
        ? {...command.payload, 'version': command.expectedEntityVersion! + 1}
        : {
            'id': command.commandId,
            'kind': command.payload['kind'],
            'as_of': command.payload['as_of'],
            'examined': 100,
            'emitted': 2,
            'has_more': true,
            'next_after': 'cursor',
          };
  }
}

class QueueDiagnostics extends Notifications implements Wave3DiagnosticGateway {
  Completer<Map<String, Object?>>? delayed;
  bool denied = false;
  @override
  Future<Map<String, Object?>> diagnostics(TenantContext scope) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access changed.',
      );
    }
    return delayed?.future ?? {'dead_letter_depth': '2'};
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase database;
  late QuotationDraftStore drafts;
  late Notifications gateway;
  late NotificationAdminController controller;
  NotificationAdminController make() => NotificationAdminController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
    permissions: {'core.roles.manage', 'finance.payments.manage'},
  );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = Notifications();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });
  test('delivery queue metadata clears on offline, late reply, revocation and disposal', () async {
    controller.dispose();
    final queue = QueueDiagnostics();
    controller = NotificationAdminController(
      scope: scope,
      gateway: queue,
      drafts: drafts,
      online: true,
      permissions: {'core.roles.manage'},
    );
    await controller.initialize();
    expect(controller.diagnosticStatus?['dead_letter_depth'], '2');
    queue.delayed = Completer<Map<String, Object?>>();
    final read = controller.refreshDiagnostics();
    await Future<void>.delayed(Duration.zero);
    controller.setOnline(false);
    queue.delayed!.complete({'dead_letter_depth': '7'});
    await read;
    expect(controller.diagnosticStatus, isNull);
    controller.setOnline(true);
    queue.delayed = null;
    await controller.initialize();
    expect(controller.diagnosticStatus?['dead_letter_depth'], '2');
    queue.denied = true;
    await controller.refreshDiagnostics();
    expect(controller.denied, true);
    expect(controller.diagnosticStatus, isNull);
  });
  test(
    'unknown subscription outcome survives restart with immutable command',
    () async {
      await controller.initialize();
      await controller.configure('recipient', 'posting');
      expect(controller.pending, isTrue);
      expect(controller.locked, isTrue);
      final original = jsonEncode(gateway.commands.single.toJson((v) => v));
      controller.dispose();
      controller = make();
      await controller.initialize();
      await controller.configure('replacement', 'due');
      expect(gateway.commands, hasLength(1));
      gateway.uncertain = false;
      await controller.retry();
      expect(jsonEncode(gateway.commands.last.toJson((v) => v)), original);
      expect(controller.pending, isFalse);
    },
  );
  test('scan continuation only advances after confirmation and stale cutoff cannot continue', () async {
    await controller.initialize();
    await controller.scan('AP', '2026-09-29');
    expect(controller.scanResult, isNull);
    expect(controller.pending, isTrue);
    gateway.uncertain = false;
    await controller.retry();
    expect(controller.scanResult!['next_after'], 'cursor');
    await controller.scan('AP', '2026-09-28', more: true);
    expect(gateway.commands, hasLength(2));
    await controller.scan('AP', '2026-09-29', more: true);
    expect(gateway.commands.last.payload['after_id'], 'cursor');
    controller.setOnline(false);
    expect(controller.scanResult, isNull);
    expect(controller.pages, isEmpty);
  });
}
