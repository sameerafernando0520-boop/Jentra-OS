// Read-only source/render diagnosis; writes only a new revision-bound report.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const revision=process.argv[2];
if(!/^r\d+$/.test(revision??''))throw Error('REVISION_REQUIRED');
const base='docs/verification/wave5/',stem=base+`full-desktop-golden-investigation-20261009-${revision}`;
const sha=b=>createHash('sha256').update(b).digest('hex');
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
const stage=await json(base+`windows-test-preview-desktopAll-20261009-${revision}.json`);
const bytes=await readFile(stage.log),log=bytes.toString('utf8');
const totals=[...log.matchAll(/\+(\d+)(?:\s+-(\d+))?: (?:All tests passed!|Some tests failed\.)/g)].at(-1);
if(!totals)throw Error('FINAL_FULL_SUITE_RESULT_REQUIRED');
const priorPath='docs/verification/remaining-wave3/golden-control-20261002.json';
const priorBytes=await readFile(priorPath),prior=JSON.parse(priorBytes),controls=[];
function visit(v){if(!v||typeof v!=='object')return;if(v.image&&v.control_sha256)controls.push(v);for(const child of Object.values(v))if(typeof child==='object')visit(child);}
visit(prior);
const blocks=log.split(/(?<=\n)(?=\d+:\d+ \+\d+(?: -\d+)?: )/),failures=[];
for(let i=0;i<blocks.length;i++){
 const header=blocks[i].split('\n')[0].trim();if(!header.endsWith('[E]'))continue;
 const body=blocks[i-1]??'',golden=body.match(/Golden ["'](goldens\/[^"']+)["']/i);
 const failure={name:header.replace(/^\d+:\d+ \+\d+(?: -\d+)?: /,'').replace(/ \[E\]$/,''),category:golden?'golden':body.includes("Creation failed, path = ''")?'capture-harness-empty-path':'unclassified',golden:golden?.[1]??null};
 if(golden){
  const approved='apps/jentra_desktop/test/'+golden[1],image=golden[1].split('/').at(-1).replace(/\.png$/,'');
  const prefix=`build/w5win9${revision}/preview/apps/jentra_desktop/test/failures/${image}`;
  failure.approved={path:approved,sha256:sha(await readFile(approved))};
  failure.renders=await Promise.all(['masterImage','testImage','isolatedDiff'].map(async kind=>{const path=prefix+'_'+kind+'.png';return{kind,path,sha256:sha(await readFile(path))};}));
  failure.approvedMatchesFailureMaster=failure.approved.sha256===failure.renders.find(r=>r.kind==='masterImage').sha256;
  const current=failure.renders.find(r=>r.kind==='testImage');
  failure.earlierControl=controls.filter(c=>c.image===image+'_testImage.png').map(c=>({source:priorPath,controlSha256:c.control_sha256,priorCurrentSha256:c.current_sha256,identicalToControl:current.sha256===c.control_sha256,identicalToPriorCurrent:current.sha256===c.current_sha256}));
  failure.pixelDifference=body.match(/Pixel test\s+failed, ([\d.]+)%, (\d+)px/)?.slice(1)??null;
 }
 failures.push(failure);
}
if(failures.length!==Number(totals[2]??0))throw Error('FAILURE_COUNT_MISMATCH');
const categories={};for(const f of failures)categories[f.category]=(categories[f.category]??0)+1;
const identical=failures.filter(f=>f.earlierControl?.some(c=>c.identicalToControl)).length;
const report={observedAt:new Date().toISOString(),revision,stage,logSha256:sha(bytes),passed:Number(totals[1]),failed:Number(totals[2]??0),categories,
 earlierControl:{path:priorPath,sha256:sha(priorBytes),identicalCurrentGoldenImages:identical},failures,approvedGoldensRegenerated:false,
 inspectedByRoot:['catalogue_1024_light_compact_isolatedDiff.png','crm_1440_light_comfortable_testImage.png','crm_1440_light_comfortable_masterImage.png','dashboard_1024_light_compact_isolatedDiff.png'],
 causeLimits:'Identical earlier control bytes establish prior existence of those render differences. The separate SDK primitive experiment establishes rounded-border raster changes only; it does not certify the cause or accept every full-screen failure.',
 correctedHarness:'The earlier full run passed empty capture-directory environment variables on Windows. The wrapper now omits only empty task-specific destinations; full-suite rerun is on the same frozen Dart source. Original failed-run logs remain preserved.',
 ownerAcceptance:false};
await writeFile(stem+'.json',JSON.stringify(report,null,2)+'\n');
await writeFile(stem+'.md',`# Full desktop rendered investigation — ${revision}\n\nThe fresh full desktop suite reports **${report.passed} passed / ${report.failed} failed** (exit ${stage.exitCode}). [Machine evidence](${stem.split('/').at(-1)}.json) binds every failure, approved/current/master/diff hashes and the exact full-suite log. Categories: ${Object.entries(categories).map(([k,v])=>k+'='+v).join(', ')}. Approved goldens were preserved.\n\n${identical} current golden images exactly match an earlier independently preserved HEAD control image in [the October 2 control](../remaining-wave3/golden-control-20261002.json). This proves that those exact render differences existed earlier. The [October 3 primitive probe](../remaining-wave3/golden-cause-20261003.md) establishes Flutter SDK rounded-border raster differences on identical source; it does not establish that every full-screen mismatch has that cause. Catalogue diff inspection shows rounded-edge pixels. CRM current/master inspection shows omitted People/Projects/Service/Analytics destinations in the current limited-capability fixture. The 13 dashboard/setup cases retain the [earlier focused investigation](shared-golden-investigation-20261008.md). Fixture/navigation reconciliation and any changed approved image still require review.\n\nThe earlier run's 26 empty capture-destination failures came from the Windows test runner environment. The capture wrapper omits empty task variables before launching Flutter. Dart source, assertions and approved PNGs were unchanged; earlier failed logs remain preserved at windows-test-preview-desktopAll-capture-env-failure-20261009-${revision}.log. This runner correction is separate from the remaining visual failures.\n\n${failures.map(f=>'- '+f.name.replace(/^.*\/test\//,'')+' — '+f.category).join('\n')}\n\nNo passing focused suite, current/master hash match or prior SDK diagnosis closes native acceptance or owner signoff. Unclassified failures remain open.\n`);
process.stdout.write(JSON.stringify({passed:report.passed,failed:report.failed,categories,identicalEarlierControlImages:identical})+'\n');
