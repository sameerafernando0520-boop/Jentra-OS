// Seal this local verification checkpoint. Never stages, commits or connects.
import assert from 'node:assert/strict';
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {join,relative} from 'node:path';
import YAML from '../../../build/launch-validation-runtime/node_modules/yaml/dist/index.js';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const folder=fileURLToPath(new URL('.',import.meta.url));
const read=path=>readFile(join(root,path));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const text=async path=>(await read(path)).toString('utf8');
const git=(...args)=>execFileSync('git',args,{cwd:root,encoding:'utf8',windowsHide:true}).trim();
assert.equal(git('rev-parse','HEAD'),'678584047d7f4a5fd0e50192b2d3ea576f33b1c7','Recheck ownership/base before recording a different checkout.');
assert.equal(git('diff','--name-only','HEAD','--','supabase/migrations'),'','Applied migration sources must remain unchanged.');
const logs={
 desktop:'build/company-access-desktop-full.log',focusedDesktop:'build/company-access-desktop-focused-final.log',
 domain:'build/company-access-domain-tests.log',platform:'build/company-access-platform-tests-final.log',
 analyzer:'build/company-access-analysis-final.log',format:'build/company-access-format-final.log',
 runner:'build/company-access-runner-final.log',
};
const results={desktop:2343,focusedDesktop:21,domain:10,platform:11};
for(const [name,count] of Object.entries(results)){
 const log=await text(logs[name]);
 assert.ok(log.includes(`+${count}: All tests passed!`),`${name} count/result must match its actual log.`);
}
assert.ok((await text(logs.analyzer)).includes('No issues found!'));
assert.ok((await text(logs.format)).includes('Formatted 880 files (0 changed)'));
assert.ok((await text(logs.runner)).includes('pass 5'));
assert.ok((await text(logs.runner)).includes('fail 0'));
const workflow=YAML.parseDocument(await text('.github/workflows/ci.yml'),{uniqueKeys:true});
assert.deepEqual(workflow.errors,[],'Workflow YAML must parse without duplicate keys.');
assert.ok((await text('.github/workflows/ci.yml')).includes('node supabase/candidates/run-company-access-test.mjs --run-local'));
const behavioral=JSON.parse(await text('docs/verification/company-access-20261028/postgres-result.json'));
const pgtap=JSON.parse(await text('docs/verification/company-access-20261028/pgtap-result.json'));
assert.equal(behavioral.passed,73);assert.equal(pgtap.passed,31);assert.equal(pgtap.failed,0);
for(const report of [behavioral,pgtap])for(const [path,expected] of Object.entries(report.sources)){
 assert.equal(hash(await read(path)),expected,`Database evidence is stale for ${path}`);
}
assert.ok(Object.values(pgtap.rollback).every(value=>value===true));
const prior=JSON.parse(await text('build/company-access-failures-before.json'));
for(const entry of prior.files)assert.equal(hash(await readFile(entry.path)),entry.hash.toLowerCase(),`Preserved diagnostic changed: ${entry.path}`);
assert.equal(prior.files.length,460);
assert.equal(hash(await read('supabase/candidates/20261023090000_employee_push.sql')),
 'd0a92d80c7baa2e0012230716a2237feff31a4d0fc90e5da80f5d18c8f9a1d31');
const originalWord='docs/user-guide/Jentra OS Company Setup and Operating Guide.docx';
assert.equal(git('hash-object',originalWord),git('rev-parse','HEAD:'+originalWord));

// Refresh the existing source inclusion inventory without changing its 43
// advertised destinations or treating candidate screens as installed software.
const inventoryPath='docs/user-guide/feature-inventory.json';
const inventory=JSON.parse(await text(inventoryPath));
assert.equal(inventory.advertised_destinations,43);assert.equal(inventory.matching_routes,43);
inventory.known_incomplete=inventory.known_incomplete.filter(value=>!['general extra legal entity and branch administration UI',
 'general staff invitation and role administration UI'].includes(value));
const adminGap='company and staff administration candidate rollout and native company acceptance';
if(!inventory.known_incomplete.includes(adminGap))inventory.known_incomplete.unshift(adminGap);
inventory.administration_candidate={implemented:true,installed:false,
 routes:['/setup/company-access','/workspace/invitations'],
 verification:'../verification/company-access-20261028/README.md'};
