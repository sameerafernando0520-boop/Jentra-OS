// Produces the human-readable derivative after technical policy publication.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/root-runtime-review-20261017/';
const hash=x=>createHash('sha256').update(x).digest('hex');
const beforePath='dist/Jentra OS Runtime Continuation Review 20261017 r5.html';
const before=await fs.readFile(path.join(root,beforePath));assert.equal(hash(before),'9511df554215ed24b30a1d1613098eb29cbf9569dd292ffe12b9e895cee32161');
const policyPath='docs/verification/wave5/task3-export-renewal-20261016/source-policy-a1.json';
const reviewPath='docs/verification/wave5/task3-export-renewal-20261016/independent-policy-review-a1.json';
assert.equal(hash(await fs.readFile(path.join(root,policyPath))),'fddf8cab9460aa590889468fc0bcd693a857697a6da8ffe6e24e3b14b6665813');
assert.equal(hash(await fs.readFile(path.join(root,reviewPath))),'799aae6417ff8e223273bf14e8407e4b9f321df550d4c01a306b1e96bd855b50');
let text=before.toString('utf8');
const once=(from,to)=>{assert.equal(text.split(from).length,2,from);text=text.replace(from,()=>to);};
once('Still required: root policy review and publication, direct decisions,','The independent technical policy review has passed and the exact policy has been published locally. Still required: direct decisions,');
once('This packet grants no requirement acceptance and contains no actual approval, fresh credential metadata, runtime renewal or successful export.',
 'Acceptance remains 23 of 109 criteria: three personal owner decisions and 20 delegated technical decisions, with 86 open. This packet grants no additional acceptance and contains no actual approval, fresh credential metadata, runtime renewal or successful export.');
once('<ul><li><a href="../docs/verification/wave5/root-runtime-review-20261017/operation-bundle.draft-a1.json">',
 `<p><a href="../${policyPath}">Published source-only policy</a> · <a href="../${reviewPath}">Independent policy review</a>. Policy bytes match the draft hash shown below. Independent review SHA-256:</p><pre>799aae6417ff8e223273bf14e8407e4b9f321df550d4c01a306b1e96bd855b50</pre><ul><li><a href="../docs/verification/wave5/root-runtime-review-20261017/operation-bundle.draft-a1.json">`);
assert.ok(!/<(?:img|iframe|link)\b|\b(?:src|href)=["']https?:|<form\b/i.test(text));
const anchors=[...text.matchAll(/href="([^"]+)"/g)].map(x=>x[1]);
for(const link of anchors){if(link.startsWith('#')){assert.ok(text.includes('id="'+link.slice(1)+'"'));continue;}assert.ok(link.startsWith('../'));assert.ok((await fs.lstat(path.resolve(root,'dist',link))).isFile());}
const output='dist/Jentra OS Runtime Continuation Review 20261017 r5 a2.html';
await fs.writeFile(path.join(root,output),text,{flag:'wx'});
const report={kind:'root-final-runtime-review-publication',publishedAt:new Date().toISOString(),passed:true,
 operationBundleSha256:'7b196512d368a4ac39f7113c0d5b04c21178cf0779179caf1f1f9fd8418d04de',
 previousHtml:{path:beforePath,sha256:hash(before)},html:{path:output,sha256:hash(text),bytes:Buffer.byteLength(text)},
 policy:{path:policyPath,sha256:'fddf8cab9460aa590889468fc0bcd693a857697a6da8ffe6e24e3b14b6665813'},
 policyReview:{path:reviewPath,sha256:'799aae6417ff8e223273bf14e8407e4b9f321df550d4c01a306b1e96bd855b50'},
 checkedLinks:anchors.length,externalAssets:0,credentialForms:0,actualPriorCharge:137,actualCallsByThisPublication:0,
 sourceReviewOnly:true,privateInputsRead:false,humanDecisionsCreated:false,actualRuntimeRenewed:false,additionalAcceptance:0,
 renewalExportDecisionRequired:true,separatePausedScheduleHealthDecisionRequired:true,schedulerDecisionMustBeLater:true,
 wholeSystemComplete:false,production:false,realBilling:false};
await fs.writeFile(path.join(root,base+'root-final-publication-a2.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify(report)+'\n');
