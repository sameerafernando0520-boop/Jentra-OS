import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_controller.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_controller.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_controller.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_controller.dart';

import '../../../packages/jentra_domain/test/support/landed_extension_fixture.dart';
import 'bank_reconciliation_workspace_test.dart' show BankFake;
import 'reservation_workspace_test.dart' show Reservations, reservation;
import 'landed_value_workspace_test.dart' show LandedGateway;
import 'landed_extension_workspace_test.dart' show Landed;
import 'manual_journal_workspace_test.dart' show JournalGateway, journal;
import 'period_fx_workspace_test.dart' show PeriodFxFake;
import 'support/procurement_fakes.dart' show Keys;

class PausedKeys extends Keys {
  bool armed = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (armed && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.read(key);
  }
}

class Case {
  Case({
    required this.controller,
    required this.send,
    required this.load,
    required this.commands,
    required this.ready,
  });
  final ChangeNotifier controller;
  final Future<void> Function() send, ready;
  final Future<Map<String, Object?>?> Function() load;
  final List<CommandEnvelope<Map<String, Object?>>> commands;
  void connection(bool value) => (controller as dynamic).setOnline(value);
}

const scope = TenantContext(
  tenantId: 't',
  actorId: 'a',
  legalEntityId: 'e',
  branchId: 'b',
);
const landedScope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);

Case make(String name, EncryptedDraftRepository repository, dynamic gateway) {
  final drafts = QuotationDraftStore(repository);
  Future<Map<String, Object?>?> load(String slot) async =>
      (await drafts.load(scope, slot))?.pending?.envelope.toJson((x) => x);
  switch (name) {
    case 'bank':
      final c = BankReconciliationController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        capabilities: {'finance.view', 'finance.bank.reconcile'},
        online: true,
      );
      return Case(
        controller: c,
        send: () => c.execute('match'),
        load: () => load(BankReconciliationController.slot),
        commands: gateway.commands,
        ready: () async {
          await c.initialize();
          if (c.local == null) {
            c.form = {
              'bank_id': 'bank',
              'posting_date': '2026-09-21',
              'reason': 'Recorded match',
              'statement_line_ids': ['s1'],
              'journal_line_ids': ['j1'],
            };
          }
        },
      );
    case 'reservation':
      final c = ReservationController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      return Case(
        controller: c,
        send: c.release,
        load: () => load(ReservationController.slot),
        commands: gateway.commands,
        ready: () async {
          await c.initialize();
          if (c.local == null) {
            c.form = {
              ...reservation,
              'reason': 'Original manual release',
              'mode': 'manual',
            };
          }
        },
      );
    case 'single landed':
      final c = LandedValueController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      return Case(
        controller: c,
        send: c.post,
        load: () => load(LandedValueController.slot),
        commands: gateway.commands,
        ready: () async {
          await c.initialize();
          if (c.local == null) {
            c.form = {
              'id': 'new-reversal',
              'reverse_of': 'original-landed',
              'status': 'draft',
              'document_date': '2026-09-21',
              'reason': 'Original landed correction',
              'reference': 'LV-42',
            };
          }
        },
      );
    case 'multi landed':
      final store = LandedExtensionDraftStore(repository);
      final c = LandedExtensionController(
        scope: landedScope,
        gateway: gateway,
        drafts: store,
        online: true,
      );
      return Case(
        controller: c,
        send: c.post,
        load: () async => (await store.store.load(
          landedScope,
          landedId,
        ))?.pending?.envelope.toJson((x) => x),
        commands: gateway.commands,
        ready: () async {
          await c.initialize();
          if (c.recovered.isNotEmpty) {
            await c.restore(c.recovered.single);
          } else {
            c.form = {...landedInput(), 'basis_hash': landedHash};
            c.preview = landedEvidence();
          }
        },
      );
    case 'manual journal':
      final c = ManualJournalController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        permissions: {'finance.view', 'finance.journals.post'},
        online: true,
      );
      return Case(
        controller: c,
        send: () => c.act('post'),
        load: () => load(ManualJournalController.slot),
        commands: gateway.commands,
        ready: () async {
          await c.initialize();
          if (c.local == null) {
            c.form = journal(status: 'approved');
          }
        },
      );
    case 'period FX':
      final c = PeriodFxController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        capabilities: {'finance.view', 'finance.period.close'},
        online: true,
      );
      return Case(
        controller: c,
        send: () => c.execute('soft_lock'),
        load: () => load(PeriodFxController.slot),
        commands: gateway.commands,
        ready: () async {
          await c.initialize();
          if (c.local == null) {
            c.form = {
              'period_id': 'period',
              'reason': 'Original governed close',
              'as_of': '2026-09-21',
            };
          }
        },
      );
    default:
      throw StateError(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in [
    'bank',
    'reservation',
    'single landed',
    'multi landed',
    'manual journal',
    'period FX',
  ]) {
    for (final change in ['disconnect', 'reconnect', 'dispose']) {
      test(
        '$name seals original request across $change without obsolete dispatch',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory()),
              keys = PausedKeys();
          final repository = EncryptedDraftRepository(
            db,
            DraftCipher(keyStore: keys),
          );
          final dynamic gateway = switch (name) {
            'bank' => BankFake(),
            'reservation' => Reservations(),
            'single landed' => LandedGateway(),
            'multi landed' => Landed()..uncertain = false,
            'manual journal' => JournalGateway(),
            _ => PeriodFxFake(),
          };
          final original = make(name, repository, gateway);
          var disposed = false;
          try {
            await original.ready();
            keys.armed = true;
            final sending = original.send();
            await keys.entered.future.timeout(const Duration(seconds: 5));
            if (change == 'dispose') {
              original.controller.dispose();
              disposed = true;
            } else {
              original.connection(false);
              if (change == 'reconnect') original.connection(true);
            }
            keys.release.complete();
            await sending;
            expect(original.commands, isEmpty);
            final sealed = await original.load();
            expect(
              sealed,
              isNotNull,
              reason: 'Original encrypted request must remain retryable.',
            );
            if (!disposed) {
              original.controller.dispose();
              disposed = true;
            }
            final fresh = make(name, repository, gateway);
            try {
              await fresh.ready();
              await fresh.send();
              expect(fresh.commands, hasLength(1));
              expect(fresh.commands.single.toJson((x) => x), sealed);
              expect(await fresh.load(), isNull);
            } finally {
              fresh.controller.dispose();
            }
          } finally {
            if (!keys.release.isCompleted) keys.release.complete();
            if (!disposed) original.controller.dispose();
            await db.close();
          }
        },
      );
    }
  }
}
