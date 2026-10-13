import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { PROJECT, ORGANIZATION, BUNDLE, loadApprovedInputs, createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes, isUuid } from './runtime_contract.mjs';
import { runtimeSealKey, appendRuntimeSecret } from './private_runtime_seal.mjs';
import { APPROVED_ACTOR_EMAILS, createPrivateKeyReader, selectExistingLegacyKeys, createApprovedAuthAdmin } from './private_runtime_http.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url)), base = 'docs/verification/wave5/';
const verifiedPath = base + 'installed-management-verification-20261013-r5-1791877136909/99-result.json';
const verifiedSha = '8c414bbe88c18336ac6f9a1d44d4d3cca9366249487da466c0ba4316acdd733e';
const localSources = {
  'tools/wave5/private_runtime_http.mjs': 'd52ae919e4c13bd1745ef806658744dfc2c52df7b61d24d9f87afac06de7be2c',
  'tools/wave5/private_runtime_seal.mjs': '1395a91ee666d40c5504c8977b5d4f64aa4d54b383dfe147fe78eb07a5d7a206'
};
const trialId = 'c0ab44a9-7385-4d9c-94f2-4df3efaa453f', trialEmail = 'desktop-test-20261009@jentra.invalid';
const must = (ok, code) => { if (!ok) { const error = Error(code); error.publicCode = code; throw error; } };
const collisionSql = `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT statement_timestamp() AS observed_at,
 (SELECT count(*) FROM supabase_migrations.schema_migrations) AS migration_count,
 (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api' AND p.prokind='f') AS api_functions,
 (SELECT count(*) FROM auth.users WHERE email IN ('w5-proposer@jentra.invalid','w5-approver@jentra.invalid','w5-executor@jentra.invalid','w5-billing-admin@jentra.invalid','w5-operator@jentra.invalid','w5-foreign-member@jentra.invalid')) AS proposed_accounts,
 (SELECT count(*) FROM core.tenants WHERE slug LIKE 'jentra-w5-%-20261008') AS proposed_tenants,
 (SELECT count(*) FROM billing.plans WHERE code IN ('w5_runtime_20261008','w5_foreign_20261008','w5_quota10_20261008','w5_load_20261008')) AS proposed_plans,
 (SELECT count(*) FROM auth.users WHERE id='${trialId}'::uuid AND email='${trialEmail}' AND email_confirmed_at IS NOT NULL) AS desktop_account_preserved;
ROLLBACK;`;

export function validateReturnedCreatedUser(value, label, createdIds) {
  const user = value?.user ?? value;
  must(isUuid(user?.id) && user.email?.toLowerCase() === APPROVED_ACTOR_EMAILS[label] && user.email_confirmed_at
    && !createdIds.includes(user.id) && !user.deleted_at, 'GENUINE_EXACT_ADMIN_CREATED_USER_REQUIRED');
  return { label, authId: user.id, email: APPROVED_ACTOR_EMAILS[label], createdAt: user.created_at,
    emailConfirmedAt: user.email_confirmed_at };
}
async function save(file, value) {
  const bytes = JSON.stringify(value, null, 2) + '\n', handle = await fs.open(path.join(root, file), 'wx');
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
  return { path: file, sha256: hashBytes(bytes) };
}
async function prepare() {
  const inputs = await loadApprovedInputs();
  for (const [file, sha] of Object.entries({ ...localSources, [verifiedPath]: verifiedSha }))
    must(hashBytes(await fs.readFile(path.join(root,file))) === sha, 'EXACT_AUTH_PREPARATION_SOURCE_REQUIRED');
  const verified = JSON.parse(await fs.readFile(path.join(root,verifiedPath),'utf8'));
  must(verified.passed === true && verified.ledgerCount === 114 && verified.catalog.apiFunctions === 363
    && verified.preservation.existingAccessRowsUnchanged === true && verified.preservation.existingDesktopAccountPreserved === true,
  'INSTALLED_VERIFICATION_REQUIRED');
  must(inputs.review.accounts.length === 6 && inputs.review.accounts.every(row => row.email === APPROVED_ACTOR_EMAILS[row.label])
    && inputs.review.bootstrap.authAdminOnly === true && inputs.review.bootstrap.emailConfirm === true
    && inputs.review.bootstrap.emailDelivery === false, 'EXACT_SIX_APPROVED_AUTH_ACCOUNTS_REQUIRED');
  return inputs;
}

