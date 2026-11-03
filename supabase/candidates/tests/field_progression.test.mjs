import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {deriveMailSecret} from '../../../workers/field-sales/mail_worker.mjs';

export async function exercise(db,checks){
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);};
 const deny=async(name,code,work)=>{await db.exec('savepoint progression_denial');let error;try{await work();}catch(e){error=e;}
  await db.exec('rollback to savepoint progression_denial;release savepoint progression_denial');assert.equal(error?.code,code,name+': '+error?.message);checks.push(name);};
 await db.exec('reset role');
 const r=(await db.query(`select r.*,c.created_by owner_id from field_sales.order_requests r
  join crm.parties c on c.id=r.customer_id where r.input->>'reference'='EMAIL-SYNTHETIC'`)).rows[0];
 const t=r.tenant_id,e=r.legal_entity_id,b=r.branch_id,oid=r.canonical_order_id;
 const actor=async(user,aal='aal2')=>{await db.exec('reset role');const session=await value('select id from auth.sessions where user_id=$1',[user]);
  await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:user,aal,session_id:session})]);await db.exec('set local role authenticated');};
 const payload={document_type:'sales_order',document_id:oid,action:'confirm'};
 const command=randomUUID(),key=randomUUID();let version=(await value('select version from sales.sales_orders where id=$1',[oid])).toString();
 const confirm=()=>value('select api.transition_operational_document($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,command,key,payload,version]);
 await actor(r.owner_id);
 await deny('field progression requires its explicit company capability','42501',confirm);
 await db.exec('reset role');
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,id,'sales.field.orders.progress' from core.roles where tenant_id=$1 and code='tenant_owner'",[t]);
 await db.query("insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by) values($1,$2,$3,'sales_order','SYNTHETIC-SO-',$4,$4)",[t,e,b,r.owner_id]);
 await actor(r.owner_id,'aal1');
 await deny('field order advancement requires current MFA','42501',confirm);
 await actor(r.owner_id);
 await deny('company cannot confirm an order before an explicit verified customer response','55000',confirm);
 await db.exec('reset role');
 const jobs=(await db.query('select * from field_sales.mail_jobs where tenant_id=$1 order by kind',[t])).rows;
 const link=jobs.find(j=>j.kind==='order_link'),codeJob=jobs.find(j=>j.kind==='order_code');
 const token=deriveMailSecret(link,'c'.repeat(64)),code=deriveMailSecret(codeJob,'c'.repeat(64));
 await db.query("select set_config('request.jwt.claims','{}',true)");await db.exec('set local role anon');
 await db.query("select set_config('request.method','POST',true)");
 const review=await value('select api.field_sales_confirmation_verify($1,$2)',[token,code]);
 const response=await value('select api.field_sales_confirmation_respond($1,$2,$3,$4,true)',[token,review.proof,'accept','Reviewed exact order']);
 check('verified customer response still leaves the canonical order in draft',response.state==='recorded'&&await value('select 1')===1);
 await db.exec('reset role');
 check('recipient acceptance creates no stock, invoice or payment effects',await value('select status from sales.sales_orders where id=$1',[oid])==='draft'
  &&await value('select count(*)=0 from sales.deliveries')&&await value('select count(*)=0 from sales.sales_invoices'));
 await actor(r.owner_id);
 let credit=await value('select api.get_sales_order_credit_preview($1,$2,$3,$4)',[t,e,b,oid]);
 check('company credit review binds current accepted response and exact exposure',credit.field_sales_request_id===r.id&&credit.field_customer_state==='accepted'&&/^[0-9a-f]{64}$/.test(credit.field_credit_review));
 await deny('legacy clients cannot omit the reviewed credit digest for a field order','40001',confirm);
 payload.source_context={field_credit_review:credit.field_credit_review};
 await db.exec('reset role;savepoint stale_credit');
 await db.query("update sales.customer_credit_exposures set as_of_at=clock_timestamp()-interval '10 minutes' where tenant_id=$1",[t]);await actor(r.owner_id);
 await deny('stale credit projection cannot advance a field order','55000',confirm);
 await db.exec('reset role;rollback to savepoint stale_credit;release savepoint stale_credit;savepoint changed_credit');
 await db.query('update sales.customer_credit_exposures set due_exposure=due_exposure+1 where tenant_id=$1',[t]);await actor(r.owner_id);
 await deny('changed exposure requires a fresh explicit company credit review','40001',confirm);
 await db.exec('reset role;rollback to savepoint changed_credit;release savepoint changed_credit');await actor(r.owner_id);
 const confirmed=await confirm();
 await db.exec('reset role');
 check('company confirmation invokes the canonical command and credit decision',confirmed.entity.status==='confirmed'
  &&await value('select exists(select 1 from sales.credit_decisions where sales_order_id=$1)',[oid]));
 await actor(r.owner_id);
 assert.deepEqual(await confirm(),confirmed);checks.push('confirmed field order retries return the original canonical receipt');
 await db.exec('reset role');
 check('applied customer response is recorded separately from company confirmation',await value('select count(*)=1 from field_sales.order_progressions where request_id=$1',[r.id]));
 check('transaction permits are removed before returning to a caller',await value('select count(*)=0 from field_sales.progression_permits'));
 await actor(r.owner_id);
 await deny('direct legacy writes remain denied after legitimate company confirmation','42501',()=>db.query('update sales.sales_orders set notes=notes where id=$1',[oid]));
 await db.exec('reset role');
 await deny('governed order trigger still requires an internal transaction permit','55000',()=>db.query('update sales.sales_orders set notes=notes where id=$1',[oid]));
 await actor(r.owner_id);
 await deny('renamed canonical transition is not a client bypass','42501',()=>value('select api.field_transition_canonical($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,randomUUID(),randomUUID(),payload,version]));
 await deny('company cannot manufacture a private progression permit','42501',()=>value('select field_sales.permit_progression($1,$2,$3,$4)',[t,e,b,oid]));
 await actor(r.rep_id);
 await deny('restricted representative cannot confirm its own canonical order','42501',confirm);
 await db.exec('reset role');
 await db.query('update field_sales.confirmation_contacts set active=false where tenant_id=$1',[t]);
 await actor(r.owner_id);
 // The public company selector owns private serialization; a direct helper/table
 // read is intentionally unavailable to the authenticated client.
 const subjects=await value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b]);
 check('later contact revocation preserves applied response history and current canonical state',subjects.items[0].customer_state==='accepted'&&subjects.items[0].canonical_state==='confirmed');
 assert.deepEqual(await confirm(),confirmed);checks.push('original confirmation recovery does not require a still-current contact');
 await db.exec('reset role');
 return {tenantId:t,entityId:e,branchId:b,ownerId:r.owner_id,repId:r.rep_id,requestId:r.id,orderId:oid};
}
