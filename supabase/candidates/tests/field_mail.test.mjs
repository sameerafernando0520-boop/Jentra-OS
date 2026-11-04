import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {sendOne} from '../../../workers/field-sales/mail_worker.mjs';

export async function exercise(db,checks){
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);};
 const deny=async(name,code,work)=>{await db.exec('savepoint mail_denial');let error;try{await work();}catch(e){error=e;}
  await db.exec('rollback to savepoint mail_denial;release savepoint mail_denial');assert.equal(error?.code,code,name+': '+error?.message);checks.push(name);};
 await db.exec('reset role');
 const fixture=(await db.query(`select r.*,c.created_by owner_id from field_sales.order_requests r
  join crm.parties c on c.id=r.customer_id where r.input->>'reference'='EMAIL-SYNTHETIC'`)).rows[0];
 const t=fixture.tenant_id,e=fixture.legal_entity_id,b=fixture.branch_id;
 const contact=(await db.query('select * from field_sales.confirmation_contacts where tenant_id=$1',[t])).rows[0];
 const session=await value('select id from auth.sessions where user_id=$1',[fixture.owner_id]);
 const key='c'.repeat(64),fingerprint=createHash('sha256').update(Buffer.from(key,'hex')).digest('hex');
 const actor=async(role,user=null)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(user?{sub:user,aal:'aal2',session_id:session}:{})]);await db.exec('set local role '+role);};
 await actor('authenticated',fixture.owner_id);
 await deny('company cannot claim private mail jobs','42501',()=>value('select api.field_sales_mail_claim($1,$2)',[[t],randomUUID()]));
 await actor('anon');
 await deny('anonymous client cannot read raw mail policies','42501',()=>db.query('select * from field_sales.mail_policies'));
 await deny('anonymous client cannot send, claim or acknowledge mail','42501',()=>value('select api.field_sales_mail_step($1,$2,$3,$4)',[t,randomUUID(),randomUUID(),'ack']));
 await actor('service_role');
 check('new worker is idle without an enabled organization policy',(await value('select api.field_sales_mail_claim($1,$2)',[[t],randomUUID()])).state==='idle');
 await db.exec('reset role');
 await db.query(`insert into field_sales.mail_policies(tenant_id,enabled,provider,credential_alias,key_version,secret_key_sha256,
  sender_email,confirmation_origin,domain_evidence_sha256,reviewed_by) values($1,false,'resend','platform','v1',$2,
  'sales@example.invalid','https://jentra-os-sales.web.app',$3,$4)`,[t,fingerprint,'d'.repeat(64),fixture.owner_id]);
 check('mail readiness is fail closed even when legacy transport was configured',await value('select field_sales.confirmation_ready($1)',[t])===false);
 await db.query('update field_sales.mail_policies set enabled=true where tenant_id=$1',[t]);
 await actor('authenticated',fixture.owner_id);
 const challenge=randomUUID();
 await value('select api.field_sales_confirmation_company_command($1,$2,$3,$4,$5,now(),$6,$7,null)',[t,e,b,randomUUID(),randomUUID(),'issue_order',{
  id:challenge,request_id:fixture.id,request_version:fixture.version.toString(),source_digest:fixture.source_digest,
  contact_id:contact.id,contact_version:contact.version.toString(),
 }]);
 await actor('service_role');
 check('another organization cannot claim this organization\'s message',(await value('select api.field_sales_mail_claim($1,$2)',[[randomUUID()],randomUUID()])).state==='idle');
 const lease=randomUUID();const claimed=await value('select api.field_sales_mail_claim($1,$2)',[[t],lease]);
 check('claim pins one recipient, purpose, organization and reviewed sender policy',claimed.state==='claimed'&&claimed.tenant_id===t&&claimed.kind==='order_link'&&claimed.snapshot.recipient==='buyer@example.invalid'&&claimed.snapshot.secret_key_sha256===fingerprint);
 check('active leases prevent a second worker from taking the same message',(await value('select api.field_sales_mail_claim($1,$2)',[[t],randomUUID()])).state==='idle');
 await deny('another lease cannot prepare or acknowledge the selected message','42501',()=>value('select api.field_sales_mail_step($1,$2,$3,$4,$5)',[t,claimed.id,randomUUID(),'prepare','a'.repeat(64)]));
 await db.exec('reset role');
 await db.query("update field_sales.mail_jobs set lease_until=clock_timestamp()-interval '1 second' where id=$1",[claimed.id]);
 await actor('service_role');
 const recovered=await value('select api.field_sales_mail_claim($1,$2)',[[t],randomUUID()]);
 check('expired worker lease recovers the same immutable job and body',recovered.id===claimed.id&&JSON.stringify(recovered.snapshot)===JSON.stringify(claimed.snapshot));
 await db.exec('reset role');await db.query("update field_sales.mail_jobs set lease_until=clock_timestamp()-interval '1 second' where id=$1",[claimed.id]);await actor('service_role');
 const providerCalls=[],rpc=async(name,p)=>{
  if(name==='field_sales_mail_claim')return value('select api.field_sales_mail_claim($1,$2)',[p.p_tenant_ids,p.p_lease_id]);
  return value('select api.field_sales_mail_step($1,$2,$3,$4,$5,$6)',[p.p_tenant_id,p.p_job_id,p.p_lease_id,p.p_action,p.p_secret??null,p.p_provider_reference??null]);
 };
 const fetchImpl=async(url,init)=>{providerCalls.push([url,init]);return Response.json({id:randomUUID()});};
 const sent=await sendOne({tenantIds:[t],rpc,providerKeys:{platform:'private-test-provider'},secretKeys:{v1:key},fetchImpl});
 check('actual worker/RPC composition records provider acceptance without delivery or order acceptance',sent.state==='provider_accepted'&&sent.delivery==='not_established'&&providerCalls.length===1);
 const mail=JSON.parse(providerCalls[0][1].body),token=mail.text.match(/#confirm=([0-9a-f]{64})/)[1];
 await db.exec('reset role');
 check('queue stores neither the bearer nor a verification code',!(await value('select jsonb_agg(to_jsonb(j))::text from field_sales.mail_jobs j')).includes(token));
 check('provider acceptance never advances a canonical draft',await value('select status from sales.sales_orders where id=$1',[fixture.canonical_order_id])==='draft');
 await actor('anon');await db.query("select set_config('request.method','POST',true)");
 check('a delivered test link still requires a separate code request',(await value('select api.field_sales_confirmation_request_code($1)',[token])).state==='check_email');
 await actor('service_role');
 const codeSent=await sendOne({tenantIds:[t],rpc,providerKeys:{platform:'private-test-provider'},secretKeys:{v1:key},fetchImpl});
 check('separate verification message uses its own job and provider idempotency identity',codeSent.state==='provider_accepted'&&providerCalls.length===2&&providerCalls[1][1].headers['Idempotency-Key']!==providerCalls[0][1].headers['Idempotency-Key']);
 const codeMail=JSON.parse(providerCalls[1][1].body),code=codeMail.text.match(/code: (\d{6})/)[1];
 await actor('anon');
 check('worker-generated code opens only the exact challenged order',(await value('select api.field_sales_confirmation_verify($1,$2)',[token,code])).state==='review');
 await db.exec('reset role');await db.query('update field_sales.mail_policies set enabled=false where tenant_id=$1',[t]);
 await actor('service_role');
 check('organization kill switch prevents further message claims',(await value('select api.field_sales_mail_claim($1,$2)',[[t],randomUUID()])).state==='idle');
}
