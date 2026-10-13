import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual as equal } from 'node:util';
import { PROJECT, ORGANIZATION, BUNDLE, loadApprovedInputs, createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes, isUuid } from './runtime_contract.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const authFile=base+'auth-admin-provisioning-20261013-r5-1791877892653/99-result.json',
 authSha='f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb';
const mfaFile=base+'genuine-mfa-20261013-r5-1791878507585/99-result.json',
 mfaSha='af4e9dec3987f5d6ba8c49fc1162be1374f93a14c043e46065119297a73e0bba';
const bootstrapSha='6c327db3699b444bf41e0be0d3d4a08334c9fd573d38b8fe0234f2e1ea665fa5';
const labels=['proposer','approver','executor','billing-admin','operator','foreign-member'];
const planCodes=['w5_runtime_20261008','w5_load_20261008','w5_quota10_20261008','w5_foreign_20261008'];
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};

const assertions=`
DO $bounded_assertions$ BEGIN
 IF (SELECT count(*) FROM w5_runtime_scopes)<>500 THEN RAISE EXCEPTION 'EXACT_500_SCOPES_REQUIRED';END IF;
 IF (SELECT count(*) FROM w5_runtime_accounts a JOIN auth.users u ON u.id=a.user_id WHERE u.email_confirmed_at IS NOT NULL)<>6 THEN RAISE EXCEPTION 'SIX_GENUINE_CONFIRMED_USERS_REQUIRED';END IF;
 IF (SELECT count(*) FROM core.tenants WHERE id IN(SELECT tenant_id FROM w5_runtime_scopes))<>500 THEN RAISE EXCEPTION 'EXACT_500_TENANTS_REQUIRED';END IF;
 IF (SELECT count(*) FROM core.legal_entities WHERE tenant_id IN(SELECT tenant_id FROM w5_runtime_scopes))<>500 THEN RAISE EXCEPTION 'EXACT_500_ENTITIES_REQUIRED';END IF;
 IF (SELECT count(*) FROM core.branches WHERE tenant_id IN(SELECT tenant_id FROM w5_runtime_scopes))<>501 THEN RAISE EXCEPTION 'EXACT_501_BRANCHES_REQUIRED';END IF;
 IF (SELECT count(*) FROM core.memberships WHERE tenant_id IN(SELECT tenant_id FROM w5_runtime_scopes))<>1997 THEN RAISE EXCEPTION 'EXACT_1997_MEMBERSHIPS_REQUIRED';END IF;
 IF (SELECT count(*) FROM core.roles WHERE tenant_id IN(SELECT tenant_id FROM w5_runtime_scopes))<>1003 THEN RAISE EXCEPTION 'EXACT_1003_ROLES_REQUIRED';END IF;
 IF (SELECT count(*) FROM core.role_assignments WHERE tenant_id IN(SELECT tenant_id FROM w5_runtime_scopes))<>2003 THEN RAISE EXCEPTION 'EXACT_2003_ASSIGNMENTS_REQUIRED';END IF;
 IF (SELECT count(*) FROM billing.tenant_subscriptions WHERE tenant_id IN(SELECT tenant_id FROM w5_runtime_scopes))<>500 THEN RAISE EXCEPTION 'EXACT_500_SUBSCRIPTIONS_REQUIRED';END IF;
 IF EXISTS(SELECT 1 FROM core.memberships WHERE user_id=(SELECT user_id FROM w5_runtime_accounts WHERE label='operator')) THEN RAISE EXCEPTION 'OPERATOR_MEMBERSHIP_FORBIDDEN';END IF;
 IF (SELECT count(*) FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid)<>1 THEN RAISE EXCEPTION 'EXACT_RUNTIME_WORKER_SCOPE_REQUIRED';END IF;
 IF (SELECT encode(extensions.digest(string_agg(role_id::text,E'\\n' ORDER BY role_id::text),'sha256'),'hex') FROM w5_runtime_roles)<>'848ef0e6b4beef663e5912c1b9e54585ff919fe007612a72dcf7f741cbd8c92f' THEN RAISE EXCEPTION 'EXACT_REVIEWED_ROLE_IDS_REQUIRED';END IF;
END $bounded_assertions$;
SELECT jsonb_build_object('passed',true,'strictStructuralAssertions',12,'tenants',500,'accounts',6,'entities',500,
 'branches',501,'memberships',1997,'roles',1003,'assignments',2003,'subscriptions',500,
 'constructedAuthRows',0,'constructedJwtClaims',0) AS bootstrap_verified;
`;

