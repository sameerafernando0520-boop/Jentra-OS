import {runDeliveryBatch} from './persistent_control.mjs';

/** Explicit configured launcher only. Scheduling is sequential and bounded;
 * neither constructing this module nor tests deploy/start a real worker. */
export async function runDeliverySchedule({control,vault,resolve,post,intervalMs=15000,limit=20,signal,onResult=()=>{},wait}) {
 if(!signal||!Number.isInteger(intervalMs)||intervalMs<1000||intervalMs>60000)throw Error('WORKER_SCHEDULE_INVALID');
 const pause=wait??(ms=>new Promise(resolve=>{const timer=setTimeout(done,ms);function done(){clearTimeout(timer);signal.removeEventListener('abort',done);resolve();}
  signal.addEventListener('abort',done,{once:true});if(signal.aborted)done();}));
 while(!signal.aborted){
  try{const rows=await runDeliveryBatch({control,vault,resolve,post,now:()=>Math.floor(Date.now()/1000),limit,signal});await onResult({state:'batch',count:rows.length});}
  catch(error){await onResult({state:'failure',code:/^[A-Z_]{1,80}$/.test(error.message)?error.message:'WORKER_PROVIDER_UNAVAILABLE'});}
  if(!signal.aborted)await pause(intervalMs);
 }
 return {state:'stopped'};
}
