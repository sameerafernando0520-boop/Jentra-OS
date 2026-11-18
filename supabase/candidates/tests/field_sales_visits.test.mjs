import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// Live customer visits (20261117100000_field_sales_visits.sql). Runs on the
// combined install with Field Sales switched on, in its own organization.
export async function exercise(db,checks){
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const scalar=async(sql,args=[])=>Object.values(await one(sql,args))[0];
 const check=(name,value)=>{assert.ok(value,name);checks.push(name);};
 const reject=async(name,code,work,message)=>{
  await db.exec('savepoint attack');let caught;try{await work();}catch(e){caught=e;}
  await db.exec('rollback to savepoint attack;release savepoint attack');
  assert.equal(caught?.code,code,name+': '+(caught?.message??'allowed'));
  if(message!==undefined)assert.equal(caught?.message,message,name+': unexpected rejection reason');
  checks.push(name);
 };
 const ids=Object.fromEntries(['owner','rep','rep2','m1','m2','fieldRole','c1','c2','c3','assignment','employee','link','visit','visit2'].map(k=>[k,randomUUID()]));
 const users=[ids.owner,ids.rep,ids.rep2];
 const sessions=new Map(users.map(id=>[id,randomUUID()]));
 const actor=async(id,aal='aal2',sessionId=sessions.get(id))=>{
  await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:id,aal,session_id:sessionId})]);
  await db.exec('set local role authenticated');
 };
 for(const id of users) await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,'person-'+id.slice(0,8)+'@visits.invalid']);
 for(const [user,session] of sessions) await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,user]);
 await actor(ids.owner);
 const scope=await scalar("select api.bootstrap_tenant('Synthetic Visits','synthetic-visits','Visits Company','VC','Head Office','HQ','Asia/Colombo','LKR',$1)",[randomUUID()]);
 const t=scope.tenant_id,e=scope.legal_entity_id,b=scope.branch_id;
 await db.exec('reset role');
 await db.query("insert into core.memberships(id,tenant_id,user_id,status) values($1,$2,$3,'active'),($4,$2,$5,'active')",[ids.m1,t,ids.rep,ids.m2,ids.rep2]);
 await db.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values($1,$2,'field_rep','Field rep',false)",[ids.fieldRole,t]);
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,$2,code from core.permissions",[t,ids.fieldRole]);
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,id,p.code from core.roles cross join core.permissions p where tenant_id=$1 and core.roles.code='tenant_owner' and p.code like 'sales.field.%' on conflict do nothing",[t]);
 for(const m of [ids.m1,ids.m2]) await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values($1,$2,$3,$4,$5,$6)',[t,m,ids.fieldRole,e,b,ids.owner]);
 for(const rep of [ids.rep,ids.rep2]) await db.query('insert into field_sales.principals values($1,$2)',[t,rep]);
 for(const [id,code] of [[ids.c1,'C1'],[ids.c2,'C2'],[ids.c3,'C3']]) await db.query(`insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
  values($1,$2,$3,$3,$3,'customer',100000,$4,$4)`,[id,t,code,ids.owner]);
 for(const [id,rep,customer] of [[ids.assignment,ids.rep,ids.c1],[randomUUID(),ids.rep2,ids.c2]]) await db.query(`insert into field_sales.assignments(id,tenant_id,legal_entity_id,branch_id,rep_id,customer_id,valid_from,valid_until,ship_to,payment_terms_days,delivery_terms)
  values($1,$2,$3,$4,$5,$6,now()-interval '1 day',now()+interval '1 day','{"address":"Approved"}',30,'Company delivery')`,[id,t,e,b,rep,customer]);
 await db.query("insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by) values($1,$2,$3,'EMP_V','Asha Perera',$4,$4)",[ids.employee,t,e,ids.owner]);
 await db.query("insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at) values($1,$2,$3,$4,$5,$6,$7,'accepted',$8,now())",
  [ids.link,t,e,b,ids.employee,ids.m1,ids.rep,ids.owner]);

 const command=(action,payload,version=null,cmd=randomUUID(),key=randomUUID())=>
  scalar('select api.field_sales_visit_command($1,$2,$3,$4,$5,now(),$6,$7,$8)',[t,e,b,cmd,key,action,payload,version]);
 const today=await scalar("select (now() at time zone 'Asia/Colombo')::date::text");
 const plan={id:ids.visit,customer_id:ids.c1,purpose:'Quarterly stock review',planned_for:today};
 const planCmd=randomUUID(),planKey=randomUUID();

 await actor(ids.rep);
 check('a field account holds the visit permission and still no broad CRM access',
  await scalar("select core.has_permission($1,'sales.field.visits.record',$2,$3) and not core.has_permission($1,'crm.parties.view',$2,$3)",[t,e,b]));
 const planned=await command('plan',plan,null,planCmd,planKey);
 check('a rep plans a visit to an assigned customer',planned.entity.state==='planned'&&planned.entity.version==='1'&&
  planned.entity.rep_id===ids.rep&&planned.entity.customer_name==='C1'&&planned.entity.purpose==='Quarterly stock review'&&planned.entity.planned_for===today);
 check('a planned visit carries no location',planned.entity.check_in_location===null&&planned.entity.complete_location===null);
 assert.deepEqual(await command('plan',plan,null,planCmd,planKey),planned);checks.push('an exact retry returns the original receipt');
 await reject('a changed payload cannot reuse the command identity','22023',()=>command('plan',{...plan,purpose:'Changed'},null,planCmd,planKey),'IDEMPOTENCY_MISMATCH');
 await reject('a second plan with the same visit id is a conflict','40001',()=>command('plan',plan),'VERSION_CONFLICT');
 await reject('a plan cannot carry an expected version','40001',()=>command('plan',{...plan,id:randomUUID()},1),'VERSION_CONFLICT');
 await reject('another rep\'s customer is refused','42501',()=>command('plan',{...plan,id:randomUUID(),customer_id:ids.c2}),'ASSIGNMENT_CHANGED');
 await reject('an unassigned customer is refused','42501',()=>command('plan',{...plan,id:randomUUID(),customer_id:ids.c3}),'ASSIGNMENT_CHANGED');
 await reject('location is not taken when planning','22023',()=>command('plan',{...plan,id:randomUUID(),latitude:'6.9',longitude:'79.8'}),'VISIT_COMMAND_INVALID');
 await reject('a purpose is required','22023',()=>command('plan',{...plan,id:randomUUID(),purpose:'  '}),'VISIT_FIELDS_INVALID');
 await reject('an unknown action is refused','22023',()=>command('track',{id:ids.visit,latitude:'6.9',longitude:'79.8'},1),'VISIT_COMMAND_INVALID');
 await reject('check in needs the current version','40001',()=>command('check_in',{id:ids.visit},2),'VERSION_CONFLICT');
 await reject('check in without a version is refused','40001',()=>command('check_in',{id:ids.visit}),'VERSION_CONFLICT');
 await reject('JSON numbers cannot be coordinates','22023',()=>command('check_in',{id:ids.visit,latitude:6.927079,longitude:79.861244},1),'LOCATION_INVALID');
 await reject('a coordinate needs its pair','22023',()=>command('check_in',{id:ids.visit,latitude:'6.927079'},1),'LOCATION_INVALID');
 await reject('a latitude beyond 90 degrees is refused','22023',()=>command('check_in',{id:ids.visit,latitude:'91',longitude:'79.8'},1),'LOCATION_INVALID');
 const checkCmd=randomUUID(),checkKey=randomUUID(),checkPayload={id:ids.visit,latitude:'6.927079',longitude:'-79.861244'};
 const checkedIn=await command('check_in',checkPayload,1,checkCmd,checkKey);
 check('check in records the time and the optional location given at that action',checkedIn.entity.state==='checked_in'&&checkedIn.entity.version==='2'&&
  checkedIn.entity.checked_in_at!==null&&checkedIn.entity.check_in_location.latitude==='6.927079'&&checkedIn.entity.check_in_location.longitude==='-79.861244');
 assert.deepEqual(await command('check_in',checkPayload,1,checkCmd,checkKey),checkedIn);checks.push('an exact check in retry after the version moved returns the original receipt');
 await reject('a second check in is refused','55000',()=>command('check_in',{id:ids.visit},2),'VISIT_STATE_INVALID');
 await reject('completion needs an outcome','22023',()=>command('complete',{id:ids.visit},2),'VISIT_FIELDS_INVALID');
 await reject('a next action date needs a next action','22023',()=>command('complete',{id:ids.visit,outcome:'Met buyer',next_action_due:today},2),'VISIT_FIELDS_INVALID');
 const completed=await command('complete',{id:ids.visit,outcome:'Met the buyer; samples left',next_action:'Send revised price list',next_action_due:today},2);
 check('completion records outcome and next action; location stays optional',completed.entity.state==='completed'&&completed.entity.version==='3'&&
  completed.entity.outcome==='Met the buyer; samples left'&&completed.entity.next_action==='Send revised price list'&&completed.entity.next_action_due===today&&
  completed.entity.complete_location===null&&completed.entity.check_in_location.latitude==='6.927079');
 await db.exec('reset role');
 const audit=await one("select actor_id,before_context->>'state' as before,after_context->>'state' as after from audit.events where aggregate_id=$1 and event_type='sales.field.visit.complete'",[ids.visit]);
 check('the audit trail records the rep as actor and the state before and after',audit.actor_id===ids.rep&&audit.before==='checked_in'&&audit.after==='completed');
 await actor(ids.rep);
 await reject('a completed visit cannot be cancelled','55000',()=>command('cancel',{id:ids.visit,reason:'Too late'},3),'VISIT_STATE_INVALID');
 await command('plan',{id:ids.visit2,customer_id:ids.c1,purpose:'Collect feedback'});
 await reject('cancellation needs a reason','22023',()=>command('cancel',{id:ids.visit2},1),'VISIT_FIELDS_INVALID');
 const cancelled=await command('cancel',{id:ids.visit2,reason:'Customer closed today'},1);
 check('a planned visit can be cancelled with a reason',cancelled.entity.state==='cancelled'&&cancelled.entity.cancel_reason==='Customer closed today');
 const own=await scalar('select api.field_sales_visits($1,$2,$3)',[t,e,b]);
 check('the rep reads its own visits',own.items.length===2&&own.items.every(v=>v.rep_id===ids.rep));
 check('receipt recovery finds the original visit command',(await scalar('select api.field_sales_visit_receipt($1,$2,$3,$4)',[t,e,b,checkKey])).receipt.command_id===checkCmd);
 check('an unknown key has no receipt',(await scalar('select api.field_sales_visit_receipt($1,$2,$3,$4)',[t,e,b,randomUUID()])).state==='not_found');
 await reject('raw visit rows are closed','42501',()=>db.query('select * from field_sales.visits'));
 await reject('visit helpers are private','42501',()=>scalar('select field_sales.coordinate($1,90)',['"1"']));
 await reject('a rep cannot read the company visit list','42501',()=>scalar('select api.field_sales_company_visits($1,$2,$3,$4::date,$4::date)',[t,e,b,today]));

 await actor(ids.rep2);
 check('another rep sees none of these visits',(await scalar('select api.field_sales_visits($1,$2,$3)',[t,e,b])).items.length===0);
 check('another rep cannot recover the original visit command',(await scalar('select api.field_sales_visit_receipt($1,$2,$3,$4)',[t,e,b,checkKey])).state==='not_found');
 await reject('another rep cannot act on the visit','42501',()=>command('cancel',{id:ids.visit2,reason:'Not mine'},2),'VISIT_NOT_FOUND');

 await actor(ids.owner);
 const company=await scalar('select api.field_sales_company_visits($1,$2,$3,$4::date,$4::date)',[t,e,b,today]);
 check('the company reads the branch visits with HR-derived rep labels',company.items.length===2&&company.items.every(v=>v.rep_label==='Asha Perera')&&!JSON.stringify(company).includes('@'));
 check('the company sees recorded locations and outcomes',company.items.some(v=>v.check_in_location?.latitude==='6.927079'&&v.outcome==='Met the buyer; samples left'));
 await reject('the company visit list needs MFA','42501',async()=>{await actor(ids.owner,'aal1');await scalar('select api.field_sales_company_visits($1,$2,$3,$4::date,$4::date)',[t,e,b,today]);});
 await actor(ids.owner);
 await reject('the company visit list refuses a bad period','22023',()=>scalar("select api.field_sales_company_visits($1,$2,$3,'2026-01-02','2026-01-01')",[t,e,b]),'PERIOD_INVALID');
 await reject('the company cannot record visits','42501',()=>command('plan',{...plan,id:randomUUID()}));

 await reject('visits need the Field Sales module','42501',async()=>{
  await db.exec('reset role');
  await db.query("update billing.plan_entitlements set enabled=false where entitlement_code='module.field_sales' and plan_code=(select plan_code from billing.tenant_subscriptions where tenant_id=$1)",[t]);
  await actor(ids.rep);await scalar('select api.field_sales_visits($1,$2,$3)',[t,e,b]);
 },'FIELD_SALES_ENTITLEMENT_REQUIRED');
 await reject('visits need the visit permission','42501',async()=>{
  await db.exec('reset role');await db.query("delete from core.role_permissions where tenant_id=$1 and role_id=$2 and permission_code='sales.field.visits.record'",[t,ids.fieldRole]);
  await actor(ids.rep);await scalar('select api.field_sales_visits($1,$2,$3)',[t,e,b]);
 });
 await reject('visits need a live Auth session','42501',async()=>{
  await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sessions.get(ids.rep)]);
  await actor(ids.rep);await scalar('select api.field_sales_visits($1,$2,$3)',[t,e,b]);
 },'FIELD_SESSION_REQUIRED');
 await db.exec('reset role');
 check('the visit table carries the organization lifecycle write guard',
  await scalar("select exists(select 1 from pg_trigger where tgrelid='field_sales.visits'::regclass and tgname='organization_write_lock')"));
 await db.query("update field_sales.assignments set valid_until=now()-interval '1 second' where id=$1",[ids.assignment]);
 await actor(ids.rep);
 check('revoking the assignment hides its visits from the rep',(await scalar('select api.field_sales_visits($1,$2,$3)',[t,e,b])).items.length===0);
 await reject('revoking the assignment blocks even an exact retry','42501',()=>command('check_in',checkPayload,1,checkCmd,checkKey),'ASSIGNMENT_CHANGED');
 await reject('revoking the assignment blocks receipt recovery','42501',()=>scalar('select api.field_sales_visit_receipt($1,$2,$3,$4)',[t,e,b,checkKey]),'ASSIGNMENT_CHANGED');
 await actor(ids.owner);
 check('the company keeps the visit history after revocation',(await scalar('select api.field_sales_company_visits($1,$2,$3,$4::date,$4::date)',[t,e,b,today])).items.length===2);
}
