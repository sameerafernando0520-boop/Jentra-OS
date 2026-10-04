import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/service/service_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_service.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/src/service_command_acknowledgement.dart';

import 'security_review_sealing_test.dart' show PausedKeys;

const scope = TenantContext(
  tenantId: '11111111-1111-4111-a111-111111111111',
  actorId: '22222222-2222-4222-a222-222222222222',
  legalEntityId: '33333333-3333-4333-a333-333333333333',
  branchId: '44444444-4444-4444-a444-444444444444',
);
const id = '55555555-5555-4555-a555-555555555555';
const customer = '66666666-6666-4666-a666-666666666666';
final equipmentInput = <String, Object?>{
  'action': 'equipment',
  'id': id,
  'reason': 'Synthetic governed equipment',
  'code': 'EQ-1',
  'name': 'Synthetic pump',
  'identity': 'SERIAL-1',
  'kind': 'customer',
  'customer_id': customer,
  'provider_id': null,
};

class ServiceFake implements ServiceRepository {
  Completer<void>? commandGate, authorizationGate, listGate, choiceGate;
  DomainError? commandFailure, authorizationFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  int reads = 0;
  Map<String, Object?>? receipt;
  @override
  Future<ServiceAuthority> authorize(TenantContext s, String cap) async {
    await authorizationGate?.future;
    if (authorizationFailure != null) throw authorizationFailure!;
    return const ServiceAuthority(
      'LKR',
      2,
      parts: false,
      billing: false,
      assets: false,
    );
  }

  @override
  Future<ServicePage<ServiceRecord>> list(
    TenantContext s,
    ServiceKind kind, {
    String? after,
    String? parent,
  }) async {
    reads++;
    await listGate?.future;
    return ServicePage([record], null);
  }

  ServiceRecord get record {
    final samples = serviceMap(
      jsonDecode(
        File(
          '../../packages/jentra_platform/test/fixtures/service_rollback_projections.json',
        ).readAsStringSync(),
      ),
    );
    final row = serviceMap(serviceMap(samples['ticket-initial'])['record']);
    return ServiceRecord.fromJson(ServiceKind.ticket, {
      ...row,
      'id': id,
      'tenant_id': scope.tenantId,
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
    });
  }

  @override
  Future<ServiceDetail> detail(
    TenantContext s,
    ServiceKind kind,
    String id, {
    String? after,
  }) async => ServiceDetail(record, [], null);
  @override
  Future<ServicePage<ServiceChoice>> choices(
    TenantContext s,
    String kind, {
    String? after,
    String? parent,
  }) async {
    await choiceGate?.future;
    return ServicePage([
      ServiceChoice.fromJson({
        'id': customer,
        'name': 'Synthetic customer',
        'version': 1,
      }),
    ], null);
  }

