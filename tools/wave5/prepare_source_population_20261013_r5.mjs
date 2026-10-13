import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs } from './approved_management_installer.mjs';
import { hashBytes,isUuid } from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(value,code)=>{if(!value)throw Error(code);};
export function sourcePopulationSql(scopes,authIds,commit=false){
 must(scopes.length===500&&new Set(scopes.map(s=>s.tenantId)).size===500&&scopes.every(s=>[s.tenantId,s.entityId,s.branchId].every(isUuid)),'EXACT_REVIEWED_500_SOURCE_SCOPES_REQUIRED');
 must(isUuid(authIds.proposer)&&isUuid(authIds['foreign-member'])&&authIds.proposer!==authIds['foreign-member'],'REAL_CREATED_SOURCE_ACTORS_REQUIRED');
 const tuples=scopes.map(s=>`('${s.tenantId}'::uuid,'${s.entityId}'::uuid,'${s.branchId}'::uuid,'${s.key==='foreign'?authIds['foreign-member']:authIds.proposer}'::uuid)`).join(',\n');
 const body=`BEGIN;
CREATE TEMP TABLE w5_source_scopes(tenant_id uuid PRIMARY KEY,entity_id uuid NOT NULL,branch_id uuid NOT NULL,actor_id uuid NOT NULL) ON COMMIT DROP;
INSERT INTO w5_source_scopes VALUES ${tuples};
DO $guards$ BEGIN
 IF (SELECT count(*) FROM w5_source_scopes)<>500 OR
   (SELECT count(*) FROM w5_source_scopes s JOIN core.tenants t ON t.id=s.tenant_id
    JOIN core.legal_entities e ON e.tenant_id=s.tenant_id AND e.id=s.entity_id
    JOIN core.branches b ON b.tenant_id=s.tenant_id AND b.legal_entity_id=s.entity_id AND b.id=s.branch_id AND b.status='active'
    JOIN auth.users a ON a.id=s.actor_id AND a.email_confirmed_at IS NOT NULL)<>500 THEN
   RAISE EXCEPTION 'EXACT_EXISTING_BOOTSTRAP_AND_REAL_ACTORS_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM crm.opportunities WHERE tenant_id IN(SELECT tenant_id FROM w5_source_scopes)) OR
    EXISTS(SELECT 1 FROM workflow.process_events WHERE tenant_id IN(SELECT tenant_id FROM w5_source_scopes)) THEN
   RAISE EXCEPTION 'SOURCE_POPULATION_COLLISION_REQUIRES_RECONCILIATION'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core.currencies WHERE code='USD') OR NOT EXISTS(SELECT 1 FROM core.currencies WHERE code='LKR') THEN
   RAISE EXCEPTION 'EXISTING_REVIEWED_CURRENCIES_REQUIRED'; END IF;
END $guards$;
INSERT INTO crm.opportunities(tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,stage,probability,
 expected_value,currency_code,expected_close_date,request_id,command_id,correlation_id,source_context,
 client_timestamp,created_by,updated_by)
SELECT s.tenant_id,s.entity_id,s.branch_id,'W5-SRC-'||n.i,'Synthetic Wave 5 prospect '||n.i,s.actor_id,'submitted',
 CASE n.i WHEN 1 THEN 33.33::numeric ELSE 50.00::numeric END,
 CASE n.i WHEN 1 THEN 1000.000001::numeric ELSE 2000.125000::numeric END,
 CASE n.i WHEN 1 THEN 'USD' ELSE 'LKR' END,
 (statement_timestamp() AT TIME ZONE 'UTC')::date+CASE n.i WHEN 1 THEN 2 ELSE 7 END,
 gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
 jsonb_build_object('fixture','w5-source-population-20261013-r5','administrativeSyntheticSeed',true),
 statement_timestamp(),s.actor_id,s.actor_id FROM w5_source_scopes s CROSS JOIN generate_series(1,2) n(i);
INSERT INTO workflow.process_events(tenant_id,legal_entity_id,branch_id,document_type,document_id,from_status,to_status,
 actor_id,owner_id,entered_at,completed_at,active_minutes,wait_minutes,request_id,command_id,correlation_id)
SELECT s.tenant_id,s.entity_id,s.branch_id,'crm_opportunity',o.id,CASE n.i WHEN 1 THEN 'draft' ELSE 'submitted' END,
 CASE n.i WHEN 1 THEN 'submitted' ELSE 'approved' END,s.actor_id,s.actor_id,
 statement_timestamp()-interval '2 days'+n.i*interval '1 hour',
 CASE n.i WHEN 1 THEN statement_timestamp()-interval '2 days'+n.i*interval '1 hour'+interval '45 minutes' ELSE NULL END,
 CASE n.i WHEN 1 THEN 30.125000::numeric ELSE 10.500000::numeric END,
 CASE n.i WHEN 1 THEN 14.875000::numeric ELSE 2.250000::numeric END,
 gen_random_uuid(),gen_random_uuid(),gen_random_uuid()
FROM w5_source_scopes s JOIN crm.opportunities o ON o.tenant_id=s.tenant_id AND o.legal_entity_id=s.entity_id AND o.branch_id=s.branch_id
CROSS JOIN generate_series(1,2) n(i);
DO $counts$ BEGIN
 IF (SELECT count(*) FROM crm.opportunities WHERE tenant_id IN(SELECT tenant_id FROM w5_source_scopes))<>1000 OR
   (SELECT count(*) FROM workflow.process_events WHERE tenant_id IN(SELECT tenant_id FROM w5_source_scopes))<>2000 OR
   EXISTS(SELECT s.tenant_id FROM w5_source_scopes s LEFT JOIN crm.opportunities o ON o.tenant_id=s.tenant_id GROUP BY s.tenant_id HAVING count(o.id)<>2) OR
   EXISTS(SELECT s.tenant_id FROM w5_source_scopes s LEFT JOIN workflow.process_events e ON e.tenant_id=s.tenant_id GROUP BY s.tenant_id HAVING count(e.id)<>4) THEN
   RAISE EXCEPTION 'EXACT_NONEMPTY_SOURCE_COUNTS_REQUIRED'; END IF;
END $counts$;
SELECT jsonb_build_object('passed',true,'scopes',500,'opportunities',1000,'processEvents',2000,
 'opportunitiesPerScope',2,'eventsPerScope',4,'authRowsWritten',0,'constructedJwtClaims',0,
 'administrativeFixtureOnly',true,'actualObservedAt',statement_timestamp()) AS source_population;
${commit?'COMMIT':'ROLLBACK'};`;
 must(!/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+auth\./i.test(body)&&!body.includes('request.jwt.claims'),'NO_AUTH_FABRICATION_REQUIRED');return body;
}
async function save(name,value){const bytes=typeof value==='string'?value:JSON.stringify(value,null,2)+'\n';
 const file=base+name,handle=await fs.open(path.join(root,file),'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:file,sha256:hashBytes(bytes)};}
async function main(){const {review}=await loadApprovedInputs();const authFile=base+'auth-admin-provisioning-20261013-r5-1791877892653/99-result.json';
 const authBytes=await fs.readFile(path.join(root,authFile));must(hashBytes(authBytes)==='f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb','EXACT_ACTUAL_CREATED_ACCOUNTS_REQUIRED');
 const auth=JSON.parse(authBytes);must(auth.passed&&auth.accountsCreated===6,'ACTUAL_CREATED_ACCOUNTS_REQUIRED');
 const authIds=Object.fromEntries(auth.accounts.map(a=>[a.label,a.authId]));
 const rollback=await save('source-population-rollback-20261013-r5.sql',sourcePopulationSql(review.syntheticScopes,authIds,false));
 const persist=await save('source-population-persist-20261013-r5.sql',sourcePopulationSql(review.syntheticScopes,authIds,true));
 const result={kind:'approved-bounded-source-population-intent',actualPreparedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,
  scopeCount:500,perScope:{opportunities:2,processEvents:4},caps:{opportunities:200,processEvents:800},existingCurrencies:['LKR','USD'],
  rollback,persist,authProvisioning:{path:authFile,sha256:hashBytes(authBytes)},administrativeFixtureOnly:true,
  authWrites:0,constructedJwtClaims:0,networkCalls:0,businessWorkflowPassed:false,ownerAcceptedCriteria:3,production:false,realBilling:false};
 const evidence=await save('source-population-intent-20261013-r5.json',result);process.stdout.write(JSON.stringify({prepared:true,networkCalls:0,evidence})+'\n');}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(()=>{process.stderr.write('SOURCE_POPULATION_PREPARATION_FAILED\n');process.exitCode=1;});
