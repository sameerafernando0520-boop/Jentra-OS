import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import path from 'node:path';
import { assertRaceClass, openNewEvidence } from './target_review_guards.mjs';

const requiredRaces = ['number_reservation','order_allocation','stock_issue','receipt',
 'matching','allocation','posting','close','reversal'];
const currentProject='xpdoufauvrbdmxgngetv';
const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const allowlist=new Set([...fs.readFileSync('packages/jentra_platform/lib/src/wave3_observability_allowlist.dart','utf8')
 .split('const wave3ObservedOutcomeCodes')[0].matchAll(/'([a-z][a-z0-9_]*)'/g)].map(m=>m[1]));
const hash=v=>crypto.createHash('sha256').update(typeof v==='string'?v:JSON.stringify(v)).digest('hex');
const diagnosticSource=fs.readFileSync('packages/jentra_platform/lib/src/wave3_observability_allowlist.dart','utf8');
const codes=new Set([...diagnosticSource.split('const wave3ObservedOutcomeCodes')[1].matchAll(/'([A-Z0-9_]+)'/g)].map(m=>m[1]));
// Reviewed read-only APIs. Generation/export recording and lifecycle commands are excluded.
const reads=new Set(['wave3_document_evidence','wave3_document_page','posted_journal_evidence',
 'stock_count_detail','stock_count_partitions_page','stock_disposition_detail','stock_dispositions_page',
 'stock_reservation_queue','stock_reservation_history','stock_reservations_as_of','inventory_transfer_holdings',
 'inventory_transfers','receipt_trace_detail','receipt_trace_page','payable_item_detail','payable_allocation_targets',
 'customer_statement','supplier_statement','bank_reconciliation_options','period_governance_options',
 'close_control_review_page','control_reconciliation_report_page','financial_statement_page','operational_report_page',
 'inventory_valuation_report_page','tax_summary_page','budget_variance_page','wave3_dashboard','wave3_observability_status']);
function protectedContext(value) {
 if(typeof value==='string' && /stock_opening|private_hr|people_|wave4/i.test(value))return true;
 return value && typeof value==='object' && Object.values(value).some(protectedContext);
}
function validate(config) {
 if(!config.synthetic || config.is_production!==false || !/^[a-z]{20}$/.test(config.project_id)
  || config.project_id===currentProject)throw Error('Only a separately approved isolated synthetic target is permitted');
 if(config.url!==`https://${config.project_id}.supabase.co`)throw Error('Target URL does not match the isolated project');
 if(!Array.isArray(config.actors) || config.actors.length!==2 || config.actors[0]===config.actors[1]
   || !config.actors.every(a=>uuid.test(a)))throw Error('Two distinct synthetic actors are required');
 if(!config.scope || !['tenant_id','legal_entity_id','branch_id'].every(k=>uuid.test(config.scope[k]??'')))throw Error('Exact approved synthetic scope required');
 if(!Array.isArray(config.races) || config.races.length!==9 || requiredRaces.some(k=>config.races.filter(r=>r.kind===k).length!==1))throw Error('All nine required concurrency classes need concrete cases');
 for(const race of config.races) {
  assertRaceClass(race.kind,race.commands);
  if(!Array.isArray(race.commands) || race.commands.length!==2 || !race.invariants?.length || !Number.isInteger(race.expected_successes) || race.expected_successes<0 || race.expected_successes>2)throw Error('Each race requires two commands, expected outcomes and final invariants');
  if(race.expected_successes<2 && (!Array.isArray(race.allowed_conflict_codes) || !race.allowed_conflict_codes.length
    || !race.allowed_conflict_codes.every(c=>codes.has(c))))throw Error('Expected losing commands need fixed approved conflict codes');
  for(const command of race.commands) {
   if(!allowlist.has(command.rpc) || reads.has(command.rpc) || !command.params || protectedContext(command.params) || !uuid.test(command.params.p_command_id??'')
     || !uuid.test(command.params.p_idempotency_key??''))throw Error('Only concrete allowlisted authenticated command envelopes may execute');
   for(const [key,value] of Object.entries(config.scope))if(command.params['p_'+key]!==value)throw Error('Command scope differs from approval scope');
  }
  for(const invariant of race.invariants) {
   if(!reads.has(invariant.rpc) || !invariant.params || protectedContext(invariant.params) || !invariant.checks?.length)throw Error('Concrete scoped read invariants required');
   for(const [key,value] of Object.entries(config.scope))if(invariant.params['p_'+key]!==value)throw Error('Read scope differs from approval scope');
   if(!invariant.checks.every(c=>typeof c.pointer==='string' && c.pointer.startsWith('/') &&
      (typeof c.equals==='string'||typeof c.equals==='boolean'||c.equals===null||Number.isSafeInteger(c.equals))))throw Error('Exact expected invariants required');
  }
 }
}
function pointer(json,path){return path.split('/').slice(1).reduce((v,k)=>v?.[k.replaceAll('~1','/').replaceAll('~0','~')],json);}
function percentile(samples,p){const ordered=[...samples].sort((a,b)=>a-b);return ordered[Math.ceil(p*ordered.length)-1];}

