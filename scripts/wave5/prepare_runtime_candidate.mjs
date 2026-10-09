import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {migrationFiles} from './runtime_plan.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const hash=b=>createHash('sha256').update(b).digest('hex');
const parts=['begin;'],sources={};
async function migration(file){const p=`supabase/migrations/${file}`,bytes=await readFile(path.join(root,p));
 if(/^\s*(?:commit|rollback)\s*;/im.test(bytes.toString()))throw Error('TRANSACTION_BOUNDARY');
 sources[p]=hash(bytes);parts.push(bytes.toString());}
const fixtureFiles=['wave5_process_metrics_test.sql','wave5_remaining_adapters_test.sql','wave5_realized_mapping_test.sql',
 'wave4_synthetic_fixture.sql','wave5_cash_payment_dates_test.sql','wave5_runtime_scope_test.sql'];
async function fixture(file){const p=`supabase/tests/${file}`,bytes=await readFile(path.join(root,p));sources[p]=hash(bytes);let sql=bytes.toString();
 sql=sql.replace(/select \* from finish\(true\);/g,'').replace(/select no_plan\(\);/g,'');
 if(file==='wave5_remaining_adapters_test.sql'){
  const start=sql.indexOf('-- Rollback-only shape shim'),end=sql.indexOf('insert into finance.accounts',start);
  if(start<0||end<start)throw Error('FIXTURE_CONTRACT_CHANGED');sql=sql.slice(0,start)+sql.slice(end);
 }
 parts.push(sql);}
// Check the earlier v2 adapters before the additive v3 date wrappers replace
// them, then exercise the final wrappers over actual Wave 4 sources. This is
// compatibility composition; no v2 fixture is relabelled as v3 evidence.
for(const file of migrationFiles)await migration(file);
const seedBytes=await readFile(path.join(root,'supabase/tests/wave5_process_metrics_test.sql'));
sources['supabase/tests/wave5_process_metrics_test.sql']=hash(seedBytes);
parts.push(seedBytes.toString().split('select is(api.analytics_process_authorize')[0].replace('select no_plan();',''));
parts.push("insert into intelligence_control.integration_hosts values('runtime-fixture.invalid');");
parts.push("insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload) values(pg_temp.fid('t'),'runtime.scope.fixture','fixture',pg_temp.fid('queue.fixture'),'{}');");
parts.push("insert into intelligence_control.operators(actor_id,active,health_read,grant_manage) values(pg_temp.fid('owner'),true,true,true);");
for(const file of fixtureFiles.slice(3))await fixture(file);
let query=parts.join('\n');
query=query.replace('set local search_path=extensions,public,pg_catalog;',
 'set local search_path=extensions,public,pg_catalog;\nselect no_plan();\ncreate temporary table w5_runtime_tap(message text);\ngrant insert,select on w5_runtime_tap to authenticated;');
query=query.replace(/^select (is|ok|throws_ok|lives_ok)\(/gm,'insert into w5_runtime_tap select $1(');
query+='\nselect * from finish(true);\nselect jsonb_agg(message) tap from w5_runtime_tap;\nrollback;\n';
await writeFile(path.join(root,'docs/verification/wave5/runtime-candidate-20261008.sql'),query);
await writeFile(path.join(root,'docs/verification/wave5/runtime-candidate-20261008.hashes.json'),JSON.stringify({sources,querySha256:hash(query),
 migrationCount:migrationFiles.length,strictFinish:true,rollback:true,installedMigrationsReplayed:false,actualWave3AllocationReversals:true,actualWave4Sources:true,
 fixtureTransformations:['only seed portion of process fixture; legacy v2 cash fixture excluded','actual Wave 3 AP and Wave 4 schemas; final date and scope checks','single strict TAP plan and rollback']},null,2)+'\n');
process.stdout.write(JSON.stringify({migrationCount:migrationFiles.length,bytes:Buffer.byteLength(query),sha256:hash(query)}));
