// Create a new public-artifact reader. Never edit either frozen predecessor.
import {readFile,writeFile,lstat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const previous='scripts/wave5/prepare_current_runtime_review_20261010_r5_a2.mjs';
const next='scripts/wave5/prepare_current_runtime_review_20261010_r5_a3.mjs';
const previousSha='64c2f703fd4d96b4cf87dc0b1797f39ecbcfdd90e21a44182f69baabe39deb9c';
const failed=base+'failed-runtime-composer-check-20261012-r5-a2.json';
const latest=base+'narrow-live-counts-20261012-r5.json';
const latestSha='a241a86d362fc0b21bdb0eb0e8ebcad2b8b8677147a9fd02c66010db4caf9e2d';
const sha=b=>createHash('sha256').update(b).digest('hex');
const oldBytes=await readFile(path.join(root,previous));
if(sha(oldBytes)!==previousSha)throw Error('FROZEN_A2_READER_CHANGED');
const latestBytes=await readFile(path.join(root,latest));
if(sha(latestBytes)!==latestSha)throw Error('ACTUAL_OCT12_COUNT_READ_CHANGED');
const contextBytes=await readFile(path.join(root,base+'complete-live-preflight-20261010-r5-read-context.json'));
const context=JSON.parse(contextBytes);
const keys=['projectId','readOnly','observedAt','contextRecordedAt','query','operations','liveWrites'].sort();
if(!isDeepStrictEqual(Object.keys(context).sort(),keys)||context.readOnly!==true||context.liveWrites!==false||
 context.projectId!=='xpdoufauvrbdmxgngetv'||!isDeepStrictEqual(context.operations,['execute_sql','list_migrations','list_edge_functions'])||
 !Number.isFinite(Date.parse(context.contextRecordedAt))||Date.parse(context.contextRecordedAt)<Date.parse(context.observedAt))throw Error('SAVED_CONTEXT_SCHEMA_CHANGED');
for(const file of [failed,next])try{await lstat(path.join(root,file));throw Error('IMMUTABLE_SUCCESSOR_OUTPUT_EXISTS:'+file);}catch(e){if(e.code!=='ENOENT')throw e;}
const failure={kind:'failed-public-runtime-composer-check',recordedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',composer:{path:previous,sha256:previousSha},
 actualToolResult:{chunkId:'007569',sessionId:72319,exitCode:1},
 command:'node scripts/wave5/prepare_current_runtime_review_20261010_r5_a2.mjs check',
 error:'CURRENT_CONNECTED_READ_CONTEXT_REQUIRED',
 cause:'The preserved read-context uses operations/contextRecordedAt/liveWrites and has seven exact fields. The reader expected nonexistent kind/tools and operation flags. Two later timestamp references also used nonexistent recordedAt.',
 executionTimestampClaimed:false,outputsWritten:false,SDKJobsExecuted:false,nativeActionsPerformed:false,
 SQLExecuted:false,AuthOperations:false,workerOperations:false,ownerAcceptanceChanged:false};
const failureBytes=Buffer.from(JSON.stringify(failure,null,2)+'\n');
let text=oldBytes.toString('utf8');
function replace(a,b,count=1){if(text.split(a).length!==count+1)throw Error('EXACT_REPAIR_LOCATION_COUNT_REQUIRED');text=text.split(a).join(b);}
replace("const self='"+previous+"'","const self='"+next+"'");
replace("for(const file of [self,'scripts/wave5/prepare_current_runtime_review_20261010_r5.mjs'",
 "for(const file of [self,'"+previous+"','"+failed+"','"+latest+"','scripts/wave5/prepare_runtime_reader_successor_20261012_r5_a3.mjs','scripts/wave5/prepare_current_runtime_review_20261010_r5.mjs'");
replace('async function audit(){',
 "must(startup.get('"+previous+"')==='"+previousSha+"','FROZEN_A2_READER_CHANGED');\n"+
 "must(startup.get('"+failed+"')==='"+sha(failureBytes)+"','ACTUAL_A2_READER_FAILURE_CHANGED');\n"+
 "must(startup.get('"+latest+"')==='"+latestSha+"','ACTUAL_OCT12_COUNT_READ_CHANGED');\nasync function audit(){");
replace("context.kind==='read-only-r5-runtime-metadata-observation'&&context.projectId===projectId&&context.observedAt===live.observedAt&&context.readOnly===true&&eq(context.tools,['supabase_execute_sql','supabase_list_migrations','supabase_list_edge_functions'])&&context.sqlInstalled===false&&context.accountsChanged===false&&context.credentialsInspected===false&&context.edgeDeployed===false",
 "eq(Object.keys(context).sort(),['projectId','readOnly','observedAt','contextRecordedAt','query','operations','liveWrites'].sort())&&context.projectId===projectId&&context.observedAt===live.observedAt&&context.readOnly===true&&eq(context.operations,['execute_sql','list_migrations','list_edge_functions'])&&context.liveWrites===false&&Number.isFinite(Date.parse(context.contextRecordedAt))&&Date.parse(context.contextRecordedAt)>=Date.parse(live.observedAt)");
replace('a.context.recordedAt','a.context.contextRecordedAt',2);
replace('await bind(context.query.path,context.query.sha256);',
 "await bind(context.query.path,context.query.sha256);\n"+
 " const latestCounts=await json('"+latest+"','"+latestSha+"'),latestCountRows=connectorRows(latestCounts);\n"+
 " must(latestCounts.kind==='narrow-live-count-refresh'&&latestCounts.projectId===projectId&&latestCounts.readOnly===true&&latestCounts.liveWrites===false&&latestCounts.ownerApproved===false&&latestCounts.installedAdditionalMigrations===0&&latestCountRows.length===1&&eq(Object.keys(latestCountRows[0]).sort(),['api_functions','migrations','observed_at'])&&latestCountRows[0].migrations===43&&latestCountRows[0].api_functions===107&&latestCounts.counts.migrations===43&&latestCounts.counts.apiFunctions===107&&latestCountRows[0].observed_at===latestCounts.observedAt&&Date.parse(latestCounts.observedAt)>Date.parse(live.observedAt),'ACTUAL_NARROW_OCT12_COUNTS_REQUIRED');");
replace('return {bound,missing,ready:true,original,prior,scopeSha256',
 'return {bound,missing,ready:true,latestCounts,original,prior,scopeSha256');
replace('  retainedReaderAuditFailure:{',
 "  retainedReadContextReaderFailure:{record:'"+failed+"',sha256:a.bound.get('"+failed+"'),predecessor:{path:'"+previous+"',sha256:'"+previousSha+"'},actualExitCode:1,outputsWritten:false,repair:'Exact saved seven-field context schema and actual contextRecordedAt, with all raw live/ledger/provider/source guards preserved.'},\n"+
 "  latestNarrowLiveCounts:{record:'"+latest+"',sha256:a.bound.get('"+latest+"'),observedAt:a.latestCounts.observedAt,migrations:43,apiFunctions:107,fullProviderRefresh:false,immediatePreflight:false},\n  retainedReaderAuditFailure:{");
replace('ledgerListReadContextRecordedAt:a.context.contextRecordedAt,',
 "ledgerListReadContextRecordedAt:a.context.contextRecordedAt,latestNarrowCountObservation:{record:'"+latest+"',sha256:a.bound.get('"+latest+"'),observedAt:a.latestCounts.observedAt,migrations:43,apiFunctions:107,providerAndCollisionRefresh:false},");
replace('\\n\\nThe first r4 focused attempt',
 "\\n\\nThe separate latest three-field live count read at ${a.latestCounts.observedAt} still reports 43 migrations and 107 API functions. It rereads no provider, ledger name, access, Auth or collision and does not replace the dated full metadata snapshot or the complete preflight required immediately before approved operations. The failed r5 and a2 reader checks and frozen source bytes are retained. This a3 reader validates the historical records using their actual schemas; their failures remain failures.\\n\\nThe first r4 focused attempt");
text='// NEW a3 successor: preserve both failed readers; validate exact saved context schema/timestamp and bind the separate actual Oct12 narrow count read.\n'+text;
const nextBytes=Buffer.from(text);
await writeFile(path.join(root,failed),failureBytes,{flag:'wx'});
await writeFile(path.join(root,next),nextBytes,{flag:'wx'});
if(sha(await readFile(path.join(root,previous)))!==previousSha||sha(await readFile(path.join(root,latest)))!==latestSha||
 !Buffer.from(await readFile(path.join(root,base+'complete-live-preflight-20261010-r5-read-context.json'))).equals(contextBytes))throw Error('INPUT_CHANGED_DURING_SUCCESSOR_CREATION');
console.log(JSON.stringify({successor:{path:next,sha256:sha(nextBytes)},failure:{path:failed,sha256:sha(failureBytes)},
 originalContextPreserved:true,predecessorPreserved:true,SDKJobsExecuted:false,sourceInputsChanged:false,liveWrites:false}));
