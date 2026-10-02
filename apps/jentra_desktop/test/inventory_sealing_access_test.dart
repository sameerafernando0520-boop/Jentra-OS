import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';

import 'stock_count_workspace_test.dart' show Counts;
import 'disposition_workspace_test.dart' show Dispositions;
import 'transfer_sealing_access_test.dart' show PausedKeys;

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  for (final module in ['count', 'disposition']) {
    for (final change in ['disconnect', 'reconnect', 'denial', 'dispose']) {
      test(
        '$module sealing cannot dispatch after $change and retains original retry',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory()),
              keys = PausedKeys();
          final store = QuotationDraftStore(
            EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          );
          final counts = Counts(), dispositions = Dispositions();
          final count = StockCountController(
            scope: scope,
            gateway: counts,
            drafts: store,
            online: true,
            permissions: {'inventory.adjustments.post', 'inventory.cost.view'},
          );
          final disposition = DispositionController(
            scope: scope,
            gateway: dispositions,
            drafts: store,
            online: true,
            permissions: {'inventory.dispositions.post', 'inventory.cost.view'},
          );
          final dynamic c = module == 'count' ? count : disposition;
          final slot = module == 'count'
              ? StockCountController.slot
              : DispositionController.slot;
          final commands = module == 'count'
              ? counts.commands
              : dispositions.commands;
          var disposed = false;
          try {
            await c.initialize();
            c.form = <String, Object?>{
              'id': 'original-$module',
              'version': 7,
              'status': 'draft',
              'document_date': '2026-09-30',
              'reason': 'Original exact revision',
              'warehouse_id': 'w',
              'offset_account_id': 'expense',
              'lines': <Map<String, Object?>>[
                {
                  'line_id': 'l',
                  'product_id': 'p',
                  'unit_id': 'unit',
                  'tracking_mode': 'none',
                  'counted_quantity': '1.000001',
                  'empty_unit_cost': '0',
                  'quantity': '1.000001',
                  'conversion_numerator': '1',
                  'conversion_denominator': '1',
                  'serial_ids': <String>[],
                },
              ],
            };
            final Future<void> sending = c.act('save');
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
            expect(commands, isEmpty);
            final saved = await store.load(scope, slot);
            expect(saved!.pending, isNotNull);
            final original = saved.pending!.envelope.toJson((v) => v);
            expect(original['expected_entity_version'], 7);
            if (!disposed) {
              c.dispose();
              disposed = true;
            }
            final dynamic fresh = module == 'count'
                ? StockCountController(
                    scope: scope,
                    gateway: counts,
                    drafts: store,
                    online: true,
                    permissions: {
                      'inventory.adjustments.post',
                      'inventory.cost.view',
                    },
                  )
                : DispositionController(
                    scope: scope,
                    gateway: dispositions,
                    drafts: store,
                    online: true,
                    permissions: {
                      'inventory.dispositions.post',
                      'inventory.cost.view',
                    },
                  );
            try {
              await fresh.initialize();
              await fresh.act('retry');
              expect(commands, hasLength(1));
              expect(commands.single.toJson((v) => v), original);
              expect((await store.load(scope, slot))!.pending, isNull);
            } finally {
              fresh.dispose();
            }
          } finally {
            if (!keys.release.isCompleted) keys.release.complete();
            if (!disposed) c.dispose();
            if (module == 'count') {
              disposition.dispose();
            } else {
              count.dispose();
            }
            await db.close();
          }
        },
      );
    }
  }
}
