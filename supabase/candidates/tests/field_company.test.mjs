import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
export async function exercise(db,checks){
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);};
 const deny=async(name,code,work)=>{await db.exec('savepoint denial');let error;try{await work();}catch(e){error=e;}
  await db.exec('rollback to savepoint denial;release savepoint denial');assert.equal(error?.code,code,name+': '+error?.message);checks.push(name);};
 await db.exec('reset role');
 const fixture=(await db.query(`select r.*,c.created_by owner_id from field_sales.order_requests r
  join crm.parties c on c.id=r.customer_id where r.input->>'reference'='EMAIL-SYNTHETIC'`)).rows[0];
 const t=fixture.tenant_id,e=fixture.legal_entity_id,b=fixture.branch_id;
 const contact=(await db.query('select * from field_sales.confirmation_contacts where tenant_id=$1',[t])).rows[0];
 const actor=async(id,aal='aal2')=>{await db.exec('reset role');const session=await value('select id from auth.sessions where user_id=$1',[id]);
  await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:id,aal,session_id:session})]);await db.exec('set local role authenticated');};
 await actor(fixture.rep_id);
 await deny('field representative cannot enumerate company confirmation subjects','42501',()=>value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b]));
 await actor(fixture.owner_id,'aal1');
 await deny('company confirmation workspace requires MFA','42501',()=>value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b]));
 await actor(fixture.owner_id);
 await deny('older confirmation command cannot bypass the reviewed staff wrapper','42501',()=>value('select api.field_sales_confirmation_command($1,$2,$3,$4,$5,now(),$6,$7,null)',[t,e,b,randomUUID(),randomUUID(),'issue_order',{}]));
 const rows=await value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b]);
 check('company workspace lists approved requests with independent customer and provider state',rows.items.length===1&&rows.items[0].company_state==='approved'&&rows.items[0].customer_state==='accepted'&&rows.provider_state==='configured');
 await deny('company workspace enforces maximum page size','22023',()=>value('select api.field_sales_confirmation_subjects($1,$2,$3,null,201)',[t,e,b]));
 const history=await value('select api.field_sales_confirmation_challenges($1,$2,$3,$4)',[t,e,b,fixture.id]);
 check('company history redacts secrets and exposes challenge versions for revocation',history.items.length===1&&history.items[0].version==='1'&&history.items[0].effective_state==='accepted'&&!JSON.stringify(history).includes('token_hash')&&!JSON.stringify(history).includes('proof_hash'));
 await deny('company cannot substitute a foreign request identifier','42501',()=>value('select api.field_sales_confirmation_challenges($1,$2,$3,$4)',[t,e,b,randomUUID()]));
 const payload={id:randomUUID(),request_id:fixture.id,request_version:fixture.version.toString(),source_digest:fixture.source_digest,contact_id:contact.id,contact_version:'99'};
 const command=randomUUID(),key=randomUUID();
 const cmd=()=>value('select api.field_sales_confirmation_company_command($1,$2,$3,$4,$5,now(),$6,$7,null)',[t,e,b,command,key,'issue_order',payload]);
 await deny('staff issue cannot silently use a changed contact revision','40001',cmd);
 payload.contact_version=contact.version.toString();
 await deny('current accepted terms cannot be silently superseded by another staff issue','55000',cmd);
 await value('select api.field_sales_confirmation_company_command($1,$2,$3,$4,$5,now(),$6,$7,$8)',[t,e,b,randomUUID(),randomUUID(),'revoke_challenge',
  {id:history.items[0].id,reason:'Explicit company review before a new recipient request'},history.items[0].version]);
 const issued=await cmd();
 check('staff-reviewed issue queues a challenge without activating email',issued.entity.state==='queued_link'&&issued.entity.contact_version===payload.contact_version);
 assert.deepEqual(await cmd(),issued);checks.push('staff issue exact retry preserves the original queued result');
 await db.exec('reset role');
 await db.query('update field_sales.confirmation_contacts set version=version+1 where id=$1',[contact.id]);await actor(fixture.owner_id);
 payload.contact_version=(BigInt(contact.version)+1n).toString();
 await deny('same command cannot silently replace its reviewed contact revision','22023',cmd);
 const recovered=await value('select api.field_sales_confirmation_receipt($1,$2,$3,$4)',[t,e,b,key]);
 check('staff receipt recovery retains the original contact revision after a later change',recovered.receipt.entity.contact_version===contact.version.toString());
 await db.exec('reset role;savepoint unique_challenge');
 await deny('all issue paths retain one current challenge per request','23505',()=>db.query(`insert into field_sales.confirmation_challenges
  select (jsonb_populate_record(null::field_sales.confirmation_challenges,to_jsonb(c)||jsonb_build_object('id',$1::text))).* from field_sales.confirmation_challenges c where id=$2`,[randomUUID(),payload.id]));
 await db.exec('rollback to savepoint unique_challenge;release savepoint unique_challenge');
 await db.exec('savepoint narrow_company');
 await db.query("delete from core.role_permissions where tenant_id=$1 and permission_code in('sales.orders.view','sales.orders.manage','sales.field.discounts.decide')",[t]);await actor(fixture.owner_id);
 check('confirmations manager can use the workspace without broad order or discount grants',(await value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b])).items.length===1);
 await db.exec('reset role;rollback to savepoint narrow_company;release savepoint narrow_company');
 await db.exec('reset role;set local role anon');
 await deny('anonymous recipient cannot open the company workspace','42501',()=>value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b]));
}
