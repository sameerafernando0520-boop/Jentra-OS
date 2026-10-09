import {activateScheduledTrial} from './worker_runtime.mjs';
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;

// Explicit trusted launcher only. A scan is resumable and bounded, and every
// activation reuses the installed command's immutable execution identity.
export async function runSyntheticSubscriptionBatch({control,after=null,limit=50,signal}) {
 if(!Number.isInteger(limit)||limit<1||limit>50||(after!==null&&!uuid.test(after)))throw Error('WORKER_LIMIT_INVALID');
 const page=await control.dueSyntheticSubscriptions(after);
 if(page?.contractRevision!==1||!Array.isArray(page.items)||page.items.length>50||
  (page.nextCursor!==null&&!uuid.test(page.nextCursor)))throw Error('WORKER_CONTRACT_MISMATCH');
 const results=[];
 for(const item of page.items.slice(0,limit)){
  if(signal?.aborted)break;
  if(!item||Object.keys(item).length!==2||!uuid.test(item.tenantId)||!uuid.test(item.revisionId))throw Error('WORKER_CONTRACT_MISMATCH');
  try{await activateScheduledTrial({control,...item});results.push({revisionId:item.revisionId,state:'applied'});}
  catch{results.push({revisionId:item.revisionId,state:'unconfirmed'});}
 }
 const next=results.length<page.items.length?(results.at(-1)?.revisionId??after):page.nextCursor;
 return {results,nextCursor:next};
}