export function bindExactBootstrap(source,authIds,mode){
 must(hashBytes(source)===bootstrapSha&&['rollback','persist'].includes(mode),'EXACT_BOOTSTRAP_SOURCE_REQUIRED');
 must(authIds&&equal(Object.keys(authIds).sort(),[...labels].sort())&&Object.values(authIds).every(isUuid)
  &&new Set(Object.values(authIds)).size===6,'EXACT_RETURNED_SIX_AUTH_IDS_REQUIRED');
 must((source.match(/^begin;\s*$/gmi)??[]).length===1&&(source.match(/^commit;\s*$/gmi)??[]).length===1
  &&!/(?:insert\s+into|update|delete\s+from)\s+auth\./i.test(source),'SINGLE_BUSINESS_BOOTSTRAP_TRANSACTION_REQUIRED');
 const json=JSON.stringify(authIds);must(!json.includes("'"),'EXACT_AUTH_ID_LITERAL_REQUIRED');
 const bound=source.replace(/^begin;\s*$/mi,`begin;\nDO $auth_binding$ BEGIN PERFORM set_config('jentra.w5.created_auth_ids','${json}',true); END $auth_binding$;`);
 return bound.replace(/^commit;\s*$/mi,assertions+(mode==='rollback'?'rollback;':'commit;'));
}

export function validateBootstrapResponse(rows) {
 must(Array.isArray(rows)&&rows.length>=1&&rows.length<=2&&rows.every(row=>Object.keys(row).length===1
  &&(Object.hasOwn(row,'bootstrap_verified')||Object.hasOwn(row,'reviewed_counts'))),'EXACT_BOOTSTRAP_RESPONSE_REQUIRED');
 const proofs=rows.filter(row=>row.bootstrap_verified),counts=rows.filter(row=>row.reviewed_counts);
 must(proofs.length===1&&proofs[0].bootstrap_verified.passed===true&&proofs[0].bootstrap_verified.strictStructuralAssertions===12,
  'STRICT_REAL_AUTH_BOOTSTRAP_PROBE_REQUIRED');
 if(counts.length)must(equal(counts[0].reviewed_counts,{tenants:500,accounts:6,memberships:1997,roles:1003,assignments:2003}),
  'EXACT_REVIEWED_BOOTSTRAP_COUNTS_REQUIRED');return proofs[0].bootstrap_verified;
}

