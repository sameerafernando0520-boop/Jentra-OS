import {edgeConfiguration as config} from '../../workers/wave5/edge_configuration.mjs';

const units=value=>typeof value==='string'&&/^(0|[1-9][0-9]{0,19})$/.test(value);
// This assesses the fixed read-only SQL projection. It cannot authenticate an
// uploaded snapshot or turn database rows into provider/HTTP observations.
export function assessHostedAccounting(snapshot,{now=Date.now()}={}){
 const failures=new Set(),fail=code=>failures.add(code);
 const result={kind:'jentra-ai-integrations-ledger-assessment',ledgerReconciled:false,
  settledModels:0,unresolvedModels:0,acknowledgedDeliveries:0,unresolvedDeliveries:0,quotaPeriods:0,
  hostedModelResponseVerified:false,externalDeliveryVerified:false,failures:[],
  boundary:'Ledger consistency only; snapshot authenticity, actual provider responses and actual outbound HTTP delivery require separate current observations.'};
 const observed=typeof snapshot?.observedAt==='string'?Date.parse(snapshot.observedAt):NaN;
 if(!snapshot||snapshot.contractRevision!==1||snapshot.projectId!==config.projectId||snapshot.runtimeId!==config.runtimeId||
  !Number.isFinite(now)||!Number.isFinite(observed)||observed>now||now-observed>300000||
  snapshot.truncated!==false||![snapshot.models,snapshot.deliveries,snapshot.quotas].every(a=>Array.isArray(a)&&a.length<=1000)){
  return {...result,failures:['CURRENT_COMPLETE_HOSTED_SNAPSHOT_REQUIRED']};
 }
 if(snapshot.authorityActive!==true)fail('RUNTIME_AUTHORITY_INACTIVE');
 for(const row of snapshot.models){
  if(row?.state==='settled'){
   if(!units(row.reserved)||!units(row.tokens)||!units(row.quantity)||row.metric!=='ai.tokens'||
    row.eventMatches!==true||row.reservationMatches!==true||row.sourceMatches!==true||
    row.tokens!==row.quantity||BigInt(row.reserved)<BigInt(row.tokens))fail('MODEL_SETTLEMENT_MISMATCH');
   else result.settledModels++;
  }else if(row?.state==='pending'||row?.state==='unknown'){
   result.unresolvedModels++;fail('MODEL_OUTCOME_UNRESOLVED');
   if(row.quantity!==null||row.tokens!==null)fail('MODEL_SETTLEMENT_MISMATCH');
  }else fail('MODEL_SETTLEMENT_MISMATCH');
 }
 for(const row of snapshot.deliveries){
  if(row?.state==='acknowledged'){
   if(row.outcome!=='acknowledged'||!Number.isInteger(row.attempt)||row.attempt<1||row.attempt>8||
    !Number.isInteger(row.httpStatus)||row.httpStatus<200||row.httpStatus>=300||row.reserved!=='1'||row.quantity!=='1'||
    row.metric!=='webhook.deliveries'||row.eventMatches!==true||row.receiptPresent!==true||
    row.receiptHashMatches!==true||row.receiptKeyMatches!==true)fail('DELIVERY_ACKNOWLEDGEMENT_MISMATCH');
   else result.acknowledgedDeliveries++;
  }else if(['pending','leased','retry','unknown','dead_letter'].includes(row?.state)){
   result.unresolvedDeliveries++;fail('DELIVERY_OUTCOME_UNRESOLVED');
   if(row.quantity!==null)fail('DELIVERY_ACKNOWLEDGEMENT_MISMATCH');
  }else fail('DELIVERY_ACKNOWLEDGEMENT_MISMATCH');
 }
 for(const row of snapshot.quotas){
  result.quotaPeriods++;
  if(!row||![row.settled,row.expectedSettled,row.reserved,row.expectedReserved].every(units)||
   row.settled!==row.expectedSettled||row.reserved!==row.expectedReserved)fail('QUOTA_BALANCE_MISMATCH');
 }
 if(!snapshot.models.length)fail('NONEMPTY_MODEL_USAGE_REQUIRED');
 if(!snapshot.deliveries.length)fail('NONEMPTY_DELIVERY_REQUIRED');
 if(!snapshot.quotas.length)fail('NONEMPTY_QUOTA_REQUIRED');
 result.failures=[...failures];
 result.ledgerReconciled=failures.size===0&&result.settledModels>0&&result.acknowledgedDeliveries>0&&result.quotaPeriods>0;
 return result;
}
