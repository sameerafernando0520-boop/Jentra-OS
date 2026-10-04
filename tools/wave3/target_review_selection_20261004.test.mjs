import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {after} from 'node:test';
import {sourceHash} from './strict-candidate-evidence.mjs';
import {digest, fixturePlan, reviewedSources, stableId, verifySources} from './prepare-target-verification.mjs';
import {liveRpcSourceSql} from './run-reviewed-target-verification.mjs';

// All identities and missing artifact names below are deliberately fictitious.
// These offline guards send no network request, execute no SQL and install nothing.
const seed='offline-selection-wave3-20261004';
const uid=name=>stableId(seed,name);
const scope={tenant_id:uid('tenant'),legal_entity_id:uid('entity'),branch_id:uid('branch')};
const fixture={synthetic:true,is_production:false,project_id:'abcdefghijklmnopqrst',url:'https://abcdefghijklmnopqrst.supabase.co',actor_id:uid('actor'),seed,posting_date:'2026-09-30',
  receipt_lanes:[{...scope,warehouse_id:uid('warehouse'),order_id:uid('order'),order_line_id:uid('line'),product_id:uid('product'),expected_version:1,receipt_count:1,quantity_per_receipt:'1',reviewed_remaining_quantity:'1',reviewed_value_per_receipt:'1'}]};
const missing={candidate_count:46,package_path:'docs/verification/remaining-wave3/offline-no-such-46-package.json',manifest_path:'docs/verification/remaining-wave3/offline-no-such-46-manifest.json',schema_review_path:'docs/verification/remaining-wave3/offline-no-such-46-schema.json'};

const root=path.resolve('docs/verification/remaining-wave3');
const temporary=fs.mkdtempSync(path.join(root,'.offline-selection-test-'));
after(()=>{
  const resolved=path.resolve(temporary);
  if(!resolved.startsWith(root+path.sep)||!path.basename(resolved).startsWith('.offline-selection-test-'))throw Error('Unsafe offline fixture cleanup boundary.');
  fs.rmSync(resolved,{recursive:true});
});
const write=(file,value)=>fs.writeFileSync(file,typeof value==='string'?value:JSON.stringify(value),{flag:'wx'});
let iteration=0;
function artificialSelection(mutate=()=>{}) {
  const directory=path.join(temporary,String(++iteration));fs.mkdirSync(directory);
  const relative=file=>path.relative(process.cwd(),path.join(directory,file)).replaceAll('\\','/');
  const selection={candidate_count:46,package_path:relative('package.json'),manifest_path:relative('manifest.json'),schema_review_path:relative('schema.json')};
  const historical=JSON.parse(fs.readFileSync('docs/verification/remaining-wave3/migration-order-final-20260930-45.json','utf8'));
  const candidates=historical.candidates.map(row=>({...row}));
  const tail='supabase/migrations/20261003090000_wave3_negative_stock_policy.sql';
  candidates.push({path:tail,ordinal:46,sha256:sourceHash(tail),installed:false,installed_now:false});
  // Exact current source is transported locally but never executed. The TAP,
  // helper and schema responses below are explicitly artificial offline data.
  const query='begin;\n'+candidates.map(row=>fs.readFileSync(row.path,'utf8')).join('\n')+'\ncreate extension if not exists pgtap;\nselect * from finish(true);\nrollback;';
  const suites=['procurement','inventory','receivables'].map(suite=>{
    const queryPath=relative(suite+'.sql');write(queryPath,query);
    const executionPath=relative(suite+'.json');
    return {suite,query:queryPath,execution:executionPath,query_sha256:sourceHash(queryPath),execution_sha256:null,assertions:2,failures:0,candidates_source_matched:46,strict_finish:true,final_rollback:true};
  });
  const shape=candidates.map(({ordinal,path,sha256})=>({ordinal,path,sha256}));
  // Order hash is a plain JSON serialization, as in the actual manifest writer.
  const hash=sourceHash(relative('procurement.sql'));
  const manifest={head:'ARTIFICIAL-OFFLINE-ONLY',candidates,exact_order_sha256:null};
  const schema={before:{schema_version:'45-before-negative-stock-tail-20261003'},after:{...JSON.parse(fs.readFileSync('docs/verification/remaining-wave3/schema-after-45-20260930.json','utf8')),schema_version:'46-after-negative-stock-tail-20261003'},
    execution:{file:suites[0].execution,sha256:null,query_sha256:hash},shared_finance_helpers:['a','b','c','d'].map(name=>({name,unchanged:true})),boundary:'ARTIFICIAL SCHEMA FIXTURE ONLY; NOT OBSERVED'};
  schema.after.functions['api.configure_negative_stock_policy(uuid)']={source_md5:'a'.repeat(32)};
  const installation={head:manifest.head,candidates:structuredClone(candidates),manifest_path:selection.manifest_path,exact_order_sha256:null,compatibility:{new_tail_review:{file:selection.schema_review_path,sha256:null}},fresh_strict_execution:{suites}};
  for(const row of suites) {
    write(row.execution,{observed_at:'2026-10-04T00:00:00Z',project_id:'xpdoufauvrbdmxgngetv',transport:'connected_supabase_mcp',mcp_is_error:false,query_sha256:row.query_sha256,
      result:{tap:'ok 1 - ARTIFICIAL OFFLINE FIXTURE ONLY\nok 2 - NO DATABASE EXECUTION\n1..2',...(row.suite==='procurement'?{negative_stock_schema_review:{'45_before_tail':schema.before,'46_after_tail':schema.after}}:{})}});
    row.execution_sha256=sourceHash(row.execution);
  }
  schema.execution.sha256=suites[0].execution_sha256;
  mutate({selection,manifest,installation,schema});
  write(selection.schema_review_path,schema);
  installation.compatibility.new_tail_review.sha256=sourceHash(selection.schema_review_path);
  // digest(string) preserves the exact non-sorted serialized order convention.
  manifest.exact_order_sha256??=digest(JSON.stringify(shape));
  installation.exact_order_sha256??=manifest.exact_order_sha256;
  write(selection.manifest_path,manifest);write(selection.package_path,installation);
  return selection;
}

