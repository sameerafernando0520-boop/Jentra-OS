import 'package:test/test.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'support/landed_extension_fixture.dart';

void main() {
  test('large six-place held and consumed amounts conserve exact total', () {
    final input = landedInput(), evidence = landedEvidence();
    LandedExtensionProtocol.validateInput(input);
    LandedExtensionProtocol.validateEvidence(evidence, input);
    expect(LandedExtensionProtocol.decimal(evidence['amount']).toDecimalString(), '9007199254740.123456');
    (evidence['legs'] as List).first['value'] = '6004799503160.082305';
    expect(() => LandedExtensionProtocol.validateEvidence(evidence, input), throwsFormatException);
  });
  test('substituted manual weights and numeric money fail closed', () {
    final input = landedInput(), evidence = landedEvidence();
    (evidence['receipts'] as List).first['weight'] = '2';
    expect(() => LandedExtensionProtocol.validateEvidence(evidence, input), throwsFormatException);
    input['total_amount'] = 0.1;
    expect(() => LandedExtensionProtocol.validateInput(input), throwsFormatException);
  });
  test('linked corrections cannot change immutable allocation inputs', () {
    final input = <String, Object?>{'id': landedId, 'correction_of': landedReceipt, 'document_date': '2026-09-29',
      'reference': 'CORRECTION', 'reason': 'Correct original charge', 'total_amount': '0'};
    LandedExtensionProtocol.validateInput(input);
    input['basis_mode'] = 'quantity';
    expect(() => LandedExtensionProtocol.validateInput(input), throwsFormatException);
  });
  test('duplicate receipt and missing legs never produce a partial allocation', () {
    final input = landedInput(), evidence = landedEvidence();
    input['receipts'] = [...input['receipts'] as List, ...(landedInput()['receipts'] as List)];
    expect(() => LandedExtensionProtocol.validateInput(input), throwsFormatException);
    evidence['legs'] = [(evidence['legs'] as List).first];
    expect(() => LandedExtensionProtocol.validateEvidence(evidence, landedInput()), throwsFormatException);
  });
}
