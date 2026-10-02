import 'dart:convert';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/count_partitions.dart';
import 'package:jentra_platform/count_partitions.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';

import 'stock_count_workspace_test.dart' show Counts;
import 'support/procurement_fakes.dart' show Keys;

class Partitions implements CountPartitionGateway {
  bool uncertain = true;
  bool readFails = false;
  Completer<CountPartitionProgress>? readReply;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  CountPartitionProgress progress(String id, {bool rows = true}) =>
      CountPartitionProgress.fromJson({
        'id': id,
        'cutoff_at': '2026-09-29T08:00:00Z',
        'expected_identity_count': 501,
        'captured_identity_count': 501,
        'expected_partition_count': 2,
        'captured_partition_count': 2,
        'posted_partition_count': 0,
        'cancelled_partition_count': 0,
        'missing_partition_ordinals': [],
        'capture_complete': true,
        'posting_complete': false,
        'baseline_quantity': '501',
        'counted_quantity': '501',
        'variance_quantity': '0',
        'grand_total': '0',
        'items': rows
            ? [
                for (final ordinal in [1, 2])
                  {
                    'id': 'partition-$ordinal',
                    'partition_ordinal': ordinal,
                    'identity_count': ordinal == 1 ? 500 : 1,
                    'status': 'draft',
                    'version': 1,
                    'baseline_quantity': ordinal == 1 ? '500' : '1',
                    'counted_quantity': ordinal == 1 ? '500' : '1',
                    'variance_quantity': '0',
                    'grand_total': '0',
                  },
              ]
            : [],
      });
  @override
  Future<CountPartitionProgress> capture(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry captured request.',
      );
    }
    return progress(command.payload['id'] as String, rows: false);
  }

  @override
  Future<CountPartitionProgress> page(
    TenantContext scope,
    String groupId, {
    int after = 0,
    int limit = 50,
  }) async {
    if (readFails) {
      throw StateError('Connection interrupted after confirmed capture');
    }
    return readReply?.future ?? Future.value(progress(groupId));
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late StockCountController c;
  late Partitions partitions;
  late Counts counts;
  StockCountController make() => StockCountController(
    scope: scope,
    gateway: counts,
    partitionGateway: partitions,
    drafts: drafts,
    online: true,
    permissions: {'inventory.cost.view', 'inventory.adjustments.post'},
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    partitions = Partitions();
    counts = Counts();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test('uncertain shared capture survives workspace restart and confirms all partitions', () async {
    await c.initialize();
    await c.create();
    c.update('warehouse_id', 'w');
    c.update('offset_account_id', 'expense');
    c.update('reason', 'Shared physical cutoff');
    c.addProduct({
      'id': 'p',
      'name': 'Tracked paper',
      'base_unit_id': 'u',
      'tracking_mode': 'serial',
    });
    await c.capturePartitions();
    expect(c.partitionPending, isTrue);
    expect(c.editable, isFalse);
    final original = jsonEncode(partitions.commands.single.toJson((v) => v));
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.partitionPending, isTrue);
    expect(c.editable, isFalse);
    partitions.uncertain = false;
    await c.capturePartitions();
    expect(jsonEncode(partitions.commands.last.toJson((v) => v)), original);
    expect(c.partitionPending, isFalse);
    expect(c.form, isNull);
    expect(c.partitionProgress!.items, hasLength(2));
    expect(c.partitionProgress!.postingComplete, isFalse);
    c.setOnline(false);
    expect(c.partitionProgress, isNull);
    expect(
      (await drafts.load(scope, CountPartitionCaptureService.slot))!.form.keys,
      ['confirmed_group_id'],
    );
  });
  test(
    'failed group read after capture cannot issue another capture',
    () async {
      await c.initialize();
      await c.create();
      c.update('warehouse_id', 'w');
      c.update('offset_account_id', 'expense');
      c.update('reason', 'Physical cutoff');
      c.addProduct({
        'id': 'p',
        'name': 'Tracked paper',
        'base_unit_id': 'u',
        'tracking_mode': 'serial',
      });
      partitions.uncertain = false;
      partitions.readFails = true;
      await c.capturePartitions();
      expect(c.form, isNull);
      expect(c.partitionPending, isFalse);
      expect(c.partitionLocal!.form['confirmed_group_id'], isNotNull);
      await c.capturePartitions();
      expect(partitions.commands, hasLength(1));
      partitions.readFails = false;
      await c.refreshPartitions();
      expect(c.partitionProgress!.items, hasLength(2));
      partitions.readReply = Completer();
      final reading = c.refreshPartitions();
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      partitions.readReply!.complete(
        partitions.progress(
          c.partitionLocal!.form['confirmed_group_id'] as String,
        ),
      );
      await reading;
      expect(c.partitionProgress, isNull);
    },
  );
}
