import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_controller.dart';

import 'reservation_workspace_test.dart' show Reservations, reservation;
import 'support/procurement_fakes.dart' show Keys;

class DelayedReservations extends Reservations {
  Completer<Map<String, Object?>>? pageReply, releaseReply;
  bool called = false, denied = false;
  @override
  Future<Map<String, Object?>> queue(
    TenantContext scope, {
    required String filter,
    String? after,
  }) async {
    called = true;
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access removed.',
      );
    }
    return pageReply?.future ??
        super.queue(scope, filter: filter, after: after);
  }

  @override
  Future<Map<String, Object?>> release(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    called = true;
    return releaseReply?.future ?? super.release(command);
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    legalEntityId: 'e',
    branchId: 'b',
    actorId: 'a',
  );
  Future<(ReservationController, DelayedReservations, QuotationDraftStore)>
  setup() async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    final drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    final gateway = DelayedReservations();
    final c = ReservationController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    return (c, gateway, drafts);
  }

  test('reservation queue cannot restore an old connection and denial preserves encrypted inputs', () async {
    final (c, g, drafts) = await setup();
    await drafts.save(scope, ReservationController.slot, {
      ...reservation,
      'reason': 'Retained release inputs',
    });
    g.pageReply = Completer();
    final loading = c.initialize();
    for (var i = 0; i < 1000 && !g.called; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(g.called, isTrue);
    c.setOnline(false);
    c.setOnline(true);
    g.pageReply!.complete({
      'items': [reservation],
    });
    await loading;
    expect(c.items, isEmpty);
    g.pageReply = null;
    g.denied = true;
    await c.initialize();
    expect(c.accessDenied, isTrue);
    expect(c.locked, isTrue);
    expect(
      (await drafts.load(scope, ReservationController.slot))!.form['reason'],
      'Retained release inputs',
    );
    g.denied = false;
    await c.initialize();
    expect(c.accessDenied, isFalse);
  });
  test(
    'late release confirmation is durable without restoring offline evidence',
    () async {
      final (c, g, drafts) = await setup();
      await c.initialize();
      await c.open(reservation);
      c.update('reason', 'Release remaining demand');
      g.called = false;
      g.releaseReply = Completer();
      final releasing = c.release();
      for (var i = 0; i < 1000 && !g.called; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(g.called, isTrue);
      c.setOnline(false);
      g.releaseReply!.complete({
        ...reservation,
        'version': 9,
        'status': 'released',
      });
      await releasing;
      expect(c.form, isNull);
      expect(c.items, isEmpty);
      final confirmed = (await drafts.load(scope, ReservationController.slot))!;
      expect(confirmed.pending, isNull);
      expect(confirmed.form['status'], 'released');
    },
  );
}