  @override
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    await commandGate?.future;
    if (commandFailure != null) throw commandFailure!;
    receipt = {
      'command_id': c.commandId,
      'request_id': c.commandId,
      'correlation_id': c.commandId,
      'warnings': <Object?>[],
      'entity': {
        'id': c.payload['id'],
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'kind': 'equipment',
        'status': 'active',
        'version': c.expectedEntityVersion! + 1,
      },
    };
    return receipt!;
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext s,
    String action,
    String key,
  ) async => receipt;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late PausedKeys keys;
  late EncryptedDraftRepository encrypted;
  late ServiceFake repository;
  ServiceController create() => ServiceController(
    scope: scope,
    repository: repository,
    drafts: {
      for (final a in ServiceCommands.extras.keys)
        a: serviceDraftStore(encrypted, a),
    },
    permissions: {'service.view', 'service.configure'},
    online: true,
    monitor: false,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = PausedKeys();
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
    repository = ServiceFake();
  });
  tearDown(() async => db.close());
  Future<void> input(ServiceController c) async {
    await c.initialize();
    c.form = Map.from(equipmentInput);
    c.expectedVersion = 0;
  }

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 1000 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(ready(), isTrue);
  }

  void change(ServiceController c, String mode) {
    if (mode == 'dispose') {
      c.dispose();
    } else {
      c.setOnline(false);
      if (mode == 'reconnect') c.setOnline(true);
    }
  }

  for (final mode in ['disconnect', 'reconnect', 'dispose']) {
    test(
      '$mode during encryption freezes original service envelope without dispatch',
      () async {
        final c = create();
        await input(c);
        keys.armed = true;
        final work = c.send();
        await keys.entered.future;
        change(c, mode);
        keys.release.complete();
        await work;
        expect(repository.commands, isEmpty);
        final draft = await c.drafts['equipment']!.load(scope, id);
        expect(draft?.pending, isNotNull);
        final sealed = draft!.pending!.envelope.toJson((p) => p);
        final fresh = create();
        await fresh.initialize();
        await fresh.resume(fresh.recovery.single);
        await fresh.send();
        expect(repository.commands.single.toJson((p) => p), sealed);
        expect(await fresh.drafts['equipment']!.load(scope, id), isNull);
        fresh.dispose();
        if (mode != 'dispose') c.dispose();
      },
    );
    test(
      '$mode while command is in flight durably acknowledges known response',
      () async {
        final c = create();
        await input(c);
        repository.commandGate = Completer<void>();
        final work = c.send();
        await until(() => repository.commands.isNotEmpty);
        final original = c.pending!;
        change(c, mode);
        repository.commandGate!.complete();
        await work;
        expect(await c.drafts['equipment']!.load(scope, id), isNull);
        expect(
          await ServiceCommandAcknowledgements(c.drafts['equipment']!)
              .contains(original),
          isTrue,
        );
        expect(c.confirmed, isNull);
        if (mode != 'dispose') c.dispose();
      },
    );
  }
  test(
    'late list after reconnect cannot repopulate obsolete service records',
    () async {
      final c = create();
      repository.listGate = Completer<void>();
      final work = c.initialize();
      await until(() => repository.reads > 0);
      c.setOnline(false);
      c.setOnline(true);
      repository.listGate!.complete();
      await work;
      expect(c.records, isEmpty);
      expect(c.authority, isNull);
      c.dispose();
    },
  );
  test('late begin authorization cannot reopen obsolete form', () async {
    final c = create();
    await c.initialize();
    repository.authorizationGate = Completer<void>();
    final work = c.begin('equipment');
    await Future<void>.delayed(Duration.zero);
    c.setOnline(false);
    c.setOnline(true);
    repository.authorizationGate!.complete();
    expect(await work, isFalse);
    expect(c.form, isNull);
    c.dispose();
  });
  for (final code in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'FEATURE_NOT_ENTITLED',
  ]) {
    test('fresh $code clears service records and plaintext', () async {
      final c = create();
      await input(c);
      repository.authorizationFailure = DomainError(
        code: code,
        message: 'Synthetic denied',
      );
      await c.checkAccess();
      expect(c.denied, isTrue);
      expect(c.form, isNull);
      expect(c.records, isEmpty);
      expect(c.authority, isNull);
      c.dispose();
    });
    test('late $code cannot deny replacement epoch', () async {
      final c = create();
      await c.initialize();
      repository.authorizationGate = Completer<void>();
      final work = c.checkAccess();
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      c.setOnline(true);
      repository.authorizationFailure = DomainError(
        code: code,
        message: 'Synthetic obsolete denial',
      );
      repository.authorizationGate!.complete();
      await work;
      expect(c.denied, isFalse);
      expect(c.error, isNull);
      c.dispose();
    });
    test('fresh picker $code clears service plaintext', () async {
      final c = create();
      await input(c);
      repository.authorizationFailure = DomainError(
        code: code,
        message: 'Synthetic picker denied',
      );
      await expectLater(c.choices('customer'), throwsA(isA<DomainError>()));
      expect(c.denied, isTrue);
      expect(c.form, isNull);
      expect(c.records, isEmpty);
      c.dispose();
    });
    test('late begin $code cannot deny replacement epoch', () async {
      final c = create();
      await c.initialize();
      repository.authorizationGate = Completer<void>();
      final work = c.begin('equipment');
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      c.setOnline(true);
      repository.authorizationFailure = DomainError(
        code: code,
        message: 'Synthetic obsolete begin denial',
      );
      repository.authorizationGate!.complete();
      expect(await work, isFalse);
      expect(c.denied, isFalse);
      expect(c.error, isNull);
      c.dispose();
    });
  }
}