async function main() {
  const mode = process.argv[2] ?? '--validate';
  must(process.argv.length <= 3 && ['--validate','--provision'].includes(mode), 'EXACT_AUTH_PROVISIONING_MODE_REQUIRED');
  const inputs = await prepare();
  if (mode === '--validate') {
    process.stdout.write(JSON.stringify({ kind: 'approved-auth-provisioning-preparation', passed: true,
      approvedAccounts: 6, installedMetadataVerified: true, networkCalls: 0, authWrites: 0,
      privateStore: 'AES-256-GCM with a Windows CurrentUser DPAPI-sealed key and current-SID-only directory' }) + '\n'); return;
  }
  let incoming = ''; for await (const chunk of process.stdin) { incoming += chunk; must(incoming.length <= 16000,'PRIVATE_INPUT_TOO_LONG'); }
  const config = JSON.parse(incoming); incoming = '';
  must(config.projectId === PROJECT && config.bundleSha256 === BUNDLE && config.privateDirectory && config.ownerToken,
    'EXACT_PRIVATE_RUNTIME_INPUT_REQUIRED');
  const key = runtimeSealKey(config.encryptionKey);
  const management = createManagementTransport(config.ownerToken), readKeys = createPrivateKeyReader(config.ownerToken);
  const evidenceDirectory = base + 'auth-admin-provisioning-20261013-r5-' + Date.now() + '/';
  await fs.mkdir(path.join(root,evidenceDirectory));
  const publicSave = (file,value) => save(evidenceDirectory+file,value);
  let phase = 'public-intent', authWrites = 0, networkCalls = 0; const accounts = [];
  try {
    await save(base+'auth-admin-provisioning-once-20261013-r5.json',{ kind:'approved-auth-once-only-intent', actualStartedAt:new Date().toISOString(),
      projectId:PROJECT,bundleSha256:BUNDLE,evidenceDirectory,approvedAccounts:inputs.review.accounts.map(a=>({label:a.label,email:a.email})),
      automaticRetryForbidden:true,existingAccountMutationForbidden:true });
    phase = 'owner-project'; networkCalls++;
    const project = (await management('GET','')).value;
    must(project.id===PROJECT && (project.organization_id??project.organization_slug)===ORGANIZATION && project.status==='ACTIVE_HEALTHY',
      'EXACT_OWNER_PROJECT_REQUIRED');
    phase = 'fresh-collision-preflight'; networkCalls++;
    const preflight = await management('POST','/database/query',{query:collisionSql,read_only:true});
    await publicSave('01-collision-preflight.json',{sqlSha256:hashBytes(collisionSql),response:preflight});
    const row = preflight.value?.[0], observed = Date.parse(row?.observed_at);
    must(row?.migration_count===114 && row.api_functions===363 && row.proposed_accounts===0 && row.proposed_tenants===0
      && row.proposed_plans===0 && row.desktop_account_preserved===1 && Number.isFinite(observed)
      && Date.now()-observed<600000 && Date.now()-observed>=-10000,'FRESH_EXACT_AUTH_COLLISION_PREFLIGHT_REQUIRED');
    phase = 'private-existing-key-read'; networkCalls++;
    const keys = selectExistingLegacyKeys((await readKeys()).value);
    const admin = createApprovedAuthAdmin(keys.serviceRole);
    phase = 'existing-trial-account'; networkCalls++;
    const trialBefore = (await admin.get(trialId)).value;
    must(trialBefore.id===trialId && trialBefore.email===trialEmail && trialBefore.email_confirmed_at,'EXISTING_TRIAL_ACCOUNT_REQUIRED');
    for (const reviewed of inputs.review.accounts) {
      phase = 'private-password-intent';
      const password = crypto.randomBytes(32).toString('base64url');
      const privateIntent = await appendRuntimeSecret(config.privateDirectory,key,'account-intent',
        {label:reviewed.label,email:reviewed.email,password,status:'prepared-before-create',createdAt:new Date().toISOString()});
      await publicSave(`${reviewed.label}-intent.json`,{label:reviewed.label,email:reviewed.email,privateIntent,
        actualIntentAt:new Date().toISOString(),genuineAdminCreateRequired:true,emailConfirm:true,emailDelivery:false});
      phase = 'genuine-auth-admin-create'; authWrites++; networkCalls++;
      const created = await admin.create(reviewed.label,password);
      const publicUser = validateReturnedCreatedUser(created.value,reviewed.label,accounts.map(a=>a.authId));
      phase = 'private-created-account-persistence';
      const privateRecord = await appendRuntimeSecret(config.privateDirectory,key,'account-created',
        {...publicUser,password,status:'returned-by-auth-admin',adminCreateResponseSha256:created.responseSha256});
      const record = {...publicUser,privateRecord,createResponseSha256:created.responseSha256,actualCreateFinishedAt:created.actualFinishedAt};
      accounts.push(record); await publicSave(`${reviewed.label}-created.json`,record);
      process.stdout.write(JSON.stringify({genuineAuthAdminCreated:true,label:record.label,authId:record.authId,passwordPrinted:false})+'\n');
    }
    phase = 'verify-created-users';
    for (const account of accounts) { networkCalls++;
      const returned=await admin.get(account.authId); validateReturnedCreatedUser(returned.value,account.label,[]);
      await publicSave(`${account.label}-verified.json`,{label:account.label,authId:account.authId,
        independentlyRereadThroughAuthAdmin:true,responseSha256:returned.responseSha256,actualFinishedAt:returned.actualFinishedAt});
    }
    phase = 'existing-trial-account-after'; networkCalls++;
    const trialAfter=(await admin.get(trialId)).value;
    must(trialAfter.id===trialId && trialAfter.email===trialEmail && trialAfter.email_confirmed_at===trialBefore.email_confirmed_at,
      'EXISTING_TRIAL_ACCOUNT_CHANGED');
    phase = 'durable-private-account-index';
    const privateIndex=await appendRuntimeSecret(config.privateDirectory,key,'accounts-index',{projectId:PROJECT,bundleSha256:BUNDLE,
      createdAt:new Date().toISOString(),accounts:accounts.map(a=>({label:a.label,authId:a.authId,privateRecord:a.privateRecord}))});
    const result={kind:'actual-approved-auth-admin-provisioning',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,
      bundleSha256:BUNDLE,passed:true,accountsCreated:accounts.length,accounts,privateIndex,networkCalls,authWrites,
      genuineAdminCreates:true,constructedAuthRows:0,passwordsOrKeysOrTokensPrinted:false,existingTrialAccountPreserved:true,
      existingAccountDeletes:0,existingAccountUpdates:0,emailDelivery:false,databaseWrites:0,bootstrapPersisted:false,
      genuineMfa:false,authenticatedNative:false,actualDelivery:false,independentSessionContention:false,targetScaleLoad:false,
      ownerAcceptedCriteria:3,production:false,realBilling:false,installedVerification:{path:verifiedPath,sha256:verifiedSha}};
    const evidence=await publicSave('99-result.json',result);
    process.stdout.write(JSON.stringify({passed:true,accountsCreated:accounts.length,existingTrialAccountPreserved:true,
      credentialsStoredPrivately:true,evidence})+'\n');
  } catch(error) {
    await publicSave('99-stop.json',{phase,failureCode:error.publicCode??'AUTH_PROVISIONING_FAILED',actualFailedAt:new Date().toISOString(),
      networkCalls,authWrites,completedAccounts:accounts,uncertainRequestMayHaveBeenSent:error.sent===true,
      automaticRetryPerformed:false,existingAccountDeletes:0,existingAccountUpdates:0,passwordOrKeyPrinted:false});
    throw error;
  } finally { key.fill(0); config.ownerToken='';config.encryptionKey=''; }
}
if (process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) main().catch(error=>{
  process.stderr.write(JSON.stringify({failureCode:error.publicCode??'AUTH_PROVISIONING_FAILED',rawErrorOrCredentialPrinted:false})+'\n');
  process.exitCode=1;
});
