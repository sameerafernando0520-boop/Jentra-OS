import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {artifactTag, writeNewJson} from './strict-candidate-evidence.mjs';

// Preparation only. A new tail changes the executed stack: historical 45-stack
// pgTAP counts are retained as history and are never relabelled as 46-stack proof.
const base = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const [queryPath,refreshPath,candidatePath,assertionsPath,iterationTag='',selectedDate='20261003'] = process.argv.slice(2);
if (iterationTag && !/^[a-z0-9-]+$/.test(iterationTag)) throw Error('Use a simple lowercase additive artifact tag.');
const dateTag=artifactTag(selectedDate);
if (![queryPath,refreshPath,candidatePath,assertionsPath].every(file=>file&&fs.existsSync(file))) throw Error('Pass existing composed query, fresh read-only refresh, tail candidate and assertions sources.');
const head = execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
const refresh = read(refreshPath), prior = read(base+'migration-order-final-20260930-45.json');
if (refresh.head !== head || refresh.project_id !== 'xpdoufauvrbdmxgngetv' || !refresh.observed_at) throw Error('Refresh must bind the currently observed repository/project.');
const expectedHelpers={flow_residual:'c0933ed943663701bbc7e01a1c21831f',wave3_lock_open_period:'a316c04eef62ba1a43d49ea4d5261ca2',flow_post_journal:'bebe95827a7e5ac3f2192d0f7acd38b4',flow_allocate:'e6e9f68ec7d8aca03be157816fe8eef6'};
if (refresh.shared_helpers?.length!==4 || refresh.shared_helpers.some(row=>expectedHelpers[row.name]!==row.source_md5)) throw Error('Fresh installed finance helper baseline drift.');
const query = fs.readFileSync(queryPath,'utf8').replace(/^\uFEFF/,''), boundary = query.indexOf('create extension if not exists pgtap');
if (!/^\s*begin;/i.test(query) || boundary < 0 || !query.includes('finish(true)') || !/rollback;\s*$/i.test(query) || /^\s*commit\s*;/im.test(query)) throw Error('Require a strict finish(true)/rollback composition.');
const prefix = query.slice(0,boundary), installed = new Set(refresh.migrations.map(row=>row.version));
const candidates = prior.candidates.map(row=>({...row,current_sha256:hash(row.path),offset:prefix.indexOf(fs.readFileSync(row.path,'utf8')),installed_now:installed.has(row.version)}));
if (candidates.length !== 45 || candidates.some((row,index)=>row.current_sha256!==row.sha256 || row.installed_now || row.offset < 0 || (index&&row.offset<=candidates[index-1].offset))) throw Error('Historical 45-stack hash/order/install drift.');
const candidate = fs.readFileSync(candidatePath,'utf8'), assertions = fs.readFileSync(assertionsPath,'utf8'), offset = prefix.indexOf(candidate);
if (offset <= candidates.at(-1).offset || !query.includes(assertions) || query.indexOf(assertions) >= query.lastIndexOf('set constraints all immediate;')) throw Error('Policy tail/assertions composition order differs from reviewed wrapper.');
const name = candidatePath.split('/').at(-1), version = name.split('_')[0];
if (!/^\d{14}_wave3_negative_stock_policy\.sql$/.test(name) || installed.has(version)) throw Error('Require a new unapplied dated policy candidate.');
candidates.push({path:candidatePath,version,ordinal:46,sha256:hash(candidatePath),current_sha256:hash(candidatePath),installed:false,installed_now:false,offset,requires_previous_candidates:true});
const compositionCandidates = fs.readdirSync('supabase/migrations').filter(file=>file.endsWith('.sql')).map(file=>({file:'supabase/migrations/'+file,body:fs.readFileSync('supabase/migrations/'+file,'utf8')})).filter(row=>prefix.includes(row.body));
if (compositionCandidates.length !== 46 || compositionCandidates.some(row=>!candidates.some(candidate=>candidate.path===row.file))) throw Error('Composed SQL includes an unreviewed candidate or omits a required one.');
const exactOrder = candidates.map(({ordinal,path,sha256})=>({ordinal,path,sha256}));
const manifest = {
  generated_at:new Date().toISOString(),head,project_id:refresh.project_id,
  installed_count:refresh.migrations.length,latest_installed:refresh.migrations.at(-1),api_functions:refresh.api_catalogue.length,
  shared_helpers:refresh.shared_helpers,
  candidate_count:46,candidates:candidates.map(({offset,...row})=>row),
  exact_order_sha256:crypto.createHash('sha256').update(JSON.stringify(exactOrder)).digest('hex'),
  historical45:{file:base+'migration-order-final-20260930-45.json',sha256:hash(base+'migration-order-final-20260930-45.json')},
  composition:{file:queryPath,sha256:hash(queryPath),strict_finish:true,final_rollback:true},
  assertions:{file:assertionsPath,sha256:hash(assertionsPath)},
  live_refresh:{file:refreshPath,sha256:hash(refreshPath),observed_at:refresh.observed_at},
  boundary:'Source/dependency/strict-rollback preparation only. No SQL sent by this script; no installation. Historical 45-stack results do not verify the new 46-stack composition.',
};
const manifestPath = base+`migration-order-negative-stock-policy${iterationTag?'-'+iterationTag:''}-${dateTag}-46.json`;
const packagePath = base+`database-installation-package-negative-stock-policy${iterationTag?'-'+iterationTag:''}-${dateTag}-46.json`;
if([manifestPath,packagePath].some(file=>fs.existsSync(file)))throw Error('Retain previous prepared source/order evidence; choose an unused iteration/date.');
writeNewJson(manifestPath,manifest);
const historicalPackagePath = base+'database-installation-package-20261003.json';
const historical = read(historicalPackagePath);
const previousTailPhase=historical.phases.find(phase=>phase.name==='inventory_dashboard_observability');
const acceptanceIndex=historical.phases.findIndex(phase=>phase.name==='installed_synthetic_checks');
if (!previousTailPhase || acceptanceIndex<1) throw Error('Historical installation dependency phases drifted.');
const tailPhase={...structuredClone(previousTailPhase),name:'negative_stock_policy',dependencies:['inventory_dashboard_observability'],ordinals:[46,46],
  candidates:[manifest.candidates.at(-1)],status:'prepared_not_installed',
  tasks:[`Review/apply ordinal46: ${candidatePath} at SHA-256 ${hash(candidatePath)}`],
  approval:'Existing isolated target/resource/actor/native/restore approval bindings remain required; the policy decision authorizes implementation only.'};
