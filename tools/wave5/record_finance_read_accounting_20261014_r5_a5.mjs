import fs from 'node:fs/promises';
import { hashBytes } from './runtime_contract.mjs';
const root = new URL('../../', import.meta.url);
const entries = [
  ['docs/verification/wave5/finance-pipeline-shape-readonly-investigation-20261014-r5-a4.json', '039a8b42ab7b93302853e094e9448e458a5c42d3020bbac765b7f96dae4a3d3e'],
  ['docs/verification/wave5/private-owner-scope-refresh-20261014-r5-a8.json', '232ba925717dfaae261c9cecb1a654d24e218b7a52df3f71daaf18d94b75c0c7'],
  ['docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json', 'd46ee968a50955e39154947f03833415bbe41e39b8771bb603bacd2ee52b615e']
];
const verified = [];
for (const [file, expected] of entries) {
  const b = await fs.readFile(new URL(file, root));
  if (hashBytes(b) !== expected) throw Error('EXACT_ACCOUNTING_EVIDENCE_REQUIRED');
  verified.push({ path: file, sha256: expected, value: JSON.parse(b) });
}
const shape = verified[0].value, a8 = verified[1].value, ready = verified[2].value;
const a9Bytes = await fs.readFile(new URL(ready.refreshEvidence.path, root));
if (hashBytes(a9Bytes) !== ready.refreshEvidence.sha256) throw Error('EXACT_A9_ACTUAL_REFRESH_REQUIRED');
const a9 = JSON.parse(a9Bytes);
if (shape.cumulativeConservativeWorkflowRequestBound !== 129 || a8.readOnlyOwnerApiCalls !== 1 || a9.readOnlyOwnerApiCalls !== 1 ||
    a8.databaseWrites !== 0 || a9.databaseWrites !== 0 || a8.settingsChanges !== 0 || a9.settingsChanges !== 0 ||
    ready.expiresAt !== '2026-10-14T05:53:48.705Z' || a9.helperSha256 !== 'b8ddcb732628bb28a9e0a511d6ef2fc83892529c2a58b9c023bae2fcec8242c7') throw Error('EXACT_READONLY_CHARGES_REQUIRED');
const record = {
  kind: 'conservative-finance-continuation-read-accounting', recordedAt: new Date().toISOString(),
  projectId: 'xpdoufauvrbdmxgngetv', originalConcreteFinancePlanCap: 150,
  recordedAfterA3Stop: 128, shapeInvestigationCalls: 1, chargedA8OwnerIdentityReads: 1, chargedA9OwnerIdentityReads: 1,
  cumulativeChargedPriorCalls: 131,
  scope: 'Conservative continuation budget accounting; this is not a count of all project activity or every connector query.',
  evidence: verified.map(({path,sha256}) => ({path,sha256})), actualA9Refresh: ready.refreshEvidence,
  freshPrivateReady: { path: entries[2][0], sha256: entries[2][1], expiresAt: ready.expiresAt },
  originalRuntimeAuthorityExpiresAt: '2026-10-14T09:57:07.481942Z', authorityExtended: false,
  exportsExecutedByThisRecord: 0, successorExportCapAuthorizedByThisRecord: false,
  originalSourcesCountersConsumedIntentsAnd150CapPreserved: true,
  preparationFailurePreserved: {execChunk:'8a9580',code:'EXACT_REFRESH_MODE_LISTS_REQUIRED',liveCalls:0,filesMutated:0,repair:'Verified thirteen existing A8 mode lists, including the added latest-ready selector; original adapter hash remained unchanged before source-only repair.'}
};
const out = 'docs/verification/wave5/finance-cumulative-read-accounting-20261014-r5-a5.json';
const text = JSON.stringify(record, null, 2) + '\n';
await fs.writeFile(new URL(out, root), text, { flag: 'wx' });
process.stdout.write(JSON.stringify({path:out,sha256:hashBytes(text),cumulativeChargedPriorCalls:131,actualA9Refresh:ready.refreshEvidence,freshPrivateReady:record.freshPrivateReady})+'\n');
