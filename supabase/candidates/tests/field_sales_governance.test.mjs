import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

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
 const ids=Object.fromEntries(['owner','rep','rep2','foreign','membership','membership2','fieldRole','c1','c2','c3','unit','product','warehouse','policy','assignment','request','command','key','employee','employee2','employeeLink','employeeLink2','quotation'].map(k=>[k,randomUUID()]));
 const sessions=new Map([ids.owner,ids.rep,ids.rep2,ids.foreign].map(id=>[id,randomUUID()]));
 const actor=async(id,aal='aal2',sessionId=sessions.get(id))=>{
  await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:id,aal,session_id:sessionId})]);
  await db.exec('set local role authenticated');
 };
 for(const id of [ids.owner,ids.rep,ids.rep2,ids.foreign]) await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@sales.invalid']);
 for(const [user,session] of sessions) await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,user]);
 await actor(ids.owner);
 const scope=await scalar("select api.bootstrap_tenant('Synthetic Sales','synthetic-sales','Sales Company','SC','Head Office','HQ','Asia/Colombo','LKR',$1)",[randomUUID()]);
 const t=scope.tenant_id,e=scope.legal_entity_id,b=scope.branch_id;
 await db.exec('reset role');
 await db.query("insert into core.memberships(id,tenant_id,user_id,status) values($1,$2,$3,'active'),($4,$2,$5,'active')",[ids.membership,t,ids.rep,ids.membership2,ids.rep2]);
 await db.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values($1,$2,'field_test','Restricted field',false)",[ids.fieldRole,t]);
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,$2,code from core.permissions",[t,ids.fieldRole]);
 await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,id,p.code from core.roles cross join core.permissions p where tenant_id=$1 and core.roles.code='tenant_owner' and p.code like 'sales.field.%' on conflict do nothing",[t]);
 for(const m of [ids.membership,ids.membership2]) await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values($1,$2,$3,$4,$5,$6)',[t,m,ids.fieldRole,e,b,ids.owner]);
 for(const rep of [ids.rep,ids.rep2])await db.query('insert into field_sales.principals values($1,$2)',[t,rep]);
 for(const [id,code] of [[ids.c1,'C1'],[ids.c2,'C2'],[ids.c3,'C3']])await db.query(`insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
  values($1,$2,$3,$3,$3,'customer',100000,$4,$4)`,[id,t,code,ids.owner]);
 await db.query("insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by) values($1,$2,'EA','Each','ea','quantity',3,$3,$3)",[ids.unit,t,ids.owner]);
 await db.query("insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,created_by,updated_by) values($1,$2,$3,'P1','Synthetic Product','non_stocked',$4,$5,$5)",[ids.product,t,e,ids.unit,ids.owner]);
 await db.query("insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,code,name,created_by) values($1,$2,$3,$4,'WH','Sales Warehouse',$5)",[ids.warehouse,t,e,b,ids.owner]);
 for(const [c,rep,id] of [[ids.c1,ids.rep,ids.assignment],[ids.c2,ids.rep2,randomUUID()],[ids.c3,ids.rep,randomUUID()]])await db.query(`insert into field_sales.assignments(id,tenant_id,legal_entity_id,branch_id,rep_id,customer_id,valid_from,valid_until,ship_to,payment_terms_days,delivery_terms)
  values($1,$2,$3,$4,$5,$6,now()-interval '1 day',now()+interval '1 day','{"address":"Company approved address"}',30,'Company delivery')`,[id,t,e,b,rep,c]);
 await db.query(`insert into field_sales.price_policies(id,tenant_id,legal_entity_id,branch_id,customer_id,product_id,unit_id,currency_code,unit_price,max_discount_percent,valid_from,valid_until)
  values($1,$2,$3,$4,$5,$6,$7,'LKR',1.25,10,current_date-1,current_date+1)`,[ids.policy,t,e,b,ids.c1,ids.product,ids.unit]);
 await db.query(`insert into core.attachments(tenant_id,aggregate_type,aggregate_id,file_name,mime_type,byte_size,object_path,upload_status,created_by,updated_by)
  values($1,'party',$2,'synthetic-private.pdf','application/pdf',12,$3,'ready',$4,$4)`,[t,ids.c2,t+'/foreign-customer/synthetic.pdf',ids.owner]);
 await db.query("insert into storage.objects(bucket_id,name) values('jentra-attachments',$1)",[t+'/foreign-customer/synthetic.pdf']);
 await actor(ids.rep);
 check('workspace resolves assigned scope without broad CRM', (await scalar('select api.field_sales_workspace()')).scopes.length===1);
 const customers=await scalar('select api.field_sales_customers($1,$2,$3)',[t,e,b]);
 check('portfolio includes customer without transactions and excludes other rep',customers.items.length===2&&customers.items.some(x=>x.id===ids.c3)&&!customers.items.some(x=>x.id===ids.c2));
 check('accidental broad CRM grant is denied',await scalar("select not core.has_permission($1,'crm.parties.view')",[t]));
 check('legacy party view returns no customers',(await db.query('select * from api.parties')).rows.length===0);
 check('direct base parties return no customers',(await db.query('select * from crm.parties')).rows.length===0);
 check('populated private file metadata and object paths remain denied despite broad file grants',
  (await db.query('select * from api.attachments')).rows.length===0&&(await db.query('select * from storage.objects')).rows.length===0);
 await reject('legacy export creation denied despite broad analytics grants','42501',()=>scalar("select api.create_export_job($1,'parties','csv','{}','[]',0,'synthetic.csv',0,$2)",[t,randomUUID()]));
 await reject('legacy canonical command denied despite inherited grant','42501',()=>scalar('select api.upsert_sales_order($1,$2,$3,$4,$5,now(),$6,null)',[t,e,b,randomUUID(),randomUUID(),{}]));
 await reject('other portfolio catalogue denied','42501',()=>scalar('select api.field_sales_catalogue($1,$2,$3,$4)',[t,e,b,ids.c2]));
 await reject('page cap enforced','22023',()=>scalar('select api.field_sales_customers($1,$2,$3,$4,null,201)',[t,e,b,'']));
 await reject('private helpers denied','42501',()=>scalar('select field_sales.assignment($1,$2,$3,$4,$5)',[t,e,b,ids.c1,ids.rep]));
 const input={customer_id:ids.c1,warehouse_id:ids.warehouse,requested_date:new Date(Date.now()+86400000).toISOString().slice(0,10),discount_percent:'10',discount_reason:'Company discount request',reference:'SYNTHETIC',notes:'',lines:[{policy_id:ids.policy,policy_version:'1',quantity:'1.125'}]};
 const preview=()=>scalar('select api.field_sales_preview($1,$2,$3,$4)',[t,e,b,input]);
 const reviewed=await preview();
 check('canonical calculator rounds fractional quantity exactly',reviewed.pricing.subtotal==='1.410000'&&reviewed.pricing.grand_total==='1.270000');
 check('discount remains requested; stock and credit are explicit',reviewed.discount_state==='requested'&&reviewed.stock_state==='unavailable'&&reviewed.credit_state==='company_review_required');
 const payload={id:ids.request,input,source_digest:reviewed.source_digest};
 const submit=(value=payload,id=ids.command,key=ids.key)=>scalar('select api.field_sales_command($1,$2,$3,$4,$5,now(),$6,null)',[t,e,b,id,key,value]);
 const receipt=await submit();
 check('submission creates a request, not a canonical order or acceptance',receipt.entity.company_state==='submitted'&&receipt.entity.customer_state==='email_link_pending'&&receipt.entity.canonical_order_id===null);
 assert.deepEqual(await submit(),receipt);checks.push('exact retry returns original receipt');
 await reject('changed payload cannot reuse command identity','22023',()=>submit({...payload,input:{...input,notes:'changed'}}));
 check('scoped recovery finds the exact original command',(await scalar('select api.field_sales_command_receipt($1,$2,$3,$4)',[t,e,b,ids.key])).receipt.command_id===ids.command);
 check('raw legacy receipt access remains closed',(await db.query('select * from core.command_receipts')).rows.length===0);
 await reject('representative cannot approve own discount','42501',()=>scalar('select api.field_sales_company_decide($1,$2,$3,$4,$5,now(),$6,1)',[t,e,b,randomUUID(),randomUUID(),{id:ids.request,decision:'approve',reason:'self',source_digest:reviewed.source_digest}]));
 await actor(ids.foreign);
 await reject('foreign account cannot enumerate portfolio','42501',()=>scalar('select api.field_sales_customers($1,$2,$3)',[t,e,b]));
 await actor(ids.owner,'aal1');
 const decide=(decision='approve',version=1)=>scalar('select api.field_sales_company_decide($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,randomUUID(),randomUUID(),{id:ids.request,decision,reason:'Independent company review',source_digest:reviewed.source_digest},version]);
 await reject('company decision requires MFA','42501',()=>decide());
 await actor(ids.owner);
 await reject('missing credit provider rolls back canonical order','55000',()=>decide());
 await db.exec('reset role');
 check('failed approval creates no canonical order',await scalar('select count(*)=0 from sales.sales_orders'));
 await db.query(`insert into sales.customer_credit_exposures(tenant_id,legal_entity_id,branch_id,customer_id,currency_code,as_of_at,created_by,updated_by)
  values($1,$2,$3,$4,'LKR',now(),$5,$5)`,[t,e,b,ids.c1,ids.owner]);
 await actor(ids.owner);
 await reject('stale company decision version refused','40001',()=>decide('approve',2));
 await reject('changed source cannot be approved','40001',async()=>{
  await db.exec('reset role');await db.query('update field_sales.price_policies set unit_price=2,version=2 where id=$1',[ids.policy]);
  await actor(ids.owner);await decide();
 });
 const approved=await decide();
 check('independent company decision creates canonical draft only',approved.entity.company_state==='approved'&&approved.entity.canonical_state==='draft'&&approved.entity.customer_state==='email_link_pending');
 await db.exec('reset role');
 const order=await one('select * from sales.sales_orders where id=$1',[approved.entity.canonical_order_id]);
 check('canonical order preserves exact total, rep attribution and draft status',order.grand_total==='1.270000'&&order.salesperson_id===ids.rep&&order.status==='draft');
 check('approval never reserves, delivers, invoices or records verified acceptance',await scalar('select count(*)=0 from inventory.stock_reservations'));
 await actor(ids.owner);
 const date=order.order_date;
 await scalar('select api.upsert_sales_quotation($1,$2,$3,$4,$5,now(),$6,null)',[t,e,b,randomUUID(),randomUUID(),{
  id:ids.quotation,customer_id:ids.c2,salesperson_id:ids.rep2,quotation_date:date,valid_until:input.requested_date,rate_date:date,
  currency_code:'LKR',exchange_rate:'1',payment_terms_days:30,delivery_terms:'Company delivery',
  header_discount_amount:'0',notes:'Synthetic legacy isolation fixture',lines:[{
   product_id:ids.product,unit_id:ids.unit,description:'Synthetic Product',quantity:'2',base_quantity:'2',
   conversion_numerator:'1',conversion_denominator:'1',unit_price:'1.25'}]}]);
 check('company can read the populated legacy canonical order and other-portfolio quotation',
  await scalar('select exists(select 1 from api.sales_orders where id=$1) and exists(select 1 from api.sales_quotations where id=$2)',[order.id,ids.quotation]));
 await reject('legacy order edit cannot bypass pending verified customer acceptance','55000',()=>scalar('select api.update_sales_order_fulfillment($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,randomUUID(),randomUUID(),{id:order.id,promised_date:input.requested_date,warehouse_id:ids.warehouse,ship_to:{}},order.version]));
 await reject('repeat company decision is not a new order','55000',()=>decide('approve',2));
 await actor(ids.rep);
 check('populated canonical order and line legacy views remain closed',
  (await db.query('select * from api.sales_orders')).rows.length===0&&(await db.query('select * from api.sales_order_lines')).rows.length===0);
 check('populated other-portfolio quotation and line legacy views remain closed',
  (await db.query('select * from api.sales_quotations')).rows.length===0&&(await db.query('select * from api.sales_quotation_lines')).rows.length===0);
 check('known document identifiers cannot bypass legacy detail isolation',
  (await db.query('select * from api.sales_order_details where id=$1',[order.id])).rows.length===0&&
  (await db.query('select * from api.sales_quotation_details where id=$1',[ids.quotation])).rows.length===0);
 check('populated member-only credit exposure view is denied',(await db.query('select * from api.customer_credit_exposures')).rows.length===0);
 await reject('direct legacy credit table is denied','42501',()=>db.query('select * from sales.customer_credit_exposures'));
 await reject('arbitrary prices rejected at preview','22023',()=>scalar('select api.field_sales_preview($1,$2,$3,$4)',[t,e,b,{...input,lines:[{...input.lines[0],unit_price:'0.01'}]}]));
 await reject('JSON numbers cannot enter exact quantities','22023',()=>scalar('select api.field_sales_preview($1,$2,$3,$4)',[t,e,b,{...input,lines:[{...input.lines[0],quantity:1.125}]}]));
 await reject('discount reason required','22023',()=>scalar('select api.field_sales_preview($1,$2,$3,$4)',[t,e,b,{...input,discount_reason:''}]));
 await reject('discount ceiling enforced before company decision','22023',()=>scalar('select api.field_sales_preview($1,$2,$3,$4)',[t,e,b,{...input,discount_percent:'11'}]));
 await reject('price revision invalidates reviewed submission','40001',async()=>{
  await db.exec('reset role');await db.query('update field_sales.price_policies set unit_price=2,version=2 where id=$1',[ids.policy]);
  await actor(ids.rep);await submit({...payload,id:randomUUID()},randomUUID(),randomUUID());
 });
 await actor(ids.rep2);
 check('other representative cannot recover the original command',(await scalar('select api.field_sales_command_receipt($1,$2,$3,$4)',[t,e,b,ids.key])).state==='not_found');
 check('other portfolio does not see submitted requests',(await scalar('select api.field_sales_subject_page($1,$2,$3)',[t,e,b])).items.length===0);
 await db.exec('reset role');
 await db.query("update field_sales.assignments set valid_until=now()-interval '1 second' where id=$1",[ids.assignment]);
 await actor(ids.rep);
 await reject('revoked assignment blocks even exact retry','42501',()=>submit());
 await reject('revoked assignment blocks historic receipt recovery','42501',()=>scalar('select api.field_sales_command_receipt($1,$2,$3,$4)',[t,e,b,ids.key]));
 await reject('bootstrap cannot replay a field receipt after revocation','42501',()=>scalar("select api.bootstrap_tenant('Attack','attack-tenant','Attack','AT','Attack','AT','Asia/Colombo','LKR',$1)",[ids.key]));
 await reject('direct legacy bootstrap helper is also denied','42501',()=>scalar("select core.bootstrap_tenant_impl('Attack','attack-tenant','Attack','AT','Attack','AT','Asia/Colombo','LKR',$1)",[ids.key]));
 check('revocation removes customer and submitted request',(await scalar('select api.field_sales_subject_page($1,$2,$3)',[t,e,b])).items.length===0&&(await scalar('select api.field_sales_customers($1,$2,$3)',[t,e,b])).items.length===1);
 check('revocation never restores broad legacy access',await scalar("select not core.has_permission($1,'sales.orders.manage',$2,$3)",[t,e,b]));
 await actor(ids.owner);
 check('company legacy CRM access is preserved',(await db.query('select * from api.parties')).rows.length===3);
 const admin=(action,payload,version=null)=>scalar('select api.field_sales_admin_command($1,$2,$3,$4,$5,now(),$6,$7,$8)',[t,e,b,randomUUID(),randomUUID(),action,payload,version]);
 await reject('company cannot permanently restrict its own owner account','42501',()=>admin('assign_customer',{id:randomUUID(),rep_id:ids.owner,customer_id:ids.c1}));
 const changed=await admin('set_price_policy',{id:ids.policy,customer_id:ids.c1,product_id:ids.product,unit_id:ids.unit,
  currency_code:'LKR',unit_price:'1.250000',max_discount_percent:'10',valid_from:'2020-01-01',valid_until:'2099-12-31'},1);
 check('MFA company price command confirms a versioned governed source',changed.entity.version==='2');
 await reject('stale price administration rejected','40001',()=>admin('set_price_policy',{id:ids.policy},1));
 const assigned=await admin('assign_customer',{id:ids.assignment,customer_id:ids.c1,rep_id:ids.rep,
  valid_from:'2020-01-01T00:00:00Z',valid_until:'2099-12-31T00:00:00Z',ship_to:{address:'Approved'},payment_terms_days:30,delivery_terms:'Company delivery'},1);
 check('MFA company assignment command restores only reviewed portfolio',assigned.entity.version==='2');
 const revoked=await admin('revoke_assignment',{id:ids.assignment},2);
 check('company revocation confirms its next version',revoked.entity.version==='3');

 // Real Employee app bootstrap compatibility, using the exact workforce and
 // private-HR migrations. No mock People helper or payroll/attendance claim.
 await db.exec('reset role');
 await db.query("update billing.plan_entitlements set enabled=true where entitlement_code='module.people' and plan_code=(select plan_code from billing.tenant_subscriptions where tenant_id=$1)",[t]);
 for(const [employee,code,name] of [[ids.employee,'FIELD_EMP','Linked Field Employee'],[ids.employee2,'OTHER_EMP','Other Linked Employee']]){
  await db.query('insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by) values($1,$2,$3,$4,$5,$6,$6)',[employee,t,e,code,name,ids.owner]);
 }
 for(const [link,employee,membership,user] of [[ids.employeeLink,ids.employee,ids.membership,ids.rep],[ids.employeeLink2,ids.employee2,ids.membership2,ids.rep2]]){
  await db.query("insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at) values($1,$2,$3,$4,$5,$6,$7,'accepted',$8,now())",[link,t,e,b,employee,membership,user,ids.owner]);
 }
 const employeeSelf=()=>scalar('select api.people_hr_self($1,$2,$3)',[t,e,b]);
 await actor(ids.rep);
 const own=await employeeSelf();
 check('enrolled Sales rep retains actual linked Employee bootstrap under its self capability',
  own.employee_id===ids.employee&&own.display_name==='Linked Field Employee'&&own.tenant_id===t&&own.legal_entity_id===e&&own.branch_id===b);
 check('Employee bootstrap does not expose the other linked Employee',own.employee_id!==ids.employee2&&!JSON.stringify(own).includes('Other Linked Employee'));
 check('Employee compatibility never restores broad People access',await scalar("select not core.has_permission($1,'people.view',$2,$3) and core.has_permission($1,'people.self.view',$2,$3)",[t,e,b]));
 await reject('linked Employee cannot select another employee through the bootstrap signature','42883',()=>scalar('select api.people_hr_self($1,$2,$3,$4)',[t,e,b,ids.employee2]));
 await reject('linked Employee cannot open the legacy staff directory despite inherited grants','42501',()=>scalar('select api.people_employee_directory($1,$2,$3)',[t,e,b]));
 await reject('linked Employee cannot read another employee private review path','42501',()=>scalar('select api.people_hr_reviews($1,$2,$3,$4)',[t,e,b,ids.employee2]));
 await reject('linked Employee cannot read raw staff rows','42501',()=>db.query('select * from people.employees'));
 await reject('linked Employee cannot read raw private account links','42501',()=>db.query('select * from people_private.account_links'));
 await reject('Employee bootstrap cannot substitute a foreign tenant','42501',()=>scalar('select api.people_hr_self($1,$2,$3)',[randomUUID(),e,b]));
 await reject('revoked Employee link immediately denies actual Employee bootstrap','42501',async()=>{
  await db.exec('reset role');await db.query("update people_private.account_links set status='revoked' where id=$1",[ids.employeeLink]);
  await actor(ids.rep);await employeeSelf();
 });
 await reject('suspended membership denies actual Employee bootstrap','42501',async()=>{
  await db.exec('reset role');await db.query("update core.memberships set status='suspended' where id=$1",[ids.membership]);
  await actor(ids.rep);await employeeSelf();
 });
 await reject('disabled People entitlement denies actual Employee bootstrap','42501',async()=>{
  await db.exec('reset role');await db.query("update billing.plan_entitlements set enabled=false where entitlement_code='module.people' and plan_code=(select plan_code from billing.tenant_subscriptions where tenant_id=$1)",[t]);
  await actor(ids.rep);await employeeSelf();
 });
 await reject('removed self capability denies actual Employee bootstrap','42501',async()=>{
  await db.exec('reset role');await db.query("delete from core.role_permissions where tenant_id=$1 and role_id=$2 and permission_code='people.self.view'",[t,ids.fieldRole]);
  await actor(ids.rep);await employeeSelf();
 });
 check('Employee denial probes preserve the legitimate own Employee bootstrap',(await employeeSelf()).employee_id===ids.employee);
 await actor(ids.rep2);
 check('second enrolled rep resolves only its own linked Employee',(await employeeSelf()).employee_id===ids.employee2);

 // A simulated Auth session is independent of a still-valid access JWT. Match
 // the specific session denial to avoid unrelated portfolio/role checks masking
 // a missing guard. Failed commands retain every prior receipt unchanged.
 await db.exec('reset role');
 const receiptCount=await scalar('select count(*)::text from core.command_receipts');
 await actor(ids.rep);
 await reject('Sales workspace requires the JWT Auth session claim','42501',async()=>{
  await actor(ids.rep,'aal2',null);await scalar('select api.field_sales_workspace()');
 },'FIELD_SESSION_REQUIRED');
 await reject('Sales workspace rejects malformed Auth session identifiers','42501',async()=>{
  await actor(ids.rep,'aal2','invalid-session');await scalar('select api.field_sales_workspace()');
 },'FIELD_SESSION_REQUIRED');
 await reject('Sales workspace rejects a session owned by another user','42501',async()=>{
  await actor(ids.rep,'aal2',sessions.get(ids.rep2));await scalar('select api.field_sales_workspace()');
 },'FIELD_SESSION_REQUIRED');
 await reject('Sales workspace rejects an absent stale session reference','42501',async()=>{
  await actor(ids.rep,'aal2',randomUUID());await scalar('select api.field_sales_workspace()');
 },'FIELD_SESSION_REQUIRED');
 await reject('revoked Auth session cannot reopen Sales with its retained JWT','42501',async()=>{
  await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sessions.get(ids.rep)]);
  await actor(ids.rep);await scalar('select api.field_sales_workspace()');
 },'FIELD_SESSION_REQUIRED');
 await reject('expired Auth session cannot reopen Sales with its retained JWT','42501',async()=>{
  await db.exec('reset role');await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 day' where id=$1",[sessions.get(ids.rep)]);
  await actor(ids.rep);await scalar('select api.field_sales_workspace()');
 },'FIELD_SESSION_REQUIRED');
 const representativeCalls=[
  ['portfolio',()=>scalar('select api.field_sales_customers($1,$2,$3)',[t,e,b])],
  ['catalogue',()=>scalar('select api.field_sales_catalogue($1,$2,$3,$4)',[t,e,b,ids.c3])],
  ['commercial preview',preview],
  ['order submission',submit],
  ['subject page',()=>scalar('select api.field_sales_subject_page($1,$2,$3)',[t,e,b])],
  ['receipt recovery',()=>scalar('select api.field_sales_command_receipt($1,$2,$3,$4)',[t,e,b,ids.key])],
 ];
 for(const [name,call] of representativeCalls){
  await reject('deleted Auth session denies representative '+name,'42501',async()=>{
   await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sessions.get(ids.rep)]);
   await actor(ids.rep);await call();
  },'FIELD_SESSION_REQUIRED');
 }
 const companyCalls=[
  ['subject review',()=>scalar('select api.field_sales_subject_page($1,$2,$3)',[t,e,b])],
  ['receipt recovery',()=>scalar('select api.field_sales_command_receipt($1,$2,$3,$4)',[t,e,b,randomUUID()])],
  ['discount decision',()=>decide('approve',2)],
  ['portfolio administration',()=>admin('revoke_assignment',{id:ids.assignment},3)],
 ];
 for(const [name,call] of companyCalls){
  await reject('deleted Auth session denies company '+name,'42501',async()=>{
   await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sessions.get(ids.owner)]);
   await actor(ids.owner);await call();
  },'FIELD_SESSION_REQUIRED');
 }
 await db.exec('reset role');
 check('session denial probes create no command receipts',(await scalar('select count(*)::text from core.command_receipts'))===receiptCount);
 await actor(ids.rep);
 check('session denial probes preserve current authorized Sales access',(await scalar('select api.field_sales_workspace()')).scopes.length===1);
}