if(process.argv.includes('--self-test')) {
 assert.equal(pointer({rows:[{residual:'90071992547409.123456'}]},'/rows/0/residual'),'90071992547409.123456');
 assert.equal(percentile([4,1,3,2],.95),4);
 assert.throws(()=>validate({project_id:currentProject,synthetic:true,is_production:false}),/isolated/);
 assert.equal(hash({exact:'0.000001'}),hash({exact:'0.000001'}));
 assert.equal(reads.has('post_manual_journal'),false);
 assert.equal(protectedContext({p_payload:{aggregate_type:'stock_opening'}}),true);
 assert.equal(protectedContext({p_payload:{aggregate_type:'private_hr_request'}}),true);
 assert.equal(codes.has('DISPOSITION_SERIAL_REVERSAL_DENIED'),true);
 console.log('Offline concurrency harness validation passed; no connections opened.');
} else {
 const configPath=process.argv.find(a=>a.endsWith('.json'));
 if(!configPath)throw Error('Usage: node run-independent-sessions.mjs config.json [--execute]. Default validates a plan only.');
 const config=JSON.parse(fs.readFileSync(configPath,'utf8'));validate(config);
 const plan={project_id:config.project_id,scope:config.scope,races:config.races.map(r=>r.kind),
  config_sha256:hash(config),executed:false,boundary:'Plan validation only; no installed/concurrent-session proof.'};
 if(!process.argv.includes('--execute'))console.log(JSON.stringify(plan,null,2));
 else {
  if(!config.approval_reference || config.approval_status!=='explicit_user_approval'
   || !/^[a-f0-9]{64}$/i.test(config.approved_ledger_sha256??'') || !/^[a-f0-9]{64}$/i.test(config.actual_ledger_sha256??'')
   || config.approved_ledger_sha256!==config.actual_ledger_sha256)throw Error('Concrete owner approval and matching installed ledger are required');
  const tokens=[process.env.WAVE3_SESSION_A_TOKEN,process.env.WAVE3_SESSION_B_TOKEN];
  const key=process.env.WAVE3_ISOLATED_PUBLIC_KEY;
  if(!key || tokens.some(t=>!t) || tokens[0]===tokens[1])throw Error('Two independently authenticated existing sessions and target key are required');
  const sessionIds=[];
  for(let i=0;i<2;i++){
   let claims;try{claims=JSON.parse(Buffer.from(tokens[i].split('.')[1],'base64url').toString('utf8'));}
   catch{throw Error('Malformed authenticated session claims');}
   if(claims.sub!==config.actors[i] || claims.role!=='authenticated' || !Number.isFinite(claims.exp) || claims.exp*1000<=Date.now()
    || claims.iss!==config.url+'/auth/v1' || !uuid.test(claims.session_id??''))throw Error('Session actor/issuer/expiry/session ID does not match isolated approval');
   sessionIds.push(claims.session_id);
  }
  if(sessionIds[0]===sessionIds[1])throw Error('Two independent authentication session IDs are required');
  const evidenceRoot=path.resolve('docs/verification/remaining-wave3/approved-runs');
  const evidencePath=path.resolve(config.evidence_path??'');
  if(!evidencePath.startsWith(evidenceRoot+path.sep) || path.extname(evidencePath)!=='.json')throw Error('Use a task-owned approved-runs JSON evidence path');
  const results=[];
  const evidenceDescriptor=openNewEvidence(evidencePath,evidenceRoot);
  async function rpc(call,session){
   const started=new Date().toISOString(),at=performance.now();
   const evidence={session:session+1,authentication_session_id:sessionIds[session],actor:config.actors[session],
    rpc:call.rpc,envelope_sha256:hash(call.params),started_at:started,success:false};
   try {
   const response=await fetch(config.url+'/rest/v1/rpc/'+call.rpc,{method:'POST',
    headers:{apikey:key,Authorization:'Bearer '+tokens[session],'Content-Profile':'api','Content-Type':'application/json'},
    body:JSON.stringify(call.params),signal:AbortSignal.timeout(30000)});
   evidence.http_status=response.status;
   const raw=await response.text();evidence.response_sha256=hash(raw);
   const body=JSON.parse(raw),code=body.error?.code??body.message??body.code;
   Object.assign(evidence,{outcome_code:codes.has(code)?code:null,success:response.ok&&body.success!==false,transport_state:'response_received'});
   return {body,evidence};
   }catch{evidence.transport_state='transport_uncertain';return {body:null,evidence};}
   finally{evidence.finished_at=new Date().toISOString();evidence.elapsed_ms=performance.now()-at;}
  }
  let passed=false;
  try {
  for(const race of config.races){
   const recorded={kind:race.kind,sessions:[],invariants:[],passed:false};results.push(recorded);
   // Separate JWT sessions start together. No synthetic sleep/fake lock contention.
   const pair=await Promise.all(race.commands.map((c,i)=>rpc(c,i)));
   recorded.sessions=pair.map(r=>r.evidence);
   recorded.client_requests_overlapped=Date.parse(pair[0].evidence.finished_at)>Date.parse(pair[1].evidence.started_at)
     && Date.parse(pair[1].evidence.finished_at)>Date.parse(pair[0].evidence.started_at);
   if(pair.some(r=>r.evidence.transport_state!=='response_received') || pair.filter(r=>r.evidence.success).length!==race.expected_successes)throw Error('Unexpected or uncertain race outcomes; retain isolated records for review');
   if(!recorded.client_requests_overlapped || pair.some(r=>!r.evidence.success && !race.allowed_conflict_codes.includes(r.evidence.outcome_code)))throw Error('Requests did not overlap or losing outcome differs from the approved conflict');
   for(const invariant of race.invariants){
    const result=await rpc(invariant,0);
    const checkEvidence={...result.evidence,checks:[]};recorded.invariants.push(checkEvidence);
    if(!result.evidence.success)throw Error('Final scoped invariant read rejected');
    for(const check of invariant.checks){
     const matched=Object.is(pointer(result.body,check.pointer),check.equals);
     checkEvidence.checks.push({pointer:check.pointer,passed:matched});
     if(!matched)throw Error('Final scoped invariant mismatch');
    }
   }
   recorded.passed=true;
  }
  passed=true;
  }finally{
  const out={...plan,executed:true,passed,finished_at:new Date().toISOString(),ledger_sha256:config.actual_ledger_sha256,approval_reference:config.approval_reference,results,
   boundary:'Independent-session evidence only for recorded installed target/cases; not native or target-scale p95 proof.'};
  try{fs.writeFileSync(evidenceDescriptor,JSON.stringify(out,null,2)+'\n');}
  finally{fs.closeSync(evidenceDescriptor);}
  console.log(JSON.stringify({evidence_path:evidencePath,passed,races_recorded:results.length}));
  }
 }
}
