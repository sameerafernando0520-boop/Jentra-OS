import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// Sales rep to employee link (20261117090000_field_sales_reps.sql). Runs on the
// combined install with Field Sales switched on, in its own organization, so
// it does not depend on fixtures left by the other Field Sales exercises.
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
 const ids=Object.fromEntries(['owner','manager','rep','rep2','rep3','m1','m2','m3','mm','fieldRole','managerRole',
  'b2','c1','c2','c3','employee','employee2','link','link2','link3'].map(k=>[k,randomUUID()]));
 const users=[ids.owner,ids.manager,ids.rep,ids.rep2,ids.rep3];
 const sessions=new Map(users.map(id=>[id,randomUUID()]));
 const actor=async(id,aal='aal2',sessionId=sessions.get(id))=>{
  await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:id,aal,session_id:sessionId})]);
  await db.exec('set local role authenticated');
 };
 for(const id of users) await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,'person-'+id.slice(0,8)+'@reps.invalid']);
 for(const [user,session] of sessions) await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,user]);
 await actor(ids.owner);
 const scope=await scalar("select api.bootstrap_tenant('Synthetic Reps','synthetic-reps','Reps Company','RC','Head Office','HQ','Asia/Colombo','LKR',$1)",[randomUUID()]);
 const t=scope.tenant_id,e=scope.legal_entity_id,b=scope.branch_id;
 await db.exec('reset role');
 await db.query("insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values($1,$2,$3,'North Branch','NORTH',$4)",[ids.b2,t,e,ids.owner]);
 await db.query("insert into core.memberships(id,tenant_id,user_id,status) values($1,$2,$3,'active'),($4,$2,$5,'active'),($6,$2,$7,'active'),($8,$2,$9,'active')",
  [ids.m1,t,ids.rep,ids.m2,ids.rep2,ids.m3,ids.rep3,ids.mm,ids.manager]);
 await db.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values($1,$2,'field_rep','Field rep',false),($3,$2,'field_manager','Field manager',false)",[ids.fieldRole,t,ids.managerRole]);
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) values($1,$2,'sales.field.customers.view'),($1,$2,'sales.field.catalogue.view'),($1,$2,'sales.field.orders.submit'),($1,$2,'sales.field.discounts.decide'),($1,$3,'sales.field.discounts.decide')",[t,ids.fieldRole,ids.managerRole]);
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,id,p.code from core.roles cross join core.permissions p where tenant_id=$1 and core.roles.code='tenant_owner' and p.code like 'sales.field.%' on conflict do nothing",[t]);
 for(const [m,role,branch] of [[ids.m1,ids.fieldRole,b],[ids.m2,ids.fieldRole,b],[ids.m3,ids.fieldRole,ids.b2],[ids.mm,ids.managerRole,b]])
  await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values($1,$2,$3,$4,$5,$6)',[t,m,role,e,branch,ids.owner]);
 for(const rep of [ids.rep,ids.rep2,ids.rep3]) await db.query('insert into field_sales.principals values($1,$2)',[t,rep]);
 for(const [id,code] of [[ids.c1,'C1'],[ids.c2,'C2'],[ids.c3,'C3']]) await db.query(`insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
  values($1,$2,$3,$3,$3,'customer',100000,$4,$4)`,[id,t,code,ids.owner]);
 for(const [rep,customer,branch] of [[ids.rep,ids.c1,b],[ids.rep2,ids.c2,b],[ids.rep3,ids.c3,ids.b2]]) await db.query(`insert into field_sales.assignments(tenant_id,legal_entity_id,branch_id,rep_id,customer_id,valid_from,valid_until,ship_to,payment_terms_days,delivery_terms)
  values($1,$2,$3,$4,$5,now()-interval '1 day',now()+interval '1 day','{"address":"Approved"}',30,'Company delivery')`,[t,e,branch,rep,customer]);
 // HR links: the first rep has an accepted link, the second only a revoked one.
 for(const [employee,code,name] of [[ids.employee,'EMP_A','Asha Perera'],[ids.employee2,'EMP_B','Ruwan Silva']])
  await db.query('insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by) values($1,$2,$3,$4,$5,$6,$6)',[employee,t,e,code,name,ids.owner]);
 await db.query("insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at) values($1,$2,$3,$4,$5,$6,$7,'accepted',$8,now()),($9,$2,$3,$4,$10,$11,$12,'revoked',$8,now())",
  [ids.link,t,e,b,ids.employee,ids.m1,ids.rep,ids.owner,ids.link2,ids.employee2,ids.m2,ids.rep2]);
 // Approved requests need a canonical order reference. The order itself is
 // outside this exercise, so the fixture rows skip foreign-key triggers.
 const today=await scalar("select (now() at time zone 'Asia/Colombo')::date::text");
 const request=async(rep,customer,branch,state,total,age='0 days')=>{
  const decided=state!=='submitted';
  await db.query(`insert into field_sales.order_requests(id,tenant_id,legal_entity_id,branch_id,customer_id,rep_id,input,preview,source_digest,state,canonical_order_id,decision_by,decision_reason,decided_at,created_at)
   values($1,$2,$3,$4,$5,$6,'{}',$7,repeat('a',64),$8,$9,$10,$11,$12,now()-$13::interval)`,
   [randomUUID(),t,e,branch,customer,rep,{currency_code:'LKR',pricing:{grand_total:total}},state,
    state==='approved'?randomUUID():null,decided?ids.owner:null,decided?'Fixture decision':null,decided?new Date().toISOString():null,age]);
 };
 await db.exec("set local session_replication_role=replica");
 await request(ids.rep,ids.c1,b,'approved','100.250000');
 await request(ids.rep,ids.c1,b,'approved','0.100000');
 await request(ids.rep,ids.c1,b,'rejected','7.000000');
 await request(ids.rep,ids.c1,b,'submitted','3.000000');
 await request(ids.rep,ids.c1,b,'approved','999.000000','40 days');
 await request(ids.rep2,ids.c2,b,'submitted','12.500000');
 await request(ids.rep3,ids.c3,ids.b2,'approved','5.000000');
 await db.exec("set local session_replication_role=origin");

 const reps=(branch=b,from=today,to=today)=>scalar('select api.field_sales_reps($1,$2,$3,$4::date,$5::date)',[t,e,branch,from,to]);
 const week=await scalar("select ((now() at time zone 'Asia/Colombo')::date-7)::text");
 await actor(ids.owner);
 const list=await reps(b,week,today);
 const byUser=Object.fromEntries(list.items.map(x=>[x.user_id,x]));
 check('company rep list covers reps of this branch only',list.items.length===2&&byUser[ids.rep]&&byUser[ids.rep2]&&!byUser[ids.rep3]);
 check('linked rep is labelled with the employee name from the HR account link',byUser[ids.rep].label==='Asha Perera'&&byUser[ids.rep].linked===true);
 check('rep without an accepted link is labelled by the last four of the user id',
  byUser[ids.rep2].label==='Unlinked member ····'+ids.rep2.slice(-4)&&byUser[ids.rep2].linked===false);
 check('rep list never carries e-mail addresses or employee identifiers',
  !JSON.stringify(list).includes('@')&&!JSON.stringify(list).includes(ids.employee)&&!JSON.stringify(list).includes(ids.employee2));
 check('counts cover requests submitted in the period by current state',
  byUser[ids.rep].submitted_count==='4'&&byUser[ids.rep].pending_count==='1'&&byUser[ids.rep].approved_count==='2'&&byUser[ids.rep].rejected_count==='1');
 check('approved total is an exact base-currency decimal string for the period',
  byUser[ids.rep].approved_total==='100.350000'&&list.currency_code==='LKR');
 check('a rep with nothing approved shows an exact zero total',byUser[ids.rep2].approved_total==='0.000000'&&byUser[ids.rep2].approved_count==='0');
 check('current customer assignments are counted per rep',byUser[ids.rep].active_customer_count==='1');
 check('an earlier period counts the older approval only',
  (await reps(b,await scalar("select ((now() at time zone 'Asia/Colombo')::date-41)::text"),await scalar("select ((now() at time zone 'Asia/Colombo')::date-39)::text"))).items.find(x=>x.user_id===ids.rep).approved_total==='999.000000');
 check('the other branch lists its own rep and totals',(await reps(ids.b2,week,today)).items.map(x=>[x.user_id,x.approved_total]).join()===[ids.rep3,'5.000000'].join());
 check('reps are ordered by label',list.items[0].label==='Asha Perera');
 await reject('period end before start is refused','22023',()=>reps(b,today,week),'PERIOD_INVALID');
 await reject('period longer than a year is refused','22023',()=>reps(b,'2024-01-01','2026-01-01'),'PERIOD_INVALID');
 await reject('missing period is refused','22023',()=>reps(b,null,today),'PERIOD_INVALID');
 await reject('company rep list requires MFA','42501',async()=>{await actor(ids.owner,'aal1');await reps(b,week,today);});
 await actor(ids.manager);
 check('a branch manager reads the rep list of its branch',(await reps(b,week,today)).items.length===2);
 await reject('a branch manager cannot read another branch','42501',()=>reps(ids.b2,week,today));
 await actor(ids.rep);
 await reject('a rep cannot read the company rep list, even with a company permission','42501',()=>reps(b,week,today));
 await reject('the label helper is private','42501',()=>scalar('select field_sales.rep_label($1,$2)',[t,ids.rep2]));
 await reject('a rep still cannot read raw HR account links','42501',()=>db.query('select * from people_private.account_links'));
 await reject('the rep list needs the Field Sales module','42501',async()=>{
  await db.exec('reset role');
  await db.query("update billing.plan_entitlements set enabled=false where entitlement_code='module.field_sales' and plan_code=(select plan_code from billing.tenant_subscriptions where tenant_id=$1)",[t]);
  await actor(ids.owner);await reps(b,week,today);
 },'FIELD_SALES_ENTITLEMENT_REQUIRED');
 await reject('the rep list needs a live Auth session','42501',async()=>{
  await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sessions.get(ids.owner)]);
  await actor(ids.owner);await reps(b,week,today);
 },'FIELD_SESSION_REQUIRED');
 // A pending link is not an employee link; revoking the accepted one unlinks.
 await db.exec('reset role');
 await db.query("insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by) values($1,$2,$3,$4,$5,$6,$7,'pending',$8)",
  [ids.link3,t,e,b,ids.employee2,ids.m2,ids.rep2,ids.owner]);
 await db.query("update people_private.account_links set status='revoked' where id=$1",[ids.link]);
 await actor(ids.owner);
 const relabelled=Object.fromEntries((await reps(b,week,today)).items.map(x=>[x.user_id,x]));
 check('a pending link does not name the rep',relabelled[ids.rep2].label==='Unlinked member ····'+ids.rep2.slice(-4));
 check('the label follows the HR link: a revoked link unlinks the rep',relabelled[ids.rep].label==='Unlinked member ····'+ids.rep.slice(-4)&&relabelled[ids.rep].linked===false);
 check('the rep link is derived; Field Sales stores no second link',
  await scalar("select not exists(select 1 from information_schema.columns where table_schema='field_sales' and column_name in('employee_id','display_name','label'))"));
}