function preservationSql(review){
 must(review.syntheticScopes.length===500&&review.syntheticScopes.every(s=>isUuid(s.tenantId)),'EXACT_500_REVIEWED_SCOPES_REQUIRED');
 const ids=review.syntheticScopes.map(s=>`'${s.tenantId}'::uuid`).join(','),plans=planCodes.map(c=>`'${c}'`).join(',');
 return `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH scoped AS(SELECT unnest(ARRAY[${ids}]) AS tenant_id)
SELECT jsonb_build_object('observedAt',statement_timestamp(),'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'scopedCounts',jsonb_build_object('tenants',(SELECT count(*) FROM core.tenants WHERE id IN(SELECT tenant_id FROM scoped)),
 'entities',(SELECT count(*) FROM core.legal_entities WHERE tenant_id IN(SELECT tenant_id FROM scoped)),
 'branches',(SELECT count(*) FROM core.branches WHERE tenant_id IN(SELECT tenant_id FROM scoped)),
 'memberships',(SELECT count(*) FROM core.memberships WHERE tenant_id IN(SELECT tenant_id FROM scoped)),
 'roles',(SELECT count(*) FROM core.roles WHERE tenant_id IN(SELECT tenant_id FROM scoped)),
 'assignments',(SELECT count(*) FROM core.role_assignments WHERE tenant_id IN(SELECT tenant_id FROM scoped)),
 'subscriptions',(SELECT count(*) FROM billing.tenant_subscriptions WHERE tenant_id IN(SELECT tenant_id FROM scoped)),
 'plans',(SELECT count(*) FROM billing.plans WHERE code IN(${plans}))),
 'existingAccessFingerprints',jsonb_build_object(
 'core.memberships',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)::text FROM core.memberships t WHERE tenant_id NOT IN(SELECT tenant_id FROM scoped)),'[]'),'sha256'),'hex'),
 'core.role_assignments',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)::text FROM core.role_assignments t WHERE tenant_id NOT IN(SELECT tenant_id FROM scoped)),'[]'),'sha256'),'hex'),
 'core.role_permissions',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tenant_id,t.role_id,t.permission_code)::text FROM core.role_permissions t WHERE tenant_id NOT IN(SELECT tenant_id FROM scoped)),'[]'),'sha256'),'hex'),
 'billing.plan_entitlements',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.plan_code,t.entitlement_code)::text FROM billing.plan_entitlements t WHERE plan_code NOT IN(${plans})),'[]'),'sha256'),'hex')),
 'existingDesktopAccountPreserved',EXISTS(SELECT 1 FROM auth.users WHERE id='c0ab44a9-7385-4d9c-94f2-4df3efaa453f'::uuid AND email='desktop-test-20261009@jentra.invalid' AND email_confirmed_at IS NOT NULL)
) AS bootstrap_preservation;ROLLBACK;`;
}

export function validateBootstrapPreservation(before,after,persisted){
 must(before?.migrationCount===114&&after?.migrationCount===114&&before.existingDesktopAccountPreserved===true
  &&after.existingDesktopAccountPreserved===true&&Object.values(before.scopedCounts).every(n=>n===0)
  &&equal(before.existingAccessFingerprints,after.existingAccessFingerprints),'BOOTSTRAP_EXISTING_ACCESS_CHANGED');
 const expected=persisted?{tenants:500,entities:500,branches:501,memberships:1997,roles:1003,assignments:2003,subscriptions:500,plans:4}:before.scopedCounts;
 must(equal(after.scopedCounts,expected),'EXACT_BOOTSTRAP_AFTER_COUNTS_REQUIRED');return true;
}

function createExactBootstrapWriter(ownerToken,queries){
 return async kind=>{
  must(['rollback','persist'].includes(kind)&&typeof queries[kind]==='string','EXACT_BOOTSTRAP_WRITE_REQUIRED');
  const bytes=JSON.stringify({query:queries[kind],read_only:false});
  return new Promise((resolve,reject)=>{let request,timer,settled=false,sent=false,size=0;const chunks=[];
   const fail=(code,status)=>{if(settled)return;settled=true;clearTimeout(timer);request?.destroy();const error=Error(code);
    error.publicCode=code;error.sent=sent;error.httpStatus=status;reject(error);};
   try{request=https.request(new URL(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`),{
    method:'POST',rejectUnauthorized:true,headers:{Authorization:`Bearer ${ownerToken}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(bytes)}},response=>{
     response.on('error',()=>fail('BOOTSTRAP_RESPONSE_UNCERTAIN'));response.on('data',chunk=>{if(settled)return;size+=chunk.length;
      if(size>2*1024*1024)fail('BOOTSTRAP_RESPONSE_LIMIT');else chunks.push(chunk);});
     response.on('end',()=>{if(settled)return;const raw=Buffer.concat(chunks);
      if(![200,201].includes(response.statusCode)){fail('BOOTSTRAP_HTTP_NOT_SUCCESS',response.statusCode);return;}
      let value;try{value=JSON.parse(raw);}catch{fail('BOOTSTRAP_JSON_INVALID');return;}
      settled=true;clearTimeout(timer);resolve({value,status:response.statusCode,responseSha256:hashBytes(raw),actualFinishedAt:new Date().toISOString()});});});
    request.on('error',()=>fail('BOOTSTRAP_TRANSPORT_UNCERTAIN'));timer=setTimeout(()=>fail('BOOTSTRAP_TIMEOUT_UNCERTAIN'),180000);
    request.once('socket',socket=>{const send=()=>{if(settled){request.destroy();return;}
     if(socket.encrypted!==true||socket.authorized!==true){fail('VERIFIED_BOOTSTRAP_TLS_REQUIRED');return;}sent=true;request.end(bytes);};
     if(settled){request.destroy();return;}if(socket.encrypted!==true){fail('VERIFIED_BOOTSTRAP_TLS_REQUIRED');return;}
     if(socket.authorized===true)send();else socket.once('secureConnect',send);});
   }catch{fail('BOOTSTRAP_REQUEST_FAILED');}
  });
 };
}

