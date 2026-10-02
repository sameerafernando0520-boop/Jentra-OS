import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_controller.dart';

import 'inventory_transfer_workspace_test.dart' show Transfers;
import 'support/procurement_fakes.dart' show Keys;

// Pause the real encrypted store's first key read; no Credential Manager access.
class PausedKeys extends Keys {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.read(key);
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  for (final change in ['disconnect', 'reconnect', 'denial', 'dispose']) {
    test(
      'transfer sealing survives $change without dispatching an obsolete command',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory()),
            keys = PausedKeys();
        final store = QuotationDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
        );
        final gateway = Transfers()..uncertain = false;
        final c = InventoryTransferController(
          scope: scope,
          gateway: gateway,
          drafts: store,
          online: true,
        );
        var disposed = false;
        try {
          await c.initialize();
          // A valid input-only receive form, using its public editor state.
          c.form = {
            'id': 'original-transfer',
            'operation': 'receive',
            'version': 7,
            'document_date': '2026-09-30',
            'reference': 'TR-7',
            'reason': 'Original destination receipt',
            'lines': <Map<String, Object?>>[],
          };
          final sending = c.submit();
          await keys.entered.future;
          switch (change) {
            case 'disconnect':
              c.setOnline(false);
            case 'reconnect':
              c.setOnline(false);
              c.setOnline(true);
            case 'denial':
              c.denyReadAccess();
            case 'dispose':
              c.dispose();
              disposed = true;
          }
          keys.release.complete();
          await sending;
          expect(gateway.commands, isEmpty);
          final recovery = await store.load(
            scope,
            InventoryTransferController.slot,
          );
          expect(recovery!.pending, isNotNull);
          final original = recovery.pending!.envelope.toJson((x) => x);
          expect((original['payload'] as Map)['id'], 'original-transfer');
          expect(original['expected_entity_version'], 7);
          if (!disposed) {
            c.dispose();
            disposed = true;
          }
          final fresh = InventoryTransferController(
            scope: scope,
            gateway: gateway,
            drafts: store,
            online: true,
          );
          try {
            await fresh.initialize();
            await fresh.submit();
            expect(gateway.commands, hasLength(1));
            expect(gateway.commands.single.toJson((x) => x), original);
            expect(
              await store.load(scope, InventoryTransferController.slot),
              isNull,
            );
          } finally {
            fresh.dispose();
          }
        } finally {
          if (!keys.release.isCompleted) keys.release.complete();
          if (!disposed) c.dispose();
          await db.close();
        }
      },
    );
  }
}
