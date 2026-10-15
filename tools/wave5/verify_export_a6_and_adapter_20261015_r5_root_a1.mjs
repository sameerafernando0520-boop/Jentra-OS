// Controlled root verification only. Never executes the private adapter.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {hashBytes} from './runtime_contract.mjs';
import {buildCandidate,PREDECESSOR,CANDIDATE} from './prepare_export_private_adapter_20261015_r5_a1.mjs';
import {validateExportsWindow,validateExportsTime,createExportsCallGate,exportsCallDescriptors,EXPORTS_COMMANDS,EXPORTS_PROFILE_PATHS}
 from './finance_exports_20261014_r5_a6.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const base='docs/verification/wave5/root-export-adapter-20261015/';
assert.deepEqual(process.argv.slice(2),['--verify-existing-outputs']);
const sourceProofPath='docs/verification/wave5/task3-export-renewal-20261014/export-a6-source-proof-a1.json';
const proof=JSON.parse(await fs.readFile(path.join(root,sourceProofPath)));
const snapshot=path.join(root,'build/wave5-approved-execution-20261013-r5-a2');
const checks=[];
const check=async(name,operation)=>{await operation();checks.push(name);};
const bindingCheck=async()=>{for(const row of proof.allBindings){
 const bytes=await fs.readFile(path.join(row.root==='frozen'?snapshot:root,row.path));
 assert.equal(hashBytes(bytes),row.sha256);assert.equal(bytes.length,row.bytes);
}};
await bindingCheck();
const before=await fs.readFile(path.join(root,PREDECESSOR.path)),candidate=await fs.readFile(path.join(root,CANDIDATE));
await check('exact_preserved_adapter_and_frozen_export_source',async()=>{
 assert.equal(hashBytes(before),PREDECESSOR.sha256);
 assert.equal(hashBytes(await fs.readFile(path.join(root,proof.sources[0].path))),proof.sources[0].sha256);
 assert.equal(buildCandidate(before,proof.sources[0].sha256).text,candidate.toString('utf8'));
});
await check('changed_predecessor_and_unbounded_source_hash_refused',()=>{
 assert.throws(()=>buildCandidate(Buffer.concat([before,Buffer.from('\n')]),'a'.repeat(64)));
 for(const value of ['', 'a'.repeat(63),'a'.repeat(65),'A'.repeat(64),'a'.repeat(64)+';x'])
  assert.throws(()=>buildCandidate(before,value));
});
const midnight=Date.parse('2026-10-15T23:59:00.000Z');
const window={notBefore:'2026-10-15T23:00:00.000Z',edgeExpiresAt:'2026-10-16T01:00:00.000Z',
 scopeExpiresAt:'2026-10-16T01:00:00.000Z',privateExpiresAt:'2026-10-16T00:30:00.000Z',expiresAt:'2026-10-16T00:30:00.000Z'};
