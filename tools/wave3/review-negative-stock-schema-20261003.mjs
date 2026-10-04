import fs from 'node:fs';
import crypto from 'node:crypto';
import {artifactTag, decodedResult, verifyCandidateOrder, verifyStrictExecution, writeNewJson} from './strict-candidate-evidence.mjs';

const base='docs/verification/remaining-wave3/';
const read=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const [executionPath,queryPath,packagePath,selectedTag='20261003']=process.argv.slice(2);
const tag=artifactTag(selectedTag);
if (![executionPath,queryPath,packagePath].every(file=>file&&fs.existsSync(file))) throw Error('Pass actual execution, exact executed query and prepared46 package.');
const execution=read(executionPath),query=fs.readFileSync(queryPath,'utf8').replace(/^\uFEFF/,''),prepared=read(packagePath);
const tap=verifyStrictExecution(execution,query,hash(queryPath));
const find=(value,key)=>{
  if (!value||typeof value!=='object') return [];
  const found=Object.hasOwn(value,key)?[value[key]]:[];
  return [...found,...Object.values(value).flatMap(child=>find(child,key))];
};
const captures=find(decodedResult(execution.result),'negative_stock_schema_review');
if(captures.length!==1||!captures[0]?.['45_before_tail']||!captures[0]?.['46_after_tail']) throw Error('Actual result lacks unique45before/46aftertail metadata.');
const before=captures[0]['45_before_tail'],after=captures[0]['46_after_tail'];
if(before.schema_version!=='45-before-negative-stock-tail-20261003'||after.schema_version!=='46-after-negative-stock-tail-20261003') throw Error('Schema phase label mismatch.');
if(prepared.candidates?.length!==46||prepared.candidates.some(row=>row.sha256!==hash(row.path)||!query.includes(fs.readFileSync(row.path,'utf8')))) throw Error('Current prepared candidate bodies differ from actual execution.');
verifyCandidateOrder(query,prepared.candidates);
const entries=object=>Object.entries(object??{}),keys=object=>Object.keys(object??{}),same=(left,right)=>JSON.stringify(left)===JSON.stringify(right);
const functions={
  added:keys(after.functions).filter(key=>!Object.hasOwn(before.functions,key)),
  removed:keys(before.functions).filter(key=>!Object.hasOwn(after.functions,key)),
  return_type_changes:entries(before.functions).filter(([key,value])=>after.functions[key]&&value.return_type!==after.functions[key].return_type).map(([key,value])=>({function:key,before:value.return_type,after:after.functions[key].return_type})),
  acl_changes:entries(before.functions).filter(([key,value])=>after.functions[key]&&value.acl!==after.functions[key].acl).map(([key,value])=>({function:key,before:value.acl,after:after.functions[key].acl})),
  source_changes:entries(before.functions).filter(([key,value])=>after.functions[key]&&value.source_md5!==after.functions[key].source_md5).map(([key,value])=>({function:key,before:value.source_md5,after:after.functions[key].source_md5})),
};
const views={added:keys(after.views).filter(key=>!Object.hasOwn(before.views,key)),removed:keys(before.views).filter(key=>!Object.hasOwn(after.views,key)),
  changes:entries(before.views).filter(([key,value])=>after.views[key]&&!same(value,after.views[key])).map(([key,value])=>({view:key,before:value,after:after.views[key]}))};
const tables={added:keys(after.tables).filter(key=>!Object.hasOwn(before.tables,key)),removed:keys(before.tables).filter(key=>!Object.hasOwn(after.tables,key)),
  changed_existing:entries(before.tables).filter(([key,value])=>after.tables[key]&&!same(value,after.tables[key])).map(([key,value])=>({table:key,before:value,after:after.tables[key]}))};
const financeHelpers=['flow_residual','wave3_lock_open_period','flow_post_journal','flow_allocate'].map(name=>{
  const matches=keys(before.functions).filter(key=>key.startsWith('finance.'+name+'('));
  if(matches.length!==1)throw Error('Finance helper capture ambiguous: '+name);
  const key=matches[0];return {name,signature:key,before:before.functions[key],after:after.functions[key],unchanged:same(before.functions[key],after.functions[key])};
});
if(financeHelpers.some(row=>!row.unchanged))throw Error('Protected shared finance helper modified by tail.');
const publicBefore=keys(before.functions).filter(key=>key.startsWith('api.'));
const apiRemoved=publicBefore.filter(key=>!after.functions[key]),apiReturnChanges=functions.return_type_changes.filter(row=>row.function.startsWith('api.'));
const warnings=[...apiRemoved.map(functionName=>({type:'removed_api_signature',severity:'breaking',function:functionName})),
  ...apiReturnChanges.map(row=>({type:'changed_api_return_type',severity:'breaking',...row})),
  ...functions.acl_changes.filter(row=>row.function.startsWith('api.')).map(row=>({type:'changed_api_acl',severity:'potential',...row})),
  ...views.removed.map(view=>({type:'removed_api_view',severity:'breaking',view})),
  ...views.changes.map(row=>({type:'changed_api_view_definition_or_options',severity:'potential',...row})),
  ...tables.changed_existing.map(row=>({type:'changed_existing_table_columns_or_constraints',severity:'potential',table:row.table})),
];
const report={generated_at:new Date().toISOString(),execution_observed_at:execution.observed_at,
  execution:{file:executionPath,sha256:hash(executionPath),query:queryPath,query_sha256:hash(queryPath),tap},
  prepared_package:{file:packagePath,sha256:hash(packagePath)},before,after,functions,views,tables,shared_finance_helpers:financeHelpers,
  warnings,summary:{breaking:warnings.filter(row=>row.severity==='breaking').length,potential:warnings.filter(row=>row.severity==='potential').length},
  boundary:'Actual45→46 metadata comparison inside successful strict rollback execution. This detects named signature, return, ACL, view, existing-column/constraint changes and preserves four shared finance helpers. Metadata comparison is not exhaustive older-client/data compatibility, installed/native/authenticated/load acceptance, or owner signoff. Historical45 zero/eight compatibility warning report remains separate.',
};
const output=base+`schema-negative-stock-policy-${tag}-46.json`;
writeNewJson(output,report);
console.log(JSON.stringify({output,summary:report.summary,api_signature_removals:apiRemoved.length,api_return_changes:apiReturnChanges.length,finance_helpers_unchanged:4,added_tables:tables.added.length,changed_existing_tables:tables.changed_existing.length}));
