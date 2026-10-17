import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export function units(value) {
  assert.equal(typeof value, 'string', 'Financial values must be decimal strings');
  assert.match(value, /^-?(0|[1-9][0-9]{0,39})(\.[0-9]{1,6})?$/);
  const negative = value.startsWith('-');
  const [whole, fraction = ''] = (negative ? value.slice(1) : value).split('.');
  return (BigInt(whole) * 1000000n + BigInt(fraction.padEnd(6, '0'))) * (negative ? -1n : 1n);
}

function decimal(value) {
  const magnitude = value < 0n ? -value : value;
  return `${value < 0n ? '-' : ''}${magnitude / 1000000n}.${String(magnitude % 1000000n).padStart(6, '0')}`;
}

export function ratio(numerator, denominator) {
  const n = units(numerator), d = units(denominator);
  if (d === 0n) return { exactValue: null, unavailableReason: 'ZERO_DENOMINATOR' };
  if (d < 0n) return { exactValue: null, unavailableReason: 'NEGATIVE_DENOMINATOR' };
  const scaled = (n < 0n ? -n : n) * 1000000n;
  const rounded = scaled / d + ((scaled % d) * 2n >= d ? 1n : 0n);
  return { exactValue: decimal(rounded * (n < 0n ? -1n : 1n)), unavailableReason: null };
}

export function auditFinancialEvidence(profitLoss, balanceSheet, publication) {
  const pl = profitLoss.summary, bs = balanceSheet.summary;
  assert.equal(profitLoss.sourceFixture, 'administrative synthetic');
  assert.equal(balanceSheet.sourceFixture, 'administrative synthetic');
  assert.equal(pl.kind, 'profit_loss');
  assert.equal(bs.kind, 'balance_sheet');
  for (const key of ['tenant_id', 'legal_entity_id', 'branch_id', 'period_id', 'period_start', 'period_end', 'as_of', 'base_currency_code']) {
    assert.equal(pl[key], bs[key], `Statement basis mismatch: ${key}`);
  }
  assert.equal(units(pl.revenue) - units(pl.expenses), units(pl.net_profit));
  const equity = units(bs.equity) + units(bs.current_earnings);
  assert.equal(units(bs.assets), units(bs.liabilities) + equity);
  const expectedBase = {
    net_profit_margin: [units(pl.net_profit), units(pl.revenue)],
    liabilities_to_assets: [units(bs.liabilities), units(bs.assets)],
    assets_to_equity: [units(bs.assets), equity],
  };
  const arithmeticRows = [];
  for (const [name, bundle] of [['ratiosBase', publication.ratiosBase], ['ratios', publication.ratios]]) {
    assert.equal(bundle.contractRevision, 1);
    assert.equal(bundle.formulaVersion, 1);
    assert.equal(bundle.profitLossId, profitLoss.id);
    assert.equal(bundle.balanceSheetId, balanceSheet.id);
    assert.deepEqual(bundle.scope, { tenantId: pl.tenant_id, legalEntityId: pl.legal_entity_id, branchId: pl.branch_id });
    assert.equal(bundle.currency, pl.base_currency_code);
    assert.equal(bundle.periodStart, pl.period_start);
    assert.equal(bundle.asOf, pl.as_of);
    assert.match(bundle.profitLossHash, /^[a-f0-9]{64}$/);
    assert.match(bundle.balanceSheetHash, /^[a-f0-9]{64}$/);
    const names = [...Object.keys(expectedBase), ...(name === 'ratios' ? ['current_ratio', 'quick_ratio', 'gross_profit_margin'] : [])].sort();
    assert.deepEqual(Object.keys(bundle.ratios).sort(), names);
    assert.equal(bundle.classificationId, name === 'ratios' ? publication.classificationId : null);
    for (const [code, row] of Object.entries(bundle.ratios)) {
      assert.deepEqual(Object.keys(row).sort(), ['denominator', 'exactValue', 'numerator', 'unavailableReason']);
      assert.deepEqual({ exactValue: row.exactValue, unavailableReason: row.unavailableReason }, ratio(row.numerator, row.denominator), `Ratio mismatch: ${name}/${code}`);
      if (expectedBase[code]) {
        assert.deepEqual([units(row.numerator), units(row.denominator)], expectedBase[code], `Statement operands mismatch: ${code}`);
      }
      arithmeticRows.push({ bundle: name, code, ...row, operandsReproducedFromStatementSummaries: code in expectedBase });
    }
  }
  assert.equal(publication.ratiosBase.profitLossHash, publication.ratios.profitLossHash);
  assert.equal(publication.ratiosBase.balanceSheetHash, publication.ratios.balanceSheetHash);
  return {
    kind: 'offline-retained-financial-evidence-reproduction',
    passed: true,
    sourceObservedAt: { profitLoss: pl.generated_at, balanceSheet: bs.generated_at },
    administrativeSyntheticSource: true,
    actualUserPostingProved: false,
    ratioArithmeticRows: arithmeticRows,
    statementOperandsReproduced: 6,
    classifiedOperandsRequireAccountClassificationManifest: true,
    canonicalStatementHashesRecomputed: false,
    liveQueries: 0,
    acceptanceDecisionsAdded: 0,
    limitations: [
      'The retained statement files contain summaries, not full canonical account-level publications.',
      'Classified formula arithmetic is checked, but account-classification source operands cannot be independently reconstructed from these files.',
      'This reproduces historical captured evidence; it does not establish current authorization, new live provider execution, source posting, concurrency, export or native acceptance.',
    ],
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const base = 'docs/verification/wave5/genuine-finance-finance-20261013-r5-1791894738890/';
  const paths = ['statement-profit_loss.json', 'statement-balance_sheet.json', 'ratios-and-classification.json'];
  const contents = await Promise.all(paths.map(p => readFile(base + p)));
  const report = auditFinancialEvidence(...contents.map(b => JSON.parse(b)));
  report.verifiedAt = new Date().toISOString();
  report.inputBindings = contents.map((b, i) => ({ path: base + paths[i], sha256: createHash('sha256').update(b).digest('hex') }));
  await writeFile(new URL('./financial-evidence-reproduction.json', import.meta.url), JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  console.log(JSON.stringify({ passed: report.passed, ratioRows: report.ratioArithmeticRows.length, statementOperandsReproduced: report.statementOperandsReproduced, liveQueries: 0 }));
}