const phases=structuredClone(historical.phases);
phases.splice(acceptanceIndex,0,tailPhase);
phases.find(phase=>phase.name==='installed_synthetic_checks').dependencies=['negative_stock_policy'];
const rollback=structuredClone(historical.rollback);
rollback.splice(acceptanceIndex,0,{name:tailPhase.name,ordinals:[46,46],triggers:tailPhase.rollback_triggers,rollback:tailPhase.rollback});
const installation = {...historical,generated_at:new Date().toISOString(),head,refresh_path:refreshPath,refresh_sha256:hash(refreshPath),observed_at:refresh.observed_at,
  installed_count:refresh.migrations.length,latest_installed:refresh.migrations.at(-1),api_functions:refresh.api_catalogue.length,
  shared_helpers:refresh.shared_helpers.map(row=>({...row,matches:true})),
  manifest_path:manifestPath,candidates:manifest.candidates,exact_order_sha256:manifest.exact_order_sha256,
  historical45_package:{file:historicalPackagePath,sha256:hash(historicalPackagePath)},
  tail_policy_candidate:{ordinal:46,path:candidatePath,sha256:hash(candidatePath),accounting_policy_approved:true,installation_approved:false},
  compatibility:{...historical.compatibility,status:'historical45_capture_retained_new46_policy_tail_requires_fresh_compatibility_review',new_tail_review:null,
    caveat:'Zero breaking/eight potential warnings describe the historical 45 bodies only. They do not establish that the added tail has zero additional compatibility risks.'},
  phases,rollback,
  fresh_strict_execution:null,
  approval_binding_missing:historical.approval_binding_missing.map(item=>item.replace('exact45candidate','exact46candidate')),
  boundary:'Prepared exact 46-stack installation package only. Selected accounting policy is approved for development. No installation, persistent fixture, independent authenticated session, native launch or acceptance/production operation is authorized by this package.',
};
writeNewJson(packagePath,installation);
console.log(JSON.stringify({head,candidates:46,historical45_hashes_match:true,installed:refresh.migrations.length,manifest:manifestPath,package:packagePath,fresh_sql_execution:false}));
