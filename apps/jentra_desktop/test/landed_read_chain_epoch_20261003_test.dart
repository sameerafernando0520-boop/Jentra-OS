import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_controller.dart';

import 'landed_value_workspace_test.dart' show LandedGateway;
import 'support/procurement_fakes.dart' show Keys;

class _PausedLanded extends LandedGateway {
  final reads = <String>[];
  Completer<void>? entered, resume;
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    reads.add(resource);
    if (resource == 'receipts' && entered != null && !entered!.isCompleted) {
      entered!.complete();
      await resume!.future;
    }
    return super.options(scope, resource, after: after);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final referencesOnly in [false, true]) {
    for (final reconnect in [false, true]) {
      test(
        '${referencesOnly ? 'reference' : 'initial'} read chain stops after '
        '${reconnect ? 'reconnect' : 'disconnect'} during first read',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory());
          final gateway = _PausedLanded();
          final controller = LandedValueController(
            scope: const TenantContext(
              tenantId: 't',
              actorId: 'a',
              legalEntityId: 'e',
              branchId: 'b',
            ),
            gateway: gateway,
            drafts: QuotationDraftStore(
              EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
            ),
            online: true,
          );
          if (referencesOnly) {
            await controller.initialize();
            gateway.reads.clear();
          }
          gateway.entered = Completer();
          gateway.resume = Completer();
          final work = referencesOnly
              ? controller.references()
              : controller.initialize();
          await gateway.entered!.future;
          controller.setOnline(false);
          if (reconnect) controller.setOnline(true);
          gateway.resume!.complete();
          await work;
          expect(gateway.reads, ['receipts']);
          expect(controller.options, isEmpty);
          if (reconnect) {
            await controller.initialize();
            expect(
              controller.options.keys,
              containsAll(['receipts', 'accounts', 'posted']),
            );
          }
          controller.dispose();
          await db.close();
        },
      );
    }
  }
}
