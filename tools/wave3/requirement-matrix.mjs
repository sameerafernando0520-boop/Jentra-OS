import fs from 'node:fs';
import crypto from 'node:crypto';

const specPath = 'docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md';
const spec = fs.readFileSync(specPath, 'utf8');
const requirements = [...spec.matchAll(/^(- (FR|NFR|EC)-\d+:|### (AC)-\d+:) ([\s\S]*?)(?=\r?\n(?:- (?:FR|NFR|EC)-\d+:|##|###)|(?![\s\S]))/gm)]
  .map(m => ({ id: m[1].match(/(?:FR|NFR|EC|AC)-\d+/)[0], statement: m[4].replace(/\r?\n/g, ' ').trim() }));
const expected = { FR: 95, NFR: 20, AC: 26, EC: 40 };
for (const [kind, count] of Object.entries(expected)) {
  if (requirements.filter(r => r.id.startsWith(kind + '-')).length !== count) throw new Error(`Incomplete ${kind} extraction`);
}
const groups = [
  [301,312,'operational_foundation','command security, attachments and cross-module verification'],
  [313,318,'crm_pipeline','fresh regression and contextual navigation'],
  [319,321,'quotation_workspace','current-list/report integration'],
  [322,325,'order_workspace','current-list/report and reservation lifecycle integration'],
  [326,334,'delivery_receivables','report navigation, historical mappings, recovery and concurrent commands'],
  [335,339,'procurement','operational reporting and contextual source integration'],
  [340,341,'goods_receipts','source integration and wider verification'],
  [342,345,'supplier_bills','source integration and wider verification'],
  [346,349,'supplier_settlement','party reports, governed corrections and access/recovery verification'],
  [350,361,'stock_counts','landed corrections, count partitioning, disposition and reservation lifecycle'],
  [362,366,'manual_journal','source and attachment integration'],
  [367,369,'control_procurement','historical/retired control mapping coverage'],
  [370,371,'bank','bank reporting and concurrent match proof'],
  [372,374,'period','concurrent close/post verification'],
  [375,382,'financial_statements','operational, party and bank report extensions'],
  [383,395,'report_exports','dashboards, list state, contextual links, files and cross-module recovery'],
];
const acFr = [301,313,319,322,326,328,330,333,335,340,342,346,350,354,356,362,367,370,372,375,383,386,389,391,301,301];
const ecFr = [301,303,311,306,305,305,308,309,321,324,325,326,328,332,332,333,342,343,346,350,351,356,353,355,357,358,359,363,310,373,307,370,370,371,371,374,374,382,394,386];
const nfrGaps = {307:'target-scale p95 ordinary reads',308:'target-scale command p95',309:'500 tenants / 10 entities / 25 warehouses / 100k products / 10m movements / 20m journal lines',310:'representative plans at target scale',312:'genuine independent concurrent database sessions',314:'full keyboard/screen reader/reduced motion acceptance',315:'all sizes/themes/densities at 200 percent',317:'branch coverage and property-test targets',318:'wider security, fault injection and concurrency',319:'isolated build; authorized cold-launch/native QA pending',320:'target-scale report p95'};
const rows = requirements.map(r => {
  const number = Number(r.id.split('-')[1]);
  const fr = r.id.startsWith('FR') ? number : r.id.startsWith('AC') ? acFr[number-301] : r.id.startsWith('EC') ? ecFr[number-301] : 301;
  const g = groups.find(g => fr >= g[0] && fr <= g[1]);
  const evidencePath = `supabase/tests/wave3_${g[2]}_test.sql`;
  return { ...r, source_evidence: fs.existsSync(evidencePath) ? evidencePath : 'docs/verification/remaining-wave3/checkpoint.md (historical)',
    implementation: 'present in baseline; requirement-specific gap review pending',
    verification: 'historical evidence only until fresh execution',
    development_gap: r.id.startsWith('NFR') ? nfrGaps[number] || 'security/exactness/rollback/encrypted recovery fresh checks' : g[3],
    external_gate: 'development candidate installation, authenticated native acceptance and owner signoff remain separate', };
});
const result = {spec:specPath,spec_sha256:crypto.createHash('sha256').update(spec).digest('hex'),requirements:rows};
fs.writeFileSync('docs/verification/remaining-wave3/requirement-matrix-20260928.json',JSON.stringify(result,null,2)+'\n');
const md = ['# Wave 3 requirement-to-evidence matrix','',
  'Every approved FR, AC, EC and NFR is listed. Source/test references identify review inputs; their presence alone does not prove a requirement. Historical checkpoints remain historical. No candidate installation or authenticated native acceptance is claimed.', '',
  '| Requirement | Approved behavior | Current source/evidence | Development gap | Verification | External gate |',
  '|---|---|---|---|---|---|', ...rows.map(r => `| ${r.id} | ${r.statement.split('**Covers:**')[0].replace(/\|/g,'/')} | [source](../../../${r.source_evidence.split(' (')[0]}) | ${r.development_gap} | ${r.verification} | ${r.external_gate} |`)];
fs.writeFileSync('docs/verification/remaining-wave3/requirement-matrix-20260928.md',md.join('\n')+'\n');
console.log(JSON.stringify({counts:expected,total:rows.length,spec_sha256:result.spec_sha256}));