await check('current_day_window_crosses_midnight_with_earliest_private_expiry',()=>{
 assert.equal(validateExportsWindow(window),window);
 const now=Date.parse('2026-10-16T00:00:01.000Z');
 assert.equal(validateExportsTime(now,{now,window}),now);
 assert.throws(()=>validateExportsTime(Date.parse(window.expiresAt),{now:Date.parse(window.expiresAt),window}));
});
await check('late_private_expiry_cannot_extend_runtime_and_missing_rows_stop',()=>{
 for(const value of [{...window,expiresAt:window.edgeExpiresAt},{...window,scopeExpiresAt:'2026-10-16T01:00:01.000Z'},
  {...window,edgeExpiresAt:undefined},{...window,notBefore:'2026-10-15T22:59:59.999Z'}])
  assert.throws(()=>validateExportsWindow(value));
});
await check('UTC_calendar_validation_rejects_normalization_and_nonUTC',()=>{
 for(const value of ['2026-02-30T00:00:00Z','2026-10-15T24:00:00Z','2026-10-16T00:00:00+05:30','2026-10-16T00:00:00'])
  assert.throws(()=>validateExportsTime(value,{now:midnight,window}));
});
await check('gate_clones_window_and_cannot_gain_time_from_caller_mutation',async()=>{
 let now=midnight;const supplied=structuredClone(window);
 const gate=createExportsCallGate({window:supplied,now:()=>now,startedAt:now});
 supplied.expiresAt='2027-01-01T00:00:00Z';supplied.edgeExpiresAt=supplied.scopeExpiresAt=supplied.privateExpiresAt=supplied.expiresAt;
 now+=900001;let calls=0;
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0],()=>{calls++;}));
 assert.equal(calls,0);assert.equal(gate.snapshot().totalWorkflowRequestBound,138);
});
await check('transport_failure_is_charged_before_dispatch_and_never_retried',async()=>{
 const gate=createExportsCallGate({window,now:()=>midnight,startedAt:midnight});let calls=0;
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0],()=>{calls++;throw Error('CONTROLLED');}));
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0],()=>{calls++;}));
 assert.equal(calls,1);assert.equal(gate.snapshot().totalWorkflowRequestBound,139);assert.equal(gate.snapshot().automaticRetries,0);
});
await check('original_export_command_identities_and_no_cash_command_route',()=>{
 assert.deepEqual(EXPORTS_COMMANDS.map(x=>x.commandId),['d4a0ad64-f138-b857-30d6-6fe0afe64e4f','217bcee3-d103-9513-a3e7-cc56d26e45be']);
 assert.equal(exportsCallDescriptors().length,24);
 for(const row of exportsCallDescriptors())assert.ok(!/cash_date_command|generate_financial_statement|wave5_cash_save/.test(row.route??''));
});
await check('actual_approval_readback_profile_and_intent_are_not_fabricated',async()=>{
 for(const file of [EXPORTS_PROFILE_PATHS.ownerDecision,EXPORTS_PROFILE_PATHS.renewalReadback,EXPORTS_PROFILE_PATHS.metadata,
  EXPORTS_PROFILE_PATHS.refresh,EXPORTS_PROFILE_PATHS.accounting,'docs/verification/wave5/finance-exports-once-20261014-r5-a6.json']){
  await assert.rejects(fs.stat(path.join(root,file)),e=>e.code==='ENOENT');
 }
});
const testFile='docs/verification/wave5/task3-export-renewal-20261014/finance_exports_20261014_r5_a6.test.mjs';
const testArgs=['--experimental-test-isolation=none','--test','--test-reporter=tap','--test-concurrency=1',testFile];
const log=await fs.readFile(path.join(root,base+'root-a6-suite-a2.log'),'utf8');
assert.match(log,/# tests 98/);assert.match(log,/# pass 98/);assert.match(log,/# fail 0/);
const receipt=JSON.parse(await fs.readFile(path.join(root,base+'actual-controlled-tools-a1.json')));
assert.equal(receipt.suiteExitCode,0);assert.equal(receipt.astExitCode,0);
assert.equal(receipt.suiteSha256,hashBytes(log));
const astBytes=await fs.readFile(path.join(root,base+'root-adapter-ast-a1.json'));
assert.equal(receipt.astSha256,hashBytes(astBytes));const ast=JSON.parse(astBytes);assert.equal(ast.passed,true);
await bindingCheck();assert.equal(hashBytes(await fs.readFile(path.join(root,PREDECESSOR.path))),PREDECESSOR.sha256);
assert.equal(hashBytes(await fs.readFile(path.join(root,CANDIDATE))),hashBytes(candidate));
const result={kind:'root-controlled-a6-and-export-adapter-verification',passed:true,observedAt:new Date().toISOString(),
 sourceProof:{path:sourceProofPath,sha256:hashBytes(await fs.readFile(path.join(root,sourceProofPath)))},
 sources:proof.sources,preservedBindingsVerifiedBeforeAndAfter:proof.allBindings.length,
 predecessor:PREDECESSOR,candidate:{path:CANDIDATE,sha256:hashBytes(candidate)},rootControls:checks,ast,
 authoredSuite:{command:[process.execPath,...testArgs],exitCode:receipt.suiteExitCode,tests:98,passed:98,failed:0,
 log:{path:base+'root-a6-suite-a2.log',sha256:hashBytes(log)}},
 priorHarnessFailure:{toolChunk:'433b7f',reason:'child process returned no exit status; no test execution claim',log:base+'root-a6-suite-a1.log'},
 sourceReviewOnly:true,adapterExecuted:false,adapterInstalled:false,networkCalls:0,privateInputsRead:false,
 executionApproved:false,acceptanceChanged:false,independentAgentReviewPending:true};
await fs.writeFile(path.join(root,base+'root-verification-a1.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({passed:true,rootControls:checks.length,astChecks:ast.checks.length,authoredSuite:98,preservedBindings:proof.allBindings.length,
 evidence:base+'root-verification-a1.json',networkCalls:0,privateInputsRead:false})+'\n');
