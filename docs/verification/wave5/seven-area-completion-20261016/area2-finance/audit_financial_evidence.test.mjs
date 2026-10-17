import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { auditFinancialEvidence, ratio, units } from './audit_financial_evidence.mjs';

const base = 'docs/verification/wave5/genuine-finance-finance-20261013-r5-1791894738890/';
const load = name => JSON.parse(readFileSync(base + name));
const inputs = () => [load('statement-profit_loss.json'), load('statement-balance_sheet.json'), load('ratios-and-classification.json')];

test('captured statements reproduce all nine ratio values and six base operands exactly', () => {
  const value = auditFinancialEvidence(...inputs());
  assert.equal(value.ratioArithmeticRows.length, 9);
  assert.equal(value.statementOperandsReproduced, 6);
  assert.equal(value.actualUserPostingProved, false);
  assert.equal(value.canonicalStatementHashesRecomputed, false);
  assert.equal(value.classifiedOperandsRequireAccountClassificationManifest, true);
});
test('half-unit ties round away from zero without binary floating point', () => {
  assert.equal(ratio('1.000001', '2').exactValue, '0.500001');
  assert.equal(ratio('-1.000001', '2').exactValue, '-0.500001');
  assert.equal(ratio('9007199254740993.000001', '1').exactValue, '9007199254740993.000001');
});
test('unavailable denominators remain distinct from measured zero', () => {
  assert.deepEqual(ratio('3', '0'), { exactValue: null, unavailableReason: 'ZERO_DENOMINATOR' });
  assert.deepEqual(ratio('3', '-1'), { exactValue: null, unavailableReason: 'NEGATIVE_DENOMINATOR' });
  assert.deepEqual(ratio('0', '2'), { exactValue: '0.000000', unavailableReason: null });
});
test('decimal parser rejects binary numbers, exponent notation, overprecision and unbounded values', () => {
  for (const value of [0.1, '1e3', '1.0000001', '01', '9'.repeat(41), 'NaN', null]) assert.throws(() => units(value));
});
test('statement scope, currency, period and cutoff mismatches are rejected', () => {
  for (const key of ['tenant_id', 'legal_entity_id', 'branch_id', 'period_id', 'period_start', 'period_end', 'as_of', 'base_currency_code']) {
    const values = inputs();
    values[1].summary[key] = 'changed';
    assert.throws(() => auditFinancialEvidence(...values), key);
  }
});
test('statement arithmetic mutation cannot be masked by plausible ratio values', () => {
  const values = inputs();
  values[0].summary.net_profit = '1787.999997';
  assert.throws(() => auditFinancialEvidence(...values));
});
test('tampered output, operands, missing formulas and source hashes fail', () => {
  for (const alter of [
    p => { p.ratios.ratios.quick_ratio.exactValue = '85.191893'; },
    p => { p.ratios.ratios.assets_to_equity.numerator = '1'; },
    p => { delete p.ratios.ratios.current_ratio; },
    p => { p.ratios.profitLossHash = 'c'.repeat(64); },
    p => { p.ratios.classificationId = null; },
  ]) {
    const values = inputs();
    alter(values[2]);
    assert.throws(() => auditFinancialEvidence(...values));
  }
});
test('source provenance cannot be upgraded to actual posting', () => {
  const values = inputs();
  values[0].sourceFixture = 'actual user posting';
  assert.throws(() => auditFinancialEvidence(...values));
});
