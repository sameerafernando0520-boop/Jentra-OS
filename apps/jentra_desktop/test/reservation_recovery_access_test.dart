import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_controller.dart';

import 'reservation_workspace_test.dart' show Reservations, reservation;
import 'support/procurement_fakes.dart' show Keys;

const scope = TenantContext(
  tenantId: 't',
  actorId: 'a',
  legalEntityId: 'e',
  branchId: 'b',
);
const inputs = {
  'id': 'reservation',
  'version': 8,
  'status': 'active',
  'reason': 'Original release reason',
  'mode': 'manual',
};

class _Gateway extends Reservations {
  DomainError? readFailure;
  Completer<void>? readGate;
  Future<void> Function()? onRelease;
  @override
  Future<Map<String, Object?>> queue(
    TenantContext s, {
    required String filter,
    String? after,
  }) async {
    final failure = readFailure;
    await readGate?.future;
    if (failure != null) throw failure;
    return super.queue(s, filter: filter, after: after);
  }

  @override
  Future<Map<String, Object?>> release(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await super.release(command);
    await onRelease?.call();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore store;
  late _Gateway gateway;
  late ReservationController c;
  ReservationController make({bool online = true}) => ReservationController(
    scope: scope,
    gateway: gateway,
    drafts: store,
    online: online,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = _Gateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> open() async {
    await c.initialize();
    await c.open(reservation);
    c.update('reason', inputs['reason'] as String);
    await c.save();
  }

  for (final reconnect in [false, true]) {
    test(
      'stale reservation selection cannot open after ${reconnect ? 'reconnect' : 'disconnect'}',
      () async {
        await c.initialize();
        final selected = c.items.single;
        c.setOnline(false);
        if (reconnect) c.setOnline(true);
        await c.open(selected);
        expect(c.form, isNull);
        expect(await store.load(scope, ReservationController.slot), isNull);
      },
    );
  }
  test('reservation selection uses current queue evidence instead of copied labels', () async {
    await c.initialize();
    await c.open({...reservation, 'product_name': 'Obsolete copied product'});
    expect(c.form!['product_name'], reservation['product_name']);
  });

  test('reservation recovery persists inputs without current labels, quantity or expiry', () async {
    await open();
    expect((await store.load(scope, ReservationController.slot))!.form, inputs);
    c.setOnline(false);
    expect(c.form, inputs);
    expect(c.items, isEmpty);
    expect(c.events, isEmpty);
  });
  test('legacy encrypted reservation strips read evidence before offline presentation', () async {
    await store.save(scope, ReservationController.slot, {
      ...reservation,
      ...inputs,
    }, expectedVersion: 8);
    c.dispose();
    c = make(online: false);
    await c.initialize();
    expect(c.form, inputs);
    expect(c.local!.form, inputs);
    expect(gateway.commands, isEmpty);
  });
  for (final code in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
  ]) {
    test(
      'current $code clears reservation labels while preserving exact release inputs',
      () async {
        await open();
        gateway.readFailure = DomainError(
          code: code,
          message: 'Current authority is required.',
        );
        await c.refresh();
        expect(c.accessDenied, true);
        expect(c.form, inputs);
        expect(c.items, isEmpty);
        expect(
          (await store.load(scope, ReservationController.slot))!.form,
          inputs,
        );
      },
    );
  }
  test('confirmed release followed by current denial clears evidence without resealing', () async {
    await open();
    gateway.readFailure = const DomainError(
      code: 'MFA_REQUIRED',
      message: 'Current MFA is required.',
    );
    await c.release();
    expect(gateway.commands, hasLength(1));
    expect(c.accessDenied, true);
    expect(c.message, contains('confirmed'));
    final saved = await store.load(scope, ReservationController.slot);
    expect(saved!.pending, isNull);
    expect(saved.form, {...inputs, 'status': 'released', 'version': 9});
    expect(c.form, saved.form);
  });
  test('obsolete post-confirm refresh failure cannot deny or annotate a new connection', () async {
    await open();
    gateway.readGate = Completer();
    gateway.readFailure = const DomainError(
      code: 'PERMISSION_DENIED',
      message: 'Old authority',
    );
    final sending = c.release();
    for (var i = 0; i < 500 && gateway.commands.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(gateway.commands, hasLength(1));
    for (
      var i = 0;
      i < 500 && !(c.message?.contains('confirmed') ?? false);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    c.setOnline(false);
    c.setOnline(true);
    gateway.readGate!.complete();
    await sending;
    expect(c.accessDenied, false);
    expect(c.error, isNull);
    expect(c.form, {...inputs, 'status': 'released', 'version': 9});
    expect(
      (await store.load(scope, ReservationController.slot))!.pending,
      isNull,
    );
  });
  test('failed local confirmation exposes storage guidance and retains identical retry', () async {
    await open();
    gateway.onRelease = () => db.customStatement('PRAGMA query_only = ON');
    await c.release();
    expect(c.error, contains('LOCAL_STORAGE_FULL'));
    expect(c.message, isNull);
    final original = gateway.commands.single.toJson((x) => x);
    await db.customStatement('PRAGMA query_only = OFF');
    gateway.onRelease = null;
    expect(
      (await store.load(
        scope,
        ReservationController.slot,
      ))!.pending!.envelope.toJson((x) => x),
      original,
    );
    await c.release();
    expect(
      jsonEncode(gateway.commands.last.toJson((x) => x)),
      jsonEncode(original),
    );
    expect(
      (await store.load(scope, ReservationController.slot))!.pending,
      isNull,
    );
  });
}