async function save(file,value){const text=JSON.stringify(value,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(text);await handle.sync();}finally{await handle.close();}return {path:file,sha256:hashBytes(text)};}
async function prepare(){const inputs=await loadApprovedInputs();
 for(const [file,sha]of [[authFile,authSha],[mfaFile,mfaSha]])must(hashBytes(await fs.readFile(path.join(root,file)))===sha,'ACTUAL_AUTH_MFA_RECORD_REQUIRED');
 const auth=JSON.parse(await fs.readFile(path.join(root,authFile),'utf8')),mfa=JSON.parse(await fs.readFile(path.join(root,mfaFile),'utf8'));
 must(auth.passed&&mfa.passed&&auth.accountsCreated===6&&mfa.genuineMfaVerifiedActors===6,'SIX_GENUINE_AUTH_MFA_ACTORS_REQUIRED');
 const authIds=Object.fromEntries(auth.accounts.map(a=>[a.label,a.authId]));
 must(mfa.actors.every(a=>authIds[a.label]===a.actorId&&a.aal==='aal2'&&a.serverSessionRowVerified),'ACTUAL_MFA_ID_BINDING_REQUIRED');
 const binding=inputs.review.artifacts.find(a=>a.path===inputs.review.bootstrap.bootstrapSql);
 must(binding?.sha256===bootstrapSha,'EXACT_APPROVED_BOOTSTRAP_BINDING_REQUIRED');
 const source=await fs.readFile(path.join(root,binding.path),'utf8');
 return {inputs,authIds,binding,queries:{rollback:bindExactBootstrap(source,authIds,'rollback'),persist:bindExactBootstrap(source,authIds,'persist')},
  preservation:preservationSql(inputs.review)};
}

