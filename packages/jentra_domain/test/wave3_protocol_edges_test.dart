import 'dart:convert';
import 'package:test/test.dart';
import 'package:jentra_domain/count_partitions.dart';
import 'package:jentra_domain/disposition.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'count_partition_test.dart' show progress;
import 'disposition_test.dart' show form;
import 'support/landed_extension_fixture.dart';

Map<String, Object?> clone(Map<String, Object?> source) =>
    (jsonDecode(jsonEncode(source)) as Map).cast<String, Object?>();

void main() {
  test(
    'partition pages preserve identity order and exact cutoff through continuation',
    () {
      final input = progress(complete: false);
      final row = <String, Object?>{
        'id': 'one',
        'partition_ordinal': 1,
        'identity_count': 500,
        'status': 'approved',
        'version': 2,
        'baseline_quantity': '500',
        'counted_quantity': '499',
        'variance_quantity': '-1',
        'grand_total': '12.000001',
      };
      input.addAll({
        'items': [row],
        'next_cursor': 1,
      });
      final p = CountPartitionProgress.fromJson(input);
      expect(p.nextCursor, 1);
      expect(p.items.single['id'], 'one');
      expect(() => p.items.add(row), throwsUnsupportedError);
      for (final changes in <Map<String, Object?>>[
        {
          'items': [row, row],
        },
        {
          'items': [null],
        },
        {'items': 'partial'},
        {
          'items': [row],
          'next_cursor': 2,
        },
        {
          'items': [row],
          'next_cursor': '1',
        },
        {
          'items': [row],
          'next_cursor': 0,
        },
        for (final patch in <Map<String, Object?>>[
          {'id': ''},
          {'partition_ordinal': 0},
          {'partition_ordinal': 3},
          {'identity_count': 0},
          {'identity_count': 501},
          {'status': null},
          {'version': 0},
          {'baseline_quantity': 1},
          {'variance_quantity': 'NaN'},
        ])
          {
            'items': [
              {...row, ...patch},
            ],
            'next_cursor': null,
          },
      ]) {
        expect(
          () => CountPartitionProgress.fromJson({...input, ...changes}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'partition completeness never hides missing, cancelled or malformed evidence',
    () {
      for (final patch in <Map<String, Object?>>[
        {'id': null},
        {'cutoff_at': 'invalid'},
        {'expected_identity_count': 0},
        {'expected_identity_count': 10001},
        {'expected_identity_count': -1},
        {'expected_partition_count': 3},
        {'captured_partition_count': 3},
        {'captured_identity_count': 502},
        {'cancelled_partition_count': 1},
        {'capture_complete': 'true'},
        {'posting_complete': null},
        {'missing_partition_ordinals': null},
        {
          'missing_partition_ordinals': [0],
        },
        {
          'missing_partition_ordinals': ['2'],
        },
        {
          'missing_partition_ordinals': [3],
        },
        {'captured_partition_count': 1},
        {'capture_complete': false},
        {'baseline_quantity': '-1'},
        {'grand_total': '1.0000001'},
        {'items': List.filled(51, {})},
        {'items': [], 'next_cursor': 1},
      ]) {
        expect(
          () => CountPartitionProgress.fromJson({...progress(), ...patch}),
          throwsFormatException,
        );
      }
      final incomplete = {
        ...progress(complete: false),
        'capture_complete': false,
        'captured_partition_count': 1,
        'captured_identity_count': 500,
        'missing_partition_ordinals': [2],
      };
      expect(CountPartitionProgress.fromJson(incomplete).missingOrdinals, [2]);
      final request = countPartitionCapturePayload({
        'id': 'g',
        'warehouse_id': 'w',
        'product_id': 'p',
        'offset_account_id': 'a',
        'document_date': '2026-09-29',
        'reason': 'Physical count',
      });
      for (final patch in <Map<String, Object?>>[
        {'id': null},
        {'product_id': ''},
        {'document_date': 'invalid'},
        {'reason': 'no'},
        {'reason': 'x' * 1001},
      ]) {
        expect(
          () => countPartitionCapturePayload({...request, ...patch}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'disposition rejects malformed headers, conversions and repeated identities atomically',
    () {
      for (final patch in <Map<String, Object?>>[
        {'document_date': 'invalid'},
        {'document_date': '2026-02-30'},
        {'id': null},
        {'warehouse_id': null},
        {'offset_account_id': null},
        {'reason': 'no'},
        {'reason': 'x' * 1001},
        {'lines': null},
        {'lines': []},
      ]) {
        expect(
          () => dispositionSavePayload({...form(), ...patch}),
          throwsFormatException,
        );
      }
      for (final patch in <Map<String, Object?>>[
        {'line_id': null},
        {'product_id': null},
        {'unit_id': null},
        {'conversion_numerator': '0'},
        {'conversion_denominator': 1},
        {
          'serial_ids': ['unexpected'],
        },
        {
          'tracking_mode': 'serial',
          'quantity': '1',
          'serial_ids': [1],
        },
        {
          'tracking_mode': 'serial',
          'quantity': '501',
          'serial_ids': List.generate(501, (i) => 's$i'),
        },
      ]) {
        final input = form(), row = (input['lines'] as List).single as Map;
        row.addAll(patch);
        expect(() => dispositionSavePayload(input), throwsFormatException);
      }
      final input = form(), row = (input['lines'] as List).single as Map;
      input['lines'] = [
        row,
        {...row},
      ];
      expect(() => dispositionSavePayload(input), throwsFormatException);
      row['lot_id'] = 'lot';
      input['lines'] = [
        row,
        {...row, 'line_id': 'second'},
      ];
      expect(() => dispositionSavePayload(input), throwsFormatException);
    },
  );
  test('landed inputs retain governed basis and seal before posting', () {
    final valid = landedInput()..['basis_hash'] = landedHash;
    LandedExtensionProtocol.validateInput(valid, sealed: true);
    expect(
      LandedExtensionProtocol.payload({
        ...valid,
        'invented_cost': '99',
      }).containsKey('invented_cost'),
      false,
    );
    for (final patch in <Map<String, Object?>>[
      {'id': 'foreign'},
      {'total_amount': '-1'},
      {'reason': null},
      {'reason': 'no'},
      {'reference': ''},
      {'reference': 'r' * 141},
      {'document_date': '2026-02-30'},
      {'document_date': 1},
      {'basis_mode': 'invented'},
      {'offset_account_id': null},
      {'variance_account_id': 'bad'},
      {'receipts': null},
      {'receipts': []},
      {'receipts': List.filled(51, {})},
      {
        'receipts': [1],
      },
      {
        'receipts': [
          {'receipt_line_id': landedReceipt, 'foreign': true},
        ],
      },
      {
        'receipts': [
          {'receipt_line_id': landedReceipt, 'weight': '0'},
        ],
      },
      {'basis_hash': null},
      {'basis_hash': 'invalid'},
    ]) {
      expect(
        () => LandedExtensionProtocol.validateInput({
          ...valid,
          ...patch,
        }, sealed: true),
        throwsFormatException,
      );
    }
    LandedExtensionProtocol.validateInput({...valid, 'basis_mode': 'quantity'});
    LandedExtensionProtocol.validateInput({
      ...valid,
      'basis_mode': 'original_value',
    });
    expect(
      () => LandedExtensionProtocol.decimal('1.0000001'),
      throwsFormatException,
    );
  });
  test(
    'landed evidence rejects incomplete quantities, totals and substituted source lineage',
    () {
      for (final patch in <Map<String, Object?>>[
        {'root_id': null},
        {'basis_mode': 'other'},
        {'basis_hash': null},
        {'basis_hash': 'invalid'},
        {'receipts': []},
        {'legs': null},
        {'legs': List.filled(1001, {})},
        {'amount': '1'},
        {'total_amount': '1'},
        {'inventory_amount': '1'},
        {'transit_amount': '1'},
        {'variance_amount': '1'},
        {'document_date': '2026-09-28'},
        {'root_id': landedProduct},
        {'offset_account_id': landedProduct},
        {'variance_account_id': landedProduct},
      ]) {
        expect(
          () => LandedExtensionProtocol.validateEvidence({
            ...landedEvidence(),
            ...patch,
          }, landedInput()),
          throwsFormatException,
        );
      }
      for (final patch in <Map<String, Object?>>[
        {'held_quantity': '-1'},
        {'transit_quantity': '-1'},
        {'consumed_quantity': '-1'},
        {'received_quantity': '4'},
        {'target_allocation': '-1'},
        {'previous_allocation': '1'},
      ]) {
        final evidence = clone(landedEvidence());
        ((evidence['receipts'] as List).first as Map).addAll(patch);
        expect(
          () =>
              LandedExtensionProtocol.validateEvidence(evidence, landedInput()),
          throwsFormatException,
        );
      }
      for (final patch in <Map<String, Object?>>[
        {'kind': 'invented'},
        {'receipt_line_id': landedProduct},
        {'product_id': landedAccount},
        {'inventory_account_id': landedProduct},
        {'quantity': '-1'},
        {'quantity': '1'},
        {'value': '1'},
      ]) {
        final evidence = clone(landedEvidence());
        ((evidence['legs'] as List).first as Map).addAll(patch);
        expect(
          () =>
              LandedExtensionProtocol.validateEvidence(evidence, landedInput()),
          throwsFormatException,
        );
      }
      final evidence = clone(landedEvidence());
      evidence['receipts'] = [
        ...(evidence['receipts'] as List),
        ...(evidence['receipts'] as List),
      ];
      expect(
        () => LandedExtensionProtocol.validateEvidence(evidence, null),
        throwsFormatException,
      );
      LandedExtensionProtocol.validateEvidence(landedEvidence(), null);
      final transit = clone(landedEvidence()),
          leg = (transit['legs'] as List).first as Map;
      ((transit['receipts'] as List).first as Map).addAll(<String, Object?>{
        'held_quantity': '0',
        'transit_quantity': '2',
      });
      leg.addAll(<String, Object?>{
        'kind': 'transit',
        'transfer_id': landedId,
        'transfer_line_id': landedReceipt,
        'destination_branch_id': landedWarehouse,
      });
      transit['transit_amount'] = transit['inventory_amount'];
      transit['inventory_amount'] = '0';
      LandedExtensionProtocol.validateEvidence(transit, landedInput());
      final correction = clone(landedEvidence())
        ..['correction_of'] = landedReceipt;
      LandedExtensionProtocol.validateEvidence(correction, {
        'correction_of': landedReceipt,
        'total_amount': correction['total_amount'],
        'document_date': correction['document_date'],
      });
    },
  );
}
