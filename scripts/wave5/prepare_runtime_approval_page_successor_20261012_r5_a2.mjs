// Preserve the first human page; make execution dates explicit in a new page.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const hash=b=>createHash('sha256').update(b).digest('hex');
const original='dist/Jentra OS Runtime Approval 20261012 r5.html';
const priorJournal='docs/verification/wave5/runtime-approval-page-20261012-r5.json';
const page='dist/Jentra OS Runtime Approval 20261012 r5 a2.html';
const journal='docs/verification/wave5/runtime-approval-page-20261012-r5-a2.json';
const raw=await readFile(path.join(root,original)),priorRaw=await readFile(path.join(root,priorJournal));
const prior=JSON.parse(priorRaw);
if(hash(raw)!=='d21dc56b4a59a37147877782fff145b5419bcac69b81862b9ba0956982e27d9f'||prior.page.sha256!==hash(raw)||prior.ownerApproved!==false)throw Error('PRESERVED_PRIOR_PAGE_REQUIRED');
const nativeRaw=await readFile(path.join(root,'docs/verification/wave5/native-preview-userflows-20261010-r5.json'));
if(hash(nativeRaw)!=='4a8783db056143e7cf6d8031bc30dba7ff7707e315324892acf05fa2fac42840')throw Error('ACTUAL_NATIVE_RECORD_REQUIRED');
let html=raw.toString('utf8');
const replacements=[
 ['Desktop tests passed / failed / skipped. Actually executed October 10; matching source bytes were rechecked.','Desktop tests passed / failed / skipped. Executed October 10; all 1,068 source inputs revalidated October 12.'],
 ['Native Preview cases passed / failed / blocked. Full authenticated keyboard and accounting checks remain open.','Native Preview cases passed / failed / blocked. Executed October 11; 33 image files include 29 distinct hashes. Authenticated keyboard and accounting checks remain open.']
];
for(const [before,after]of replacements){if(html.split(before).length!==2)throw Error('EXACT_VISIBLE_COPY_REQUIRED');html=html.replace(before,after);}
const bytes=Buffer.from(html);
// Embedded downloads must remain byte-for-byte identical.
const embedded=b=>[...b.toString('utf8').matchAll(/href="data:[^"]+;base64,([A-Za-z0-9+/=]+)"/g)].map(x=>hash(Buffer.from(x[1],'base64')));
if(JSON.stringify(embedded(bytes))!==JSON.stringify(embedded(raw))||embedded(bytes).length!==2)throw Error('EMBEDDED_REVIEWS_CHANGED');
await writeFile(path.join(root,page),bytes,{flag:'wx'});
if(hash(await readFile(path.join(root,original)))!==hash(raw)||hash(await readFile(path.join(root,priorJournal)))!==hash(priorRaw))throw Error('PRIOR_PAGE_CHANGED');
const record={...prior,kind:'dated-self-contained-runtime-approval-page-successor',preparedAt:new Date().toISOString(),
 priorPage:{path:original,sha256:hash(raw),bytes:raw.length},priorJournal:{path:priorJournal,sha256:hash(priorRaw)},
 page:{path:page,sha256:hash(bytes),bytes:bytes.length},corrections:['Explicit October10 suite/October12 source revalidation dates','Explicit October11 native date/33 image files/29 distinct hashes'],
 embeddedReviewsChanged:false,runtimeReviewChanged:false,operationScopeChanged:false,priorPageOverwritten:false,approvalRecorded:false};
await writeFile(path.join(root,journal),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(record));
