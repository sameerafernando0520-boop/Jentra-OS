import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const root = resolve('C:/Users/sheha/Desktop/Jentra OS');
const owned = 'docs/verification/wave5/seven-area-completion-20261016/area1-windows';
const read = p => readFileSync(resolve(root,p));
const json = p => JSON.parse(read(p));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const bind = path => { const bytes = read(path); return {path,bytes:bytes.length,sha256:hash(bytes)}; };
const historicalPath = 'docs/verification/wave5/task3-completion-20261013/desktop-partitioned-independent-verification-20261014.json';
assert.equal(bind(historicalPath).sha256,'9edb0aa5648f9b30c8c48c09b94a365605e8a4a5f5ef46f41260a311385ec97e');
const historical = json(historicalPath);
const verifiedHistoricalEvidence = historical.evidence.map(expected => {
  const actual = bind(expected.path);
  assert.equal(actual.sha256,expected.sha256,expected.path);
  assert.equal(actual.bytes,expected.bytes,expected.path);
  return actual;
});
const manifestPath = 'docs/verification/wave5/windows-test-preview-source-20261009-o13r7.json';
const manifest = json(manifestPath);
const paths = [
 'apps/jentra_desktop/lib/src/features/analytics/process_metric_controller.dart',
 'apps/jentra_desktop/lib/src/features/analytics/process_metric_screen.dart',
 'apps/jentra_desktop/lib/src/shell/jentra_shell.dart',
 'apps/jentra_desktop/lib/src/app_providers.dart',
 'packages/jentra_platform/lib/src/analytics/process_filter_store.dart',
 'packages/jentra_platform/lib/src/draft_repository.dart',
 'packages/jentra_platform/lib/src/local_draft_storage_failure.dart',
 'apps/jentra_desktop/test/process_metric_workspace_test.dart',
 'packages/jentra_platform/test/analytics/process_filter_store_test.dart',
 'packages/jentra_platform/test/local_draft_storage_failure_test.dart',
];
const sourceComparison = paths.map(path => {
 const current = bind(path), snapshot = bind(`build/w5win9o13r7/preview/${path}`);
 const expected = manifest.baseSourceHashes[path];
 return {path,currentSha256:current.sha256,snapshotSha256:snapshot.sha256,historicalManifestSha256:expected ?? null,currentMatchesHistoricalManifest:expected === current.sha256,snapshotMatchesHistoricalManifest:expected === snapshot.sha256,currentMatchesSavedSnapshot:current.sha256 === snapshot.sha256};
});
const protocolPath = 'docs/verification/wave5/task3-windows-20261013/native-acceptance-protocol.md';
const protocol = read(protocolPath).toString('utf8');
const cases = [...protocol.matchAll(/^\| (W[NKRV]\d{2}) \| (.*?) \| (.*?) \|$/gm)].map(m => ({id:m[1],requiredObservation:m[2],requirements:m[3].split(', ').map(s=>s.trim()),actualVerdict:'unverified'}));
const ids = ['FR-530','FR-531','NFR-508','AC-515','EC-513','FR-558','FR-559','AC-556','EC-558'];
const matrixPath = 'docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json';
const matrix = json(matrixPath);
const rows = ids.map(id => {
 const row = matrix.rows.find(r=>r.id === id);
 assert.ok(row,id); assert.equal(row.accepted,false,id);
 const requiredCaseIds = cases.filter(c=>c.requirements.includes(id)).map(c=>c.id);
 assert.ok(requiredCaseIds.length,id);
 return {id,fullStatement:row.fullStatement,statementSha256:row.statementSha256,decision:'open_missing_actual_authenticated_native_evidence',accepted:false,requiredCaseIds,nextEvidence:row.nextEvidence};
});
const logPath = 'docs/verification/wave5/desktop-partitioned-20261013-o13r7/11-tests.log';
const log = read(logPath).toString('utf8');
const names = ['filter replacement rejects late response','revocation and offline clear protected summaries and detail','disposing pending reader rejects all later evidence','process workspace light at 200 percent','process workspace dark at 200 percent'];
for (const name of names) assert.ok(log.includes(name),name);
const report = {
 kind:'wave5-area1-source-and-historical-evidence-verification',observedAt:new Date().toISOString(),
 verificationPassed:true, SDKExecuted:false,networkCalls:0,privateInputsRead:false,nativeActionsExecuted:0,
 historicalRun:{finishedAt:historical.actualRunFinishedAt,desktopCasesPassed:historical.testCasesPassed,desktopFiles:historical.testFiles,failed:historical.failed,skipped:historical.skipped,evidenceBindingsVerified:verifiedHistoricalEvidence.length,focusedProcessCasesPresent:names,sourceOnlyOrControlled:true},
 historicalEvidence:bind(historicalPath),verifiedHistoricalEvidence,sourceComparison,
 sourceDrift:sourceComparison.filter(v=>!v.currentMatchesHistoricalManifest || !v.snapshotMatchesHistoricalManifest),
 fullNativeProtocol:bind(protocolPath),matrix:bind(matrixPath),nativeCaseCount:cases.length,cases,rows,
 acceptedRowsAdded:0,authenticatedNativeAcceptance:false,keyboardAcceptance:false,restartRecoveryAcceptance:false,
 conclusions:['Existing saved desktop tests remain historical controlled evidence; no native claim follows from them.','Current and saved source hashes are compared individually; absent historical bindings are reported as drift instead of asserted current pass.','No confirmed product defect was established by the scoped source trace. Native prerequisites and actual execution remain the blocking work.'],
 verifier:bind(`${owned}/verify-source-and-evidence.mjs`)
};
const output = `${owned}/source-and-historical-evidence-verification.json`;
writeFileSync(resolve(root,output),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output,sha256:bind(output).sha256,passed:true,historicalBindingsVerified:verifiedHistoricalEvidence.length,sourceComparisons:sourceComparison.length,drift:report.sourceDrift.map(v=>v.path),nativeCases:cases.length,rows:rows.length,accepted:0}));
