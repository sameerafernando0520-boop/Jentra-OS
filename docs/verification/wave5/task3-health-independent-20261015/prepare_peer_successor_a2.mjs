import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
const directory=fileURLToPath(new URL('./',import.meta.url));
const read=name=>readFileSync(resolve(directory,name),'utf8');
const bind=name=>{const data=readFileSync(resolve(directory,name));return {name,bytes:data.length,sha256:createHash('sha256').update(data).digest('hex')};};
const original=read('peer_cases_a1.mjs');
const needle="  p.once=async value=>{const receipt=await original(value);clock=instant+45001;return receipt;};\n  await assert.rejects(runHealthReadiness(p),/HEALTH_DISPATCH_RESOLUTION_MARGIN_REQUIRED/);";
const replacement="  p.once=async value=>{const receipt=await original(value);clock=instant+45001;return receipt;};\n  p.transport=async request=>{\n    p.calls.push(request);assert.equal(request.kind,'preflight');\n    assert.equal(request.signal.aborted,false);assert.ok(request.deadline>clock);assert.ok(request.deadline<=clock+15000);\n    return {status:200,rows:[{snapshot:state(clock)}]};\n  };\n  await assert.rejects(runHealthReadiness(p),/HEALTH_DISPATCH_RESOLUTION_MARGIN_REQUIRED/);";
if(original.split(needle).length!==2)throw Error('EXACT_SINGLE_PEER_FIXTURE_REPLACEMENT_REQUIRED');
writeFileSync(resolve(directory,'peer_cases_a2.mjs'),original.replace(needle,replacement),{flag:'wx'});
const runner=read('run_independent_health_a1.mjs')
  .replaceAll('peer_cases_a1.mjs','peer_cases_a2.mjs')
  .replaceAll('independent-a1.test.mjs','independent-a2.test.mjs')
  .replaceAll('independent-health-a1','independent-health-a2')
  .replaceAll('independent-local-verification-a1.json','independent-local-verification-a2.json');
writeFileSync(resolve(directory,'run_independent_health_a2.mjs'),runner,{flag:'wx'});
const report={kind:'independent-health-test-fixture-correction',createdAt:new Date().toISOString(),sourceEdited:false,
  failure:'Case 27 advanced the injected controller clock but reused the authored transport assertion against its original separate fixture clock.',
  correction:'Only that peer case now injects a preflight transport using the same virtual clock. The original startup deadline and reserve expectation are retained.',
  preserved:['peer_cases_a1.mjs','run_independent_health_a1.mjs','health_readiness.independent-a1.test.mjs','independent-health-a1.tap','independent-local-verification-a1.json'].map(bind),
  successors:['peer_cases_a2.mjs','run_independent_health_a2.mjs'].map(bind),actualNetworkRequests:0,actualSqlExecutions:0};
writeFileSync(resolve(directory,'peer-fixture-correction-a2.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({correction:bind('peer-fixture-correction-a2.json'),successors:report.successors}));
