import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { openNewEvidence } from './target_review_guards.mjs';
import { assertOrdinaryReportBinding, collectAgedReport, isAgedMetric, ordinaryReportMetrics } from './target_review_aging.mjs';

// Prepared execution tool. This task runs only its offline self-test.
const currentProject='xpdoufauvrbdmxgngetv';
const uuid=/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const sha=/^[a-f0-9]{64}$/i;
const hash=s=>crypto.createHash('sha256').update(typeof s==='string'?s:JSON.stringify(s)).digest('hex');
const limits={read:500,save:1500,transition:1500,post:3000,ordinary_report:2000,complex_report:10000};
const source=fs.readFileSync('packages/jentra_platform/lib/src/wave3_observability_allowlist.dart','utf8');
const rpcNames=new Set([...source.split('const wave3ObservedOutcomeCodes')[0].matchAll(/'([a-z][a-z0-9_]*)'/g)].map(m=>m[1]));
const outcomeCodes=new Set([...source.split('const wave3ObservedOutcomeCodes')[1].matchAll(/'([A-Z0-9_]+)'/g)].map(m=>m[1]));
const readNames=new Set(['wave3_document_page','wave3_document_evidence','wave3_dashboard','posted_journal_evidence',
 'receipt_trace_page','receipt_trace_detail','stock_counts_page','stock_count_detail','stock_dispositions_page',
 'stock_reservation_queue','stock_reservations_as_of','stock_reservation_history','inventory_transfers',
 'inventory_transfer_holdings','customer_statement','supplier_statement','payable_item_detail',
 'control_reconciliation_report_page','financial_statement_page','inventory_valuation_report_page','operational_report_page',
 'close_control_review_page','tax_summary_page','budget_variance_page','bank_reconciliation_options','period_governance_options']);
const reportNames=new Set(['generate_control_reconciliation_report','generate_financial_statement',
 'generate_inventory_valuation_report','generate_operational_report','generate_close_control_review',
 'generate_tax_summary','generate_budget_variance']);
function protectedContext(v){return typeof v==='string'?/stock_opening|people_|private_hr|wave4/i.test(v):
 v&&typeof v==='object'&&Object.values(v).some(protectedContext);}