for(const path of Object.keys(inventory.sources))inventory.sources[path]=hash(await read(path));
await writeFile(join(root,inventoryPath),JSON.stringify(inventory,null,2)+'\n');

const inputs=[
 '.github/workflows/ci.yml','apps/jentra_desktop/lib/main.dart',
 'apps/jentra_desktop/lib/src/app_providers.dart','apps/jentra_desktop/lib/src/router.dart',
 'apps/jentra_desktop/lib/src/shell/navigation.dart','apps/jentra_desktop/lib/src/shell/workspace_context_dialog.dart',
 'apps/jentra_desktop/lib/src/features/auth/mfa_required_screen.dart',
 'apps/jentra_desktop/lib/src/features/dashboard/dashboard_screen.dart',
 'apps/jentra_desktop/lib/src/features/setup/business_setup_screen.dart',
 ...['workspace_admin_controller.dart','workspace_admin_screen.dart','workspace_invitations_screen.dart']
  .map(name=>'apps/jentra_desktop/lib/src/features/tenant/'+name),
 ...['workspace_admin_test.dart','workspace_invitations_test.dart'].map(name=>'apps/jentra_desktop/test/'+name),
 'packages/jentra_domain/lib/jentra_workspace_admin.dart','packages/jentra_domain/lib/src/workspace_admin.dart',
 'packages/jentra_domain/test/workspace_admin_test.dart',
 'packages/jentra_platform/lib/jentra_workspace_admin_platform.dart',
 ...['workspace_admin_gateway.dart','workspace_admin_recovery.dart'].map(name=>'packages/jentra_platform/lib/src/'+name),
 ...['workspace_admin_gateway_test.dart','workspace_admin_recovery_test.dart'].map(name=>'packages/jentra_platform/test/'+name),
 'supabase/candidates/20261028130000_company_access_administration.sql','supabase/candidates/run-company-access-test.mjs',
 'supabase/candidates/tests/company_access_administration_test.sql','supabase/candidates/tests/company_access_runner.test.mjs',
 'docs/blueprint/69_COMPANY_AND_ACCESS_ADMINISTRATION_CONTRACT.md',
 'docs/blueprint/mobile-apps/SALESMAN_APP_BLUEPRINT.md','docs/blueprint/mobile-apps/SALES_OWNER_DECISIONS_20261028.md',
 'docs/development/company-access-administration-candidate.md','docs/development/launch-readiness-20261028.md',
 'docs/user-guide/README.md','docs/user-guide/company-access-administration.md',
 'docs/user-guide/feature-completeness.md',inventoryPath,
 'docs/user-guide/Jentra OS Company Access Administration Addendum.docx',originalWord,
];
for(const name of await readdir(folder))if(name!=='verification-manifest.json')inputs.push(relative(root,join(folder,name)).replaceAll('\\','/'));
const sourceHashes={};for(const path of inputs)sourceHashes[path]=hash(await read(path));
const logHashes={};for(const path of Object.values(logs))logHashes[path]=hash(await read(path));
const manifest={atUtc:new Date().toISOString(),baseCommit:git('rev-parse','HEAD'),branch:git('branch','--show-current'),
 status:'Uncommitted administration candidate; not the narrow published PR 16 repair',
 results:{...results,runner:5,postgresBehavioral:73,pgtap:31,analyzer:'No issues',formatFiles:880,formatChanges:0},
 limits:{hostedAccess:false,supabaseStackExecuted:false,migrationInstalled:false,senderDeployed:false,
  companyDataDeleted:false,productionCertified:false,independentContentionVerified:false},
 preserved:{diagnosticArtifacts:460,originalWord:true,originalEmployeePushCandidate:true,appliedMigrationSources:true},
 documentReview:{pages:2,renderer:'Native Microsoft Word; PDFium page images visually inspected'},
 sourceHashes,logHashes};
await writeFile(new URL('verification-manifest.json',import.meta.url),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({results:manifest.results,preserved:manifest.preserved,hashedSources:inputs.length}));