test('Explicit current46 selection cannot silently fall back to the historical45 source list',()=>{
  assert.throws(()=>reviewedSources(missing),/selection|artifact|ENOENT/i);
});
test('Current46 fixture plan requires the explicitly selected complete artifacts',()=>{
  assert.throws(()=>fixturePlan({...fixture,candidate_review:missing}),/selection|artifact|ENOENT/i);
});
test('Relabelling a valid legacy45 source bundle as current46 is rejected',()=>{
  const legacy=fixturePlan(fixture);
  const relabelled={...legacy,candidate_review:missing};
  relabelled.source_bundle_sha256=digest(relabelled.source_hashes);
  assert.throws(()=>verifySources(relabelled),/selection|artifact|bundle|ENOENT/i);
});
test('Current46 live RPC comparison cannot use the historical45 schema by omission',()=>{
  const config={candidate_review:missing,workloads:[{calls:[{rpc:'post_goods_receipt'}]}]};
  assert.throws(()=>liveRpcSourceSql(config),/selection|artifact|ENOENT/i);
});
test('The explicit historical library default retains all45 source hashes',()=>{
  const sources=reviewedSources();
  const order=JSON.parse(fs.readFileSync('docs/verification/remaining-wave3/migration-order-final-20260930-45.json','utf8'));
  assert.equal(order.candidates.length,45);
  for(const row of order.candidates)assert.equal(sources[row.path],row.sha256);
  verifySources(fixturePlan(fixture));
});
test('An explicitly selected artificial46 bundle retains every body and selected metadata',()=>{
  const selection=artificialSelection(),sources=reviewedSources(selection);
  const tail='supabase/migrations/20261003090000_wave3_negative_stock_policy.sql';
  assert.equal(sources[tail],sourceHash(tail));
  for(const key of ['package_path','manifest_path','schema_review_path'])assert.equal(sources[selection[key]],sourceHash(selection[key]));
  const plan=fixturePlan({...fixture,candidate_review:selection});
  assert.deepEqual(plan.candidate_review,selection);verifySources(plan);
  assert.equal(plan.executed,false);
});
test('Current46 RPC preflight uses the selected artificial tail schema',()=>{
  const candidate_review=artificialSelection();
  const result=liveRpcSourceSql({candidate_review,workloads:[{calls:[{rpc:'configure_negative_stock_policy'}]}]});
  assert.deepEqual(result.expected,{'api.configure_negative_stock_policy(uuid)':'a'.repeat(32)});
  assert.match(result.sql,/^begin read only;/);assert.match(result.sql,/rollback;$/);
});
test('Omitted46 tail, changed source hash and invalid artifact path fail closed',()=>{
  assert.throws(()=>reviewedSources(artificialSelection(({manifest})=>manifest.candidates.pop())),/46 candidate|omitted/i);
  assert.throws(()=>reviewedSources(artificialSelection(({manifest})=>manifest.candidates.at(-1).sha256='f'.repeat(64))),/source\/order/i);
  assert.throws(()=>reviewedSources({...missing,manifest_path:'..\/outside.json'}),/artifact/i);
});
test('Wrong ordered package, missing suite and altered schema/helper bindings fail closed',()=>{
  assert.throws(()=>reviewedSources(artificialSelection(({installation})=>installation.exact_order_sha256='f'.repeat(64))),/bindings differ/i);
  assert.throws(()=>reviewedSources(artificialSelection(({installation})=>installation.fresh_strict_execution.suites.pop())),/three completed/i);
  assert.throws(()=>reviewedSources(artificialSelection(({schema})=>schema.shared_finance_helpers[0].unchanged=false)),/schema review/i);
  assert.throws(()=>reviewedSources(artificialSelection(({schema})=>schema.execution.query_sha256='f'.repeat(64))),/schema review/i);
  assert.throws(()=>reviewedSources(artificialSelection(({schema})=>schema.after.functions['api.configure_negative_stock_policy(uuid)'].source_md5='b'.repeat(32))),/schema review/i);
});
test('Rehashed selected46 bundle cannot omit the policy body or selection artifacts',()=>{
  const selection=artificialSelection();
  const plan=fixturePlan({...fixture,candidate_review:selection});
  delete plan.source_hashes['supabase/migrations/20261003090000_wave3_negative_stock_policy.sql'];
  plan.source_bundle_sha256=digest(plan.source_hashes);
  assert.throws(()=>verifySources(plan),/Complete explicitly selected/i);
});
