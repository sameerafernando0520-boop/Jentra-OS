// Isolated query verification with the existing pinned build-only PGlite 0.5.12.
// Minimal contract-shaped tables, synthetic records, no Supabase/Auth/network.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {PGlite} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js';
import {pgcrypto} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
import {assessHostedAccounting} from '../../../tools/wave5/hosted_accounting.mjs';

const source=await readFile(new URL('../../../tools/wave5/hosted_accounting_readonly.sql',import.meta.url),'utf8');
const db=new PGlite({extensions:{pgcrypto}}),checks=[];
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7';
const check=(label,condition)=>{assert.ok(condition,label);checks.push(label);};
try{
 await db.exec(`create schema intelligence_control;create schema analytics;create schema core;create schema extensions;
 create extension pgcrypto with schema extensions;
 create table intelligence_control.runtime_worker_scopes(runtime_id uuid,tenant_id uuid,legal_entity_id uuid,branch_id uuid,enabled boolean,issued_at timestamptz,expires_at timestamptz);
 create table core.branches(id uuid,tenant_id uuid,legal_entity_id uuid,status text);
 create table intelligence_control.edge_authorities(runtime_id uuid,enabled boolean,issued_at timestamptz,expires_at timestamptz);
 create table analytics.pipeline_forecasts(id uuid,tenant_id uuid,legal_entity_id uuid,branch_id uuid,source_hash text);
 create table intelligence_control.model_invocations(invocation_id uuid primary key,tenant_id uuid,source_id uuid,source_hash text,request jsonb,created_at timestamptz default now());
 create table intelligence_control.model_outcomes(invocation_id uuid primary key,state text,tokens numeric(20,0));
 create table intelligence_control.usage_reservations(tenant_id uuid,invocation_id uuid,metric_code text,period_start timestamptz,reserved_units numeric(20,0),primary key(tenant_id,invocation_id));
 create table intelligence_control.usage_events(tenant_id uuid,invocation_id uuid,event_id uuid,quantity numeric(20,0),primary key(tenant_id,event_id),unique(tenant_id,invocation_id));
 create table intelligence_control.usage_corrections(tenant_id uuid,original_event_id uuid,quantity numeric(20,0));
 create table intelligence_control.quota_periods(tenant_id uuid,metric_code text,period_start timestamptz,period_end timestamptz,settled_units numeric(20,0),reserved_units numeric(20,0));
 create table intelligence_control.integration_subscriptions(id uuid,tenant_id uuid,legal_entity_id uuid,branch_id uuid);
 create table intelligence_control.delivery_heads(id uuid,tenant_id uuid,subscription_id uuid,event_id uuid,invocation_id uuid,usage_event_id uuid,state text,attempt int);
 create table intelligence_control.delivery_attempts(tenant_id uuid,delivery_id uuid,key_version int,claimed_at timestamptz);
 create table intelligence_control.delivery_outcomes(tenant_id uuid,delivery_id uuid,attempt int,state text,http_status int);
 create table intelligence_control.edge_receiver_receipts(runtime_id uuid,tenant_id uuid,legal_entity_id uuid,branch_id uuid,subscription_id uuid,event_id uuid,key_version int,payload bytea,sha256 text,received_at timestamptz);`);
 await db.query(`insert into intelligence_control.runtime_worker_scopes values($1,$2,$3,$4,true,now()-interval '1 minute',now()+interval '1 hour');`,[runtime,id(1),id(2),id(3)]);
 await db.query(`insert into core.branches values($1,$2,$3,'active');`,[id(3),id(1),id(2)]);
 await db.query(`insert into intelligence_control.edge_authorities values($1,true,now()-interval '1 minute',now()+interval '1 hour');`,[runtime]);
 await db.query(`insert into analytics.pipeline_forecasts values($1,$2,$3,$4,$5);`,[id(4),id(1),id(2),id(3),'a'.repeat(64)]);
 await db.query(`insert into intelligence_control.model_invocations(invocation_id,tenant_id,source_id,source_hash,request) values($1,$2,$3,$4,$5);`,
  [id(5),id(1),id(4),'a'.repeat(64),JSON.stringify({usageEventId:id(6),maxTokens:'2000',periodStart:'2026-10-01T00:00:00Z',periodEnd:'2026-11-01T00:00:00Z'})]);
 await db.query(`insert into intelligence_control.model_outcomes values($1,'settled',150);`,[id(5)]);
 await db.query(`insert into intelligence_control.usage_reservations values($1,$2,'ai.tokens','2026-10-01',2000),($1,$3,'webhook.deliveries','2026-10-01',1);`,[id(1),id(5),id(10)]);
 await db.query(`insert into intelligence_control.usage_events values($1,$2,$3,150),($1,$4,$5,1);`,[id(1),id(5),id(6),id(10),id(11)]);
 await db.query(`insert into intelligence_control.quota_periods values($1,'ai.tokens','2026-10-01','2026-11-01',150,0),($1,'webhook.deliveries','2026-10-01','2026-11-01',1,0);`,[id(1)]);
 await db.query(`insert into intelligence_control.integration_subscriptions values($1,$2,$3,$4);`,[id(7),id(1),id(2),id(3)]);
 await db.query(`insert into intelligence_control.delivery_heads values($1,$2,$3,$4,$5,$6,'acknowledged',2);`,[id(8),id(1),id(7),id(9),id(10),id(11)]);
 // A key-1 receipt followed by an acknowledged key-2 duplicate is valid.
 await db.query(`insert into intelligence_control.delivery_attempts values($1,$2,1,now()-interval '30 seconds'),($1,$2,2,now()-interval '10 seconds');`,[id(1),id(8)]);
 await db.query(`insert into intelligence_control.delivery_outcomes values($1,$2,2,'acknowledged',200);`,[id(1),id(8)]);
 await db.query(`insert into intelligence_control.edge_receiver_receipts values($1,$2,$3,$4,$5,$6,1,convert_to('signed event','UTF8'),encode(extensions.digest(convert_to('signed event','UTF8'),'sha256'),'hex'),now()-interval '20 seconds');`,[runtime,id(1),id(2),id(3),id(7),id(9)]);
 const snapshot=async()=>{
  const output=await db.exec(source);
  const rows=output.flatMap(result=>result.rows??[]);
  assert.equal(rows.length,1);
  return rows[0].hosted_accounting_snapshot;
 };
 let actual=await snapshot();
 check('Exact read-only SQL executes in PostgreSQL and reconciles settled model and rotated-key delivery',assessHostedAccounting(actual).ledgerReconciled);
 check('Independent worked quota example remains exactly 150 tokens and one webhook',actual.quotas.some(q=>q.expectedSettled==='150')&&actual.quotas.some(q=>q.expectedSettled==='1'));
 await db.query(`insert into intelligence_control.usage_corrections values($1,$2,10);`,[id(1),id(6)]);
 await db.exec(`update intelligence_control.quota_periods set settled_units=140 where metric_code='ai.tokens';`);
 actual=await snapshot();
 check('Ten-unit correction reconciles to 140 with no multiplication across joins',actual.quotas.some(q=>q.expectedSettled==='140')&&assessHostedAccounting(actual).ledgerReconciled);
 await db.query(`insert into intelligence_control.usage_reservations values($1,$2,'ai.tokens','2026-10-01',2000);`,[id(1),id(12)]);
 await db.exec(`update intelligence_control.quota_periods set reserved_units=2000 where metric_code='ai.tokens';`);
 actual=await snapshot();
 check('Unsettled reservation keeps exactly 2000 units in the quota balance',actual.quotas.some(q=>q.expectedReserved==='2000')&&assessHostedAccounting(actual).ledgerReconciled);
 await db.query(`insert into intelligence_control.model_invocations(invocation_id,tenant_id,source_id,source_hash,request) select $1,tenant_id,source_id,source_hash,request from intelligence_control.model_invocations;`,[id(12)]);
 await db.query(`insert into intelligence_control.model_outcomes values($1,'unknown',null);`,[id(12)]);
 actual=await snapshot();
 check('Unknown persisted model outcome remains unresolved with its reservation retained',assessHostedAccounting(actual).failures.includes('MODEL_OUTCOME_UNRESOLVED'));
 await db.query(`delete from intelligence_control.model_outcomes where invocation_id=$1;`,[id(12)]);
 await db.query(`delete from intelligence_control.model_invocations where invocation_id=$1;`,[id(12)]);
 await db.exec(`update intelligence_control.edge_receiver_receipts set sha256=repeat('0',64);`);
 check('Corrupted receiver payload hash cannot pass ledger reconciliation',assessHostedAccounting(await snapshot()).failures.includes('DELIVERY_ACKNOWLEDGEMENT_MISMATCH'));
 await db.exec(`update intelligence_control.edge_receiver_receipts set sha256=encode(extensions.digest(payload,'sha256'),'hex');update intelligence_control.edge_authorities set expires_at=now()-interval '1 second';`);
 check('Expired runtime remains blocked even with historically matching ledger',assessHostedAccounting(await snapshot()).failures.includes('RUNTIME_AUTHORITY_INACTIVE'));
 await db.exec(`update intelligence_control.edge_authorities set expires_at=now()+interval '1 hour';update intelligence_control.quota_periods set settled_units=settled_units+1 where metric_code='ai.tokens';`);
 check('One-token counter drift is detected against independent reservation/event/correction totals',assessHostedAccounting(await snapshot()).failures.includes('QUOTA_BALANCE_MISMATCH'));
 await db.exec(`update intelligence_control.quota_periods set settled_units=settled_units-1 where metric_code='ai.tokens';`);
 await db.query(`insert into intelligence_control.quota_periods values($1,'ai.tokens','2026-10-01','2026-11-01',999,999);`,[id(99)]);
 actual=await snapshot();
 check('Foreign tenant counter mismatch is excluded by exact runtime scope',actual.quotas.length===2&&assessHostedAccounting(actual).ledgerReconciled);
 const version=(await db.query('select version()')).rows[0].version;
 const report={kind:'isolated-hosted-accounting-query-verification',observedAt:new Date().toISOString(),
  engine:version,passed:checks.length,checks,sqlSha256:createHash('sha256').update(source).digest('hex'),
  hostedDatabaseQueried:false,hostedModelResponseVerified:false,externalDeliveryVerified:false,
  boundary:'Contract-shaped synthetic tables in isolated PGlite. Actual installed schemas, RLS, grants, Auth and hosted model/delivery remain unverified.'};
 await writeFile(new URL('accounting-postgres-after-wrapper-fix.json',import.meta.url),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({passed:checks.length,engine:version,hostedDatabaseQueried:false}));
}finally{await db.close();}
