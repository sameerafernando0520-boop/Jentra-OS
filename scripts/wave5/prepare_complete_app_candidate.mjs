import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),base='docs/verification/wave5/';
const sha=b=>createHash('sha256').update(b).digest('hex');
const inventory=JSON.parse(await readFile(path.join(root,base+'complete-app-migration-inventory-20261009.json'),'utf8'));
const migrations=[...inventory.pending.map(m=>m.path),
 'supabase/migrations/20261009120000_wave5_supabase_runtime.sql','supabase/migrations/20261009123000_wave5_supabase_schedule.sql'].sort();
if(new Set(migrations).size!==71)throw Error('MIGRATION_CLOSURE_CHANGED');
const sources={},parts=['begin;'];
for(const file of migrations){const bytes=await readFile(path.join(root,file)),sql=bytes.toString();
 if(/^\s*(?:commit|rollback)\s*;/im.test(sql))throw Error('TRANSACTION_BOUNDARY:'+file);
 sources[file]=sha(bytes);parts.push(sql.replace(/^\s*begin;\s*$/gm,''));}
const earlier=await readFile(path.join(root,base+'runtime-candidate-20261008.sql'),'utf8');
const start=earlier.indexOf('create extension if not exists pgtap with schema extensions;'),end=earlier.lastIndexOf('select * from finish(true);');
if(start<0||end<=start)throw Error('EXISTING_FIXTURE_BOUNDARY_CHANGED');
parts.push(earlier.slice(start,end));
for(const test of ['supabase/tests/wave5_supabase_runtime_test.sql','supabase/tests/wave5_supabase_setup_test.sql']){
 const fixture=await readFile(path.join(root,test));sources[test]=sha(fixture);
 parts.push(fixture.toString().replace(/^select (is|ok|throws_ok|lives_ok)\(/gm,'insert into w5_runtime_tap select $1('));
}
parts.push('select * from finish(true);\nselect jsonb_agg(message) tap from w5_runtime_tap;\nrollback;');
const query=parts.join('\n');
await writeFile(path.join(root,base+'complete-app-candidate-20261009.sql'),query);
await writeFile(path.join(root,base+'complete-app-candidate-20261009.hashes.json'),JSON.stringify({sources,querySha256:sha(query),migrationCount:migrations.length,strictFinish:true,rollback:true,installedMigrationsReplayed:false,
 fixtureScope:'Existing 63 policy assertions over full missing closure plus Edge scope/lease/secret/scheduling contract checks. Injected Auth claims, entirely rolled back. No real MFA or delivery.'},null,2)+'\n');
console.log(JSON.stringify({migrations:migrations.length,bytes:Buffer.byteLength(query),querySha256:sha(query)}));