async function main(){const mode=process.argv[2]??'--validate';must(process.argv.length<=3&&['--validate','--execute'].includes(mode),'EXACT_BOOTSTRAP_MODE_REQUIRED');
 const prepared=await prepare();if(mode==='--validate'){process.stdout.write(JSON.stringify({kind:'exact-auth-bound-bootstrap-preparation',passed:true,
  syntheticScopes:500,genuineReturnedAuthIds:6,strictStructuralAssertions:12,networkCalls:0,databaseWrites:0,authWrites:0})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_INPUT_TOO_LONG');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_RUNTIME_INPUT_REQUIRED');
 const reader=createManagementTransport(config.ownerToken),writer=createExactBootstrapWriter(config.ownerToken,prepared.queries);
 const evidenceDirectory=base+'exact-bootstrap-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,evidenceDirectory));
 const publicSave=(file,value)=>save(evidenceDirectory+file,value);let phase='once-only-intent',networkCalls=0,writeRequests=0,before;
 try{
  await save(base+'exact-bootstrap-once-20261013-r5.json',{kind:'approved-bootstrap-once-only-intent',projectId:PROJECT,bundleSha256:BUNDLE,
   actualStartedAt:new Date().toISOString(),evidenceDirectory,source:prepared.binding,authIds:prepared.authIds,automaticReplayForbidden:true});
  phase='owner-project';networkCalls++;const project=(await reader('GET','')).value;
  must(project.id===PROJECT&&(project.organization_id??project.organization_slug)===ORGANIZATION&&project.status==='ACTIVE_HEALTHY','EXACT_OWNER_PROJECT_REQUIRED');
  const snapshot=async filename=>{networkCalls++;const response=await reader('POST','/database/query',{query:prepared.preservation,read_only:true});
   await publicSave(filename,{querySha256:hashBytes(prepared.preservation),response});must(response.value?.length===1,'ONE_BOOTSTRAP_SNAPSHOT_REQUIRED');return response.value[0].bootstrap_preservation;};
  phase='fresh-collision-and-preservation-baseline';before=await snapshot('01-before.json');
  must(before.migrationCount===114&&Object.values(before.scopedCounts).every(n=>n===0)&&before.existingDesktopAccountPreserved,'BOOTSTRAP_COLLISION');
  phase='actual-rollback-bootstrap';await publicSave('02-rollback-intent.json',{actualIntentAt:new Date().toISOString(),
   source:prepared.binding,boundSqlSha256:hashBytes(prepared.queries.rollback),authIds:prepared.authIds,outerTransaction:'ROLLBACK',constructedAuthRows:0,constructedJwtClaims:0});
  writeRequests++;networkCalls++;const rollback=await writer('rollback');await publicSave('03-rollback-result.json',rollback);
  validateBootstrapResponse(rollback.value);
  phase='rollback-reconciliation';const rolledBack=await snapshot('04-after-rollback.json');validateBootstrapPreservation(before,rolledBack,false);
  phase='exact-persistent-bootstrap';await publicSave('05-persist-intent.json',{actualIntentAt:new Date().toISOString(),source:prepared.binding,
   boundSqlSha256:hashBytes(prepared.queries.persist),authIds:prepared.authIds,rollbackProbePassed:true,outerTransaction:'COMMIT'});
  writeRequests++;networkCalls++;const applied=await writer('persist');await publicSave('06-persist-result.json',applied);
  validateBootstrapResponse(applied.value);
  phase='independent-read-after-commit';const after=await snapshot('07-after-commit.json');validateBootstrapPreservation(before,after,true);
  const result={kind:'actual-auth-bound-approved-synthetic-bootstrap',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,
   bundleSha256:BUNDLE,passed:true,bootstrapPersisted:true,strictStructuralAssertions:12,genuineReturnedAuthIds:prepared.authIds,
   actualScopedCounts:after.scopedCounts,existingAccessRowsUnchanged:true,existingDesktopAccountPreserved:true,
   rollbackProbeExecuted:true,rollbackProbedRowsDidNotPersist:true,committedBootstrapObservedThroughFreshRead:true,
   source:prepared.binding,authProvisioning:{path:authFile,sha256:authSha},genuineMfa:{path:mfaFile,sha256:mfaSha},networkCalls,
   writeRequests,persistentBootstrapCommits:1,authWrites:0,constructedAuthRows:0,constructedJwtClaims:0,
   schemaMigrationsReplayed:0,businessWorkflowBehaviorVerified:false,workerAuthorityScopeExpiresAfterHours:24,
   operatorTimeLimitedAuthorityIssued:false,workersDeployed:false,schedulesInstalled:false,actualDelivery:false,actualModelUsage:false,
   authenticatedNative:false,independentSessionContention:false,targetScaleLoad:false,ownerAcceptedCriteria:3,production:false,realBilling:false};
  const evidence=await publicSave('99-result.json',result);process.stdout.write(JSON.stringify({passed:true,bootstrapPersisted:true,
   syntheticTenants:500,memberships:1997,roles:1003,assignments:2003,existingAccessRowsUnchanged:true,evidence})+'\n');
 }catch(error){await publicSave('99-stop.json',{phase,failureCode:error.publicCode??'EXACT_BOOTSTRAP_FAILED',httpStatus:error.httpStatus??null,
  networkCalls,writeRequests,actualFailedAt:new Date().toISOString(),uncertainRequestMayHaveBeenSent:error.sent===true,automaticReplayPerformed:false});throw error;
 }finally{config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'EXACT_BOOTSTRAP_FAILED',rawErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;
});