function percentile(values,p){const sorted=[...values].sort((a,b)=>a-b);return sorted[Math.ceil(p*sorted.length)-1];}
function validate(config) {
 if(config.synthetic!==true||config.is_production!==false||!/^[a-z]{20}$/.test(config.project_id??'')||config.project_id===currentProject
  ||config.url!==`https://${config.project_id}.supabase.co`)throw Error('Only a separately approved isolated synthetic target is permitted');
 if(!uuid.test(config.actor_id??'')||!config.scope||!['tenant_id','legal_entity_id','branch_id'].every(k=>uuid.test(config.scope[k]??'')))throw Error('Exact synthetic actor and scope required');
 const counts=config.fixture_counts,minimum={tenants:500,legal_entities:5000,warehouses:125000,
  minimum_legal_entities_per_tenant:10,minimum_warehouses_per_entity:25,large_tenants:1,
  products_per_large_tenant:100000,stock_movements:10000000,journal_lines:20000000};
 if(!counts||Object.entries(minimum).some(([k,n])=>!Number.isSafeInteger(counts[k])||counts[k]<n)
  ||!sha.test(config.fixture_counts_query_sha256??'')||!sha.test(config.fixture_source_sha256??''))throw Error('Recorded NFR-309 per-tenant/entity fixture counts and source/query hashes required');
 if(config.fixture_counts_query_sha256!==hash(fs.readFileSync('tools/wave3/verify-target-fixtures.sql','utf8')))
  throw Error('Fixture counts must use the reviewed per-tenant/entity query');
 if(!config.environment||!['region','postgres_version','resource_size','generator_seed','distribution','cache_conditions'].every(k=>typeof config.environment[k]==='string'&&config.environment[k].length))throw Error('Measured environment and fixture distribution required');
 if(!Array.isArray(config.workloads)||Object.keys(limits).some(k=>!config.workloads.some(w=>w.kind===k)))throw Error('All six workload classes require concrete cases');
 if(ordinaryReportMetrics.some(metric=>!config.workloads.some(w=>w.kind==='ordinary_report'&&w.metric===metric)))throw Error('All five actual ordinary-report measurements required');
 const mutations=new Set();
 for(const w of config.workloads){
  if(!Object.hasOwn(limits,w.kind)||!Array.isArray(w.calls)||!Number.isInteger(w.warmup)||w.warmup<10||w.calls.length-w.warmup<100)throw Error('Each workload needs at least 10 warmups and 100 measured samples');
  for(const c of w.calls){
   if(!rpcNames.has(c.rpc)||!c.params||protectedContext(c.params)||!c.checks?.length)throw Error('Concrete scoped RPC and exact response invariants required');
   if(w.kind==='read'&&!readNames.has(c.rpc))throw Error('Read workloads require read-only RPCs');
   if(['ordinary_report','complex_report'].includes(w.kind)&&!reportNames.has(c.rpc))throw Error('Report workloads measure generation, not a cached page read');
   if(w.kind==='ordinary_report')assertOrdinaryReportBinding(w.metric,c);
   if(['save','transition','post'].includes(w.kind)&&(readNames.has(c.rpc)||reportNames.has(c.rpc)))throw Error('Command workloads require their concrete mutation class');
   for(const [k,v]of Object.entries(config.scope))if(c.params['p_'+k]!==v)throw Error('Workload scope differs from approved scope');
   if(!readNames.has(c.rpc)){
    for(const k of ['p_command_id','p_idempotency_key']){
     if(!uuid.test(c.params[k]??'')||mutations.has(c.params[k]))throw Error('Fresh mutation identities required; cached idempotent replies are not posting benchmarks');
     mutations.add(c.params[k]);
    }
   }
   if(!c.checks.every(x=>typeof x.pointer==='string'&&x.pointer.startsWith('/')&&
    (typeof x.equals==='string'||typeof x.equals==='boolean'||x.equals===null||Number.isSafeInteger(x.equals))))throw Error('Exact scalar invariants required');
  }
 }
}
function pointer(body,p){return p.split('/').slice(1).reduce((v,k)=>v?.[k.replaceAll('~1','/').replaceAll('~0','~')],body);}
function context(config){
 if(config.approval_status!=='explicit_user_approval'||typeof config.approval_reference!=='string'||!config.approval_reference.trim()
  ||!sha.test(config.approved_ledger_sha256??'')||!sha.test(config.actual_ledger_sha256??'')||config.approved_ledger_sha256!==config.actual_ledger_sha256)throw Error('Concrete installation/fixture/load approval and ledger hashes required');
 const token=process.env.WAVE3_LOAD_SESSION_TOKEN,key=process.env.WAVE3_ISOLATED_PUBLIC_KEY;
 if(!token||!key)throw Error('An existing independently authenticated isolated session is required');
 let claims;try{claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));}catch{throw Error('Malformed authenticated session claims');}
 if(claims.sub!==config.actor_id||claims.role!=='authenticated'||claims.iss!==config.url+'/auth/v1'||!uuid.test(claims.session_id??'')||!Number.isFinite(claims.exp)||claims.exp*1000<=Date.now())throw Error('Session does not match approved actor, issuer, session ID or expiry');
 const root=path.resolve('docs/verification/remaining-wave3/approved-runs'),output=path.resolve(config.evidence_path??'');
 if(!output.startsWith(root+path.sep)||path.extname(output)!=='.json')throw Error('Use a task-owned approved-runs evidence path');
 return {token,key,session_id:claims.session_id,root,output};
}
async function execute(config){
 const c=context(config);
 const evidenceDescriptor=openNewEvidence(c.output,c.root);
 const out={project_id:config.project_id,scope:config.scope,actor_id:config.actor_id,authentication_session_id:c.session_id,
  config_sha256:hash(config),ledger_sha256:config.actual_ledger_sha256,fixture_counts:config.fixture_counts,
  fixture_counts_query_sha256:config.fixture_counts_query_sha256,fixture_source_sha256:config.fixture_source_sha256,
  environment:config.environment,approval_reference:config.approval_reference,started_at:new Date().toISOString(),
  executed:true,passed:false,workloads:[],boundary:'Measured authenticated HTTP timings for the recorded installed synthetic target; fixture counts need their linked database verification. Single-session load, not concurrent database lock or native acceptance proof.'};
 try{
  for(const w of config.workloads){
   const recorded={name:w.name,kind:w.kind,warmup:w.warmup,samples:[],passed:false};out.workloads.push(recorded);
   for(let i=0;i<w.calls.length;i++){
    const call=w.calls[i],sample={ordinal:i+1,warmup:i<w.warmup,rpc:call.rpc,envelope_sha256:hash(call.params),started_at:new Date().toISOString(),success:false};recorded.samples.push(sample);
    const at=performance.now();
    try{
     const r=await fetch(config.url+'/rest/v1/rpc/'+call.rpc,{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+c.token,'Content-Profile':'api','Content-Type':'application/json'},body:JSON.stringify(call.params),signal:AbortSignal.timeout(30000)});
     sample.http_status=r.status;const raw=await r.text();sample.response_sha256=hash(raw);
     const body=JSON.parse(raw),code=body.error?.code??body.message??body.code;sample.outcome_code=outcomeCodes.has(code)?code:null;
     sample.checks=call.checks.map(x=>({pointer:x.pointer,passed:Object.is(pointer(body,x.pointer),x.equals)}));
     sample.success=r.ok&&body.success!==false&&sample.checks.every(x=>x.passed);sample.transport_state='response_received';
     if(sample.success&&w.kind==='ordinary_report'&&isAgedMetric(w.metric)){
      sample.aging_reads=[];
      const aging=await collectAgedReport(call,body.entity,config.scope,async read=>{
       const evidence={rpc:read.rpc,envelope_sha256:hash(read.params),started_at:new Date().toISOString(),success:false};sample.aging_reads.push(evidence);
       try{
        const response=await fetch(config.url+'/rest/v1/rpc/'+read.rpc,{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+c.token,'Content-Profile':'api','Content-Type':'application/json'},body:JSON.stringify(read.params),signal:AbortSignal.timeout(30000)});
        const raw=await response.text();evidence.http_status=response.status;evidence.response_sha256=hash(raw);evidence.transport_state='response_received';
        const page=JSON.parse(raw);if(!response.ok||page.success===false)throw Error('Aged source page rejected');evidence.success=true;return page;
       }catch{evidence.transport_state??='transport_uncertain';throw Error('Aged source page rejected or uncertain');}
       finally{evidence.finished_at=new Date().toISOString();}
      });
      sample.aging={item_count:aging.item_count,party_count:aging.party_count,source_read_count:aging.source_read_count,buckets_sha256:hash(aging.buckets),passed:true};
     }
    }catch{sample.success=false;sample.transport_state??='transport_uncertain';}
    finally{sample.finished_at=new Date().toISOString();sample.elapsed_ms=performance.now()-at;}
    if(!sample.success)throw Error('Rejected, uncertain or mismatched sample; retain failure evidence');
   }
   const values=recorded.samples.filter(s=>!s.warmup).map(s=>s.elapsed_ms);
   recorded.p95_ms=percentile(values,.95);recorded.sample_count=values.length;recorded.limit_ms=limits[w.kind];
   recorded.passed=w.kind==='complex_report'?recorded.p95_ms<=recorded.limit_ms:recorded.p95_ms<recorded.limit_ms;
  }
  out.passed=out.workloads.every(w=>w.passed);
 }finally{
  out.finished_at=new Date().toISOString();
  try{fs.writeFileSync(evidenceDescriptor,JSON.stringify(out,null,2)+'\n');}
  finally{fs.closeSync(evidenceDescriptor);}
  console.log(JSON.stringify({evidence_path:c.output,passed:out.passed}));
 }
 if(!out.passed)throw Error('Measured target-scale timing gate failed');
}
if(process.argv.includes('--self-test')){
 assert.equal(percentile(Array.from({length:100},(_,i)=>100-i),.95),95);
 assert.equal(pointer({exact:'90071992547409.123456'},'/exact'),'90071992547409.123456');
 assert.equal(readNames.has('post_supplier_bill'),false);assert.equal(protectedContext({kind:'stock_opening'}),true);
 assert.equal(reportNames.has('generate_financial_statement'),true);
 assert.equal(reportNames.has('financial_statement_page'),false);
 assert.ok([...reportNames].every(name=>rpcNames.has(name)));
 assert.throws(()=>validate({project_id:currentProject,synthetic:true,is_production:false}),/isolated/);
 assert.throws(()=>context({}),/approval/);
 const fakeProject='abcdefghijklmnopqrst',fakeId='00000000-0000-4000-8000-000000000001';
 const fakeScope={tenant_id:fakeId,legal_entity_id:fakeId,branch_id:fakeId};
 let serial=2;
 const nextId=()=>`00000000-0000-4000-8000-${String(serial++).padStart(12,'0')}`;
 const sample={synthetic:true,is_production:false,project_id:fakeProject,url:`https://${fakeProject}.supabase.co`,
  actor_id:fakeId,scope:fakeScope,fixture_counts:{tenants:500,legal_entities:5000,warehouses:125000,
   minimum_legal_entities_per_tenant:10,minimum_warehouses_per_entity:25,large_tenants:1,
   products_per_large_tenant:100000,stock_movements:10000000,journal_lines:20000000},
  fixture_counts_query_sha256:hash(fs.readFileSync('tools/wave3/verify-target-fixtures.sql','utf8')),
  fixture_source_sha256:'a'.repeat(64),environment:Object.fromEntries(
   ['region','postgres_version','resource_size','generator_seed','distribution','cache_conditions'].map(k=>[k,'offline fixture'])),
  workloads:Object.keys(limits).map(kind=>({name:'offline '+kind,kind,warmup:10,calls:Array.from({length:110},()=>({
   rpc:kind==='read'?'stock_count_detail':kind.endsWith('report')?'generate_control_reconciliation_report':
    kind==='save'?'upsert_stock_count':kind==='transition'?'transition_stock_count':'post_stock_adjustment',
   params:{...Object.fromEntries(Object.entries(fakeScope).map(([k,v])=>['p_'+k,v])),
    p_command_id:nextId(),p_idempotency_key:nextId()},checks:[{pointer:'/success',equals:true}]}))}))};
 sample.workloads.find(w=>w.kind==='ordinary_report').metric='subledger_reconciliation';
 for(const metric of ['trial_balance','aged_receivables','aged_payables','inventory_valuation']){
  const aged=isAgedMetric(metric),rpc=aged?'generate_control_reconciliation_report':metric==='trial_balance'?'generate_financial_statement':'generate_inventory_valuation_report';
  const payload={id:nextId(),as_of:'2026-09-30',kind:metric==='aged_receivables'?'AR':metric==='aged_payables'?'AP':'trial_balance'};
  const aging={item_count:2,party_count:2,buckets:[{currency_code:'LKR',base_currency_code:'LKR',bucket:0,item_count:2,amount:'2.000000',base_amount:'2.000000'}]};
  sample.workloads.push({name:'offline '+metric,kind:'ordinary_report',metric,warmup:10,calls:Array.from({length:110},()=>({rpc,
   params:{...Object.fromEntries(Object.entries(fakeScope).map(([k,v])=>['p_'+k,v])),p_command_id:nextId(),p_idempotency_key:nextId(),p_payload:{...payload,id:nextId()}},
   checks:[{pointer:'/success',equals:true}],...(aged?{aging}:{})}))});
 }
 validate(sample);
 const deficient=structuredClone(sample);deficient.fixture_counts.minimum_legal_entities_per_tenant=9;
 assert.throws(()=>validate(deficient),/per-tenant/);
 deficient.fixture_counts.minimum_legal_entities_per_tenant=10;deficient.fixture_counts.minimum_warehouses_per_entity=0;
 assert.throws(()=>validate(deficient),/per-tenant/);
 const oldQuery=structuredClone(sample);oldQuery.fixture_counts_query_sha256='b'.repeat(64);
 assert.throws(()=>validate(oldQuery),/reviewed per-tenant/);
 const staleRequest=structuredClone(sample);staleRequest.workloads[2].calls[1].params.p_command_id=staleRequest.workloads[1].calls[0].params.p_command_id;
 assert.throws(()=>validate(staleRequest),/Fresh mutation/);
 console.log('Offline load harness guards and nearest-rank p95 passed; no connections opened.');
}else{
 const configPath=process.argv.slice(2).find(a=>a.endsWith('.json'));
 if(!configPath)throw Error('Usage: node run-target-load.mjs config.json [--execute]. Default validates the plan only.');
 const config=JSON.parse(fs.readFileSync(configPath,'utf8'));validate(config);
 if(process.argv.includes('--execute'))await execute(config);
 else console.log(JSON.stringify({project_id:config.project_id,config_sha256:hash(config),executed:false,classes:config.workloads.map(w=>w.kind)}));
}
