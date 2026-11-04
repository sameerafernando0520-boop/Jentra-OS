import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

export async function exercise(db,checks){
 await db.exec('reset role');
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const check=(name,result)=>{assert.ok(result,name);checks.push(name);};
 const reject=async(name,code,work,message)=>{
  await db.exec('savepoint denial');let error;try{await work();}catch(e){error=e;}
  await db.exec('rollback to savepoint denial;release savepoint denial');
  assert.equal(error?.code,code,name+': '+(error?.message??'allowed'));
  if(message)assert.equal(error.message,message,name);
  checks.push(name);
 };
 const scenario=async(work)=>{await db.exec('savepoint scenario');try{await work();}finally{await db.exec('rollback to savepoint scenario;release savepoint scenario');}};
 await db.query("select set_config('request.jwt.claims','{}',true)");
 check('missing request method never permits public customer actions',await value('select field_sales.confirmation_public_request()')===false);
 const anonFunctions=(await db.query("select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and has_function_privilege('anon',p.oid,'execute') order by p.proname")).rows.map(r=>r.proname);
 assert.deepEqual(anonFunctions,['field_sales_confirmation_request_code','field_sales_confirmation_respond','field_sales_confirmation_verify']);
 checks.push('anonymous API schema access exposes only the three reviewed recipient facades');
 await db.query("select set_config('request.method','POST',true)");
 const ids=Object.fromEntries(['owner','rep','other','session','repSession','membership','role','customer','unit','product','warehouse','assignment','policy','request','contact'].map(k=>[k,randomUUID()]));
 const actor=async(user,aal='aal2')=>{
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:user,aal,session_id:user===ids.owner?ids.session:ids.repSession})]);
  await db.exec('set local role authenticated');
 };
 for(const user of [ids.owner,ids.rep,ids.other])await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[user,user+'@confirmation.invalid']);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4)',[ids.session,ids.owner,ids.repSession,ids.rep]);
 await actor(ids.owner);
 const scope=await value("select api.bootstrap_tenant('Confirmation Sales','confirmation-sales','Confirmation Company','CC','Main','MAIN','Asia/Colombo','LKR',$1)",[randomUUID()]);
 const t=scope.tenant_id,e=scope.legal_entity_id,b=scope.branch_id;
 await db.exec('reset role');
 await db.query("insert into core.memberships(id,tenant_id,user_id,status) values($1,$2,$3,'active')",[ids.membership,t,ids.rep]);
 await db.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values($1,$2,'confirmation_rep','Sales representative',false)",[ids.role,t]);
 await db.query('insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,$2,code from core.permissions',[t,ids.role]);
 await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values($1,$2,$3,$4,$5,$6)',[t,ids.membership,ids.role,e,b,ids.owner]);
 await db.query('insert into field_sales.principals values($1,$2)',[t,ids.rep]);
 await db.query("insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by) values($1,$2,'EMAIL-C','Email Customer','Email Customer','customer',100000,$3,$3)",[ids.customer,t,ids.owner]);
 await db.query("insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by) values($1,$2,'EA','Each','ea','quantity',3,$3,$3)",[ids.unit,t,ids.owner]);
 await db.query("insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,created_by,updated_by) values($1,$2,$3,'EMAIL-P','Confirmation Product','non_stocked',$4,$5,$5)",[ids.product,t,e,ids.unit,ids.owner]);
 await db.query("insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,code,name,created_by) values($1,$2,$3,$4,'EMAIL-WH','Main Warehouse',$5)",[ids.warehouse,t,e,b,ids.owner]);
 await db.query(`insert into field_sales.assignments(id,tenant_id,legal_entity_id,branch_id,rep_id,customer_id,valid_from,valid_until,ship_to,payment_terms_days,delivery_terms)
  values($1,$2,$3,$4,$5,$6,now()-interval '1 day',now()+interval '7 days','{"address":"Approved customer address"}',30,'Company delivery')`,[ids.assignment,t,e,b,ids.rep,ids.customer]);
 await db.query(`insert into field_sales.price_policies(id,tenant_id,legal_entity_id,branch_id,customer_id,product_id,unit_id,currency_code,unit_price,max_discount_percent,valid_from,valid_until)
  values($1,$2,$3,$4,$5,$6,$7,'LKR',1.25,10,current_date-1,current_date+7)`,[ids.policy,t,e,b,ids.customer,ids.product,ids.unit]);
 await db.query("insert into sales.customer_credit_exposures(tenant_id,legal_entity_id,branch_id,customer_id,currency_code,as_of_at,created_by,updated_by) values($1,$2,$3,$4,'LKR',now(),$5,$5)",[t,e,b,ids.customer,ids.owner]);
 await actor(ids.rep);
 const input={customer_id:ids.customer,warehouse_id:ids.warehouse,requested_date:new Date(Date.now()+86400000).toISOString().slice(0,10),discount_percent:'10',discount_reason:'Independent review',reference:'EMAIL-SYNTHETIC',notes:'',lines:[{policy_id:ids.policy,policy_version:'1',quantity:'1.125'}]};
 const preview=await value('select api.field_sales_preview($1,$2,$3,$4)',[t,e,b,input]);
 await value('select api.field_sales_command($1,$2,$3,$4,$5,now(),$6,null)',[t,e,b,randomUUID(),randomUUID(),{id:ids.request,input,source_digest:preview.source_digest}]);
 await actor(ids.owner);
 await value('select api.field_sales_company_decide($1,$2,$3,$4,$5,now(),$6,1)',[t,e,b,randomUUID(),randomUUID(),{id:ids.request,decision:'approve',reason:'Company-approved terms',source_digest:preview.source_digest}]);
 const command=async(action,payload,expected=null,commandId=randomUUID(),key=randomUUID())=>value('select api.field_sales_confirmation_command($1,$2,$3,$4,$5,now(),$6,$7,$8)',[t,e,b,commandId,key,action,payload,expected]);
 const contact=await command('authorize_contact',{id:ids.contact,customer_id:ids.customer,name:'Authorized buyer',email:'Buyer@Example.invalid',authority_note:'Company reviewed commercial contact',valid_until:new Date(Date.now()+3*86400000).toISOString()});
 check('MFA company authorizes a scoped contact without claiming verified identity',contact.entity.email==='buyer@example.invalid'&&contact.entity.version==='1'&&contact.entity.channel_state==='unverified');
 await reject('stale contact administration is refused','40001',()=>command('revoke_contact',{id:ids.contact},2));
 await actor(ids.owner,'aal1');
 await reject('contact authorization needs current company MFA','42501',()=>command('revoke_contact',{id:ids.contact},1));
 await actor(ids.rep);
 await reject('broadly granted field representative cannot authorize a customer contact','42501',()=>command('revoke_contact',{id:ids.contact},1));
 await reject('field representative cannot enumerate company contact addresses','42501',()=>value('select api.field_sales_confirmation_contacts($1,$2,$3,$4)',[t,e,b,ids.customer]));
 await reject('field representative cannot execute private confirmation data helpers','42501',()=>value('select field_sales.confirmation_offer(null::field_sales.confirmation_challenges)'));
 await db.exec('reset role;set local role anon');
 await reject('anonymous client cannot read raw contact rows','42501',()=>db.query('select * from field_sales.confirmation_contacts'));
 await actor(ids.owner);
 const listing=await value('select api.field_sales_confirmation_contacts($1,$2,$3,$4)',[t,e,b,ids.customer]);
 check('missing transport remains explicitly unavailable',listing.provider_state==='unavailable'&&listing.items.length===1);
 const issuePayload={id:randomUUID(),request_id:ids.request,contact_id:ids.contact,request_version:'2',source_digest:preview.source_digest};
 await reject('disabled transport creates no challenge or command receipt','55000',()=>command('issue_order',issuePayload), 'CONFIRMATION_PROVIDER_UNAVAILABLE');
 await db.exec('reset role');
 check('disabled provider leaves the challenge queue empty',await value('select count(*)=0 from field_sales.confirmation_challenges'));
 // Synthetic transport configuration is confined to the rolled-back transaction.
 await db.query('insert into field_sales.confirmation_transport(tenant_id,enabled) values($1,true)',[t]);
 await actor(ids.owner);
 const issueCommand=randomUUID(),issueKey=randomUUID();
 const issued=await command('issue_order',issuePayload,null,issueCommand,issueKey);
 check('company issue freezes source/contact revisions and exposes no bearer secret',issued.entity.state==='queued_link'&&issued.entity.request_version==='2'&&issued.entity.contact_version==='1'&&!JSON.stringify(issued).includes('token_hash'));
 const token='ab'.repeat(32),code='482619';
 const worker=async(step,secret)=>{
  await db.exec('reset role');await db.query("select set_config('request.jwt.claims','{}',true)");await db.exec('set local role service_role');
  return value('select field_sales.confirmation_dispatch($1,$2,$3)',[issuePayload.id,step,secret]);
 };
 const prepared=await worker('prepare_link',token);
 check('only the worker prepares the authorized email channel',prepared.recipient==='buyer@example.invalid'&&prepared.kind==='order_link');
 const anon=async()=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claims','{}',true)");await db.exec('set local role anon');};
 await anon();
 const requestCode=()=>value('select api.field_sales_confirmation_request_code($1)',[token]);
 check('prepared link is unavailable until the provider acknowledgement', (await requestCode()).state==='unavailable');
 await reject('provider acknowledgement cannot be fabricated by omitting its reference','55000',()=>worker('ack_link',token));
 await db.exec('reset role;set local role service_role');
 await value('select field_sales.confirmation_dispatch($1,$2,$3,$4)',[issuePayload.id,'ack_link',token,'synthetic-link-ack']);
 await reject('conflicting link acknowledgements cannot overwrite transport evidence','22023',()=>value('select field_sales.confirmation_dispatch($1,$2,$3,$4)',[issuePayload.id,'ack_link',token,'different-ack']),'DISPATCH_IMMUTABLE');
 await anon();
 const requested=await requestCode();
 check('explicit code request queues only the separately addressed verification step',requested.state==='check_email'&&!('offer' in requested)&&!('recipient' in requested));
 await worker('prepare_code',code);
 await anon();
 const verify=()=>value('select api.field_sales_confirmation_verify($1,$2)',[token,code]);
 check('code preparation alone does not establish verified email access',(await verify()).state==='unavailable');
 await db.exec('reset role;set local role service_role');
 await value('select field_sales.confirmation_dispatch($1,$2,$3,$4)',[issuePayload.id,'ack_code',code,'synthetic-code-ack']);
 await reject('conflicting code acknowledgements cannot overwrite transport evidence','22023',()=>value('select field_sales.confirmation_dispatch($1,$2,$3,$4)',[issuePayload.id,'ack_code',code,'different-ack']),'DISPATCH_IMMUTABLE');
 await anon();
 await scenario(async()=>{
  for(let i=0;i<5;i++)await value('select api.field_sales_confirmation_verify($1,$2)',[token,'000000']);
  check('five failed code attempts close the challenge even for a later correct code',(await value('select api.field_sales_confirmation_verify($1,$2)',[token,code])).state==='unavailable');
 });
 const verified=await verify();
 assert.equal(verified.state,'review');
 assert.equal(verified.offer.totals.grand_total,'1.270000');
 assert.equal(verified.offer.lines[0].quantity,'1.125000');
 check('separate email code opens the exact frozen offer without accepting it',typeof verified.proof==='string');
 const respond=(response='accept',authorized=true)=>value('select api.field_sales_confirmation_respond($1,$2,$3,$4,$5)',[token,verified.proof,response,'',authorized]);
 await actor(ids.rep);await db.exec('reset role;set local role anon');
 check('a staff JWT cannot act as a verified recipient even under anonymous role',(await respond()).state==='unavailable');
 await anon();
 await scenario(async()=>{
  await actor(ids.owner);await command('revoke_challenge',{id:issuePayload.id,reason:'Company revoked the response request'},1);await anon();
  check('company revocation immediately denies a previously verified response',(await respond()).state==='unavailable');
 });
 await scenario(async()=>{
  await actor(ids.owner);await command('revoke_contact',{id:ids.contact},1);await anon();
  check('contact revocation immediately denies a previously verified response',(await respond()).state==='unavailable');
 });
 await scenario(async()=>{
  await db.exec('reset role');await db.query("update field_sales.confirmation_challenges set issued_at=clock_timestamp()-interval '16 minutes',expires_at=clock_timestamp()-interval '1 minute' where id=$1",[issuePayload.id]);await anon();
  check('expired link cannot record customer acceptance',(await respond()).state==='unavailable');
 });
 await scenario(async()=>{
  await db.exec('reset role');await db.query('update field_sales.price_policies set unit_price=2,version=2 where id=$1',[ids.policy]);await anon();
  check('commercial source change invalidates even the verified challenge',(await respond()).state==='unavailable');
 });
 await scenario(async()=>{
  await db.exec('reset role');await db.query("update inventory.units set symbol='new unit label' where id=$1",[ids.unit]);await anon();
  check('changed displayed unit terms cannot reuse an earlier review proof',(await respond()).state==='unavailable');
  const newReview=await verify();
  check('a refreshed display receives a distinct review-bound proof',newReview.state==='review'&&newReview.proof!==verified.proof);
  check('old review proof cannot accept the refreshed display',(await respond()).state==='unavailable');
 });
 await scenario(async()=>{
  await db.exec('reset role');await db.query("update field_sales.assignments set valid_until=clock_timestamp() where id=$1",[ids.assignment]);await anon();
  check('assignment revocation invalidates the outstanding challenge',(await respond()).state==='unavailable');
 });
 await db.query("select set_config('request.method','GET',true)");
 check('GET or link scanning cannot record a response',(await respond()).state==='unavailable');
 await db.query("select set_config('request.method','POST',true)");
 check('email access does not substitute the explicit authority declaration',(await respond('accept',false)).state==='unavailable');
 const accepted=await respond();
 check('explicit verified acceptance records a separate revision-bound response',accepted.state==='recorded'&&accepted.response==='accepted'&&accepted.method==='email_link_and_code');
 assert.deepEqual(await respond(),accepted);checks.push('exact response retry returns its original evidence without a second acceptance');
 check('a consumed challenge cannot silently replace acceptance with rejection',(await respond('reject')).state==='conflict');
 for(let i=0;i<6;i++){
  await value('select api.field_sales_confirmation_verify($1,$2)',[token,'000000']);
  await value('select api.field_sales_confirmation_respond($1,$2,$3,$4,true)',[token,'00'.repeat(32),'accept','']);
 }
 assert.deepEqual(await respond(),accepted);checks.push('bad code or proof guesses cannot revoke a completed customer response');
 await actor(ids.rep);
 const subjects=await value('select api.field_sales_subject_page($1,$2,$3)',[t,e,b]);
 check('Sales history exposes independent company, customer and delivery states',subjects.items[0].company_state==='approved'&&subjects.items[0].customer_state==='accepted'&&subjects.items[0].delivery_state==='not_requested'&&!JSON.stringify(subjects).includes('buyer@example.invalid'));
 await db.exec('reset role');
 check('verification stores hashes rather than link/code/proof secrets',!(await value('select to_jsonb(c)::text from field_sales.confirmation_challenges c where id=$1',[issuePayload.id])).includes(token)&&!(await value('select to_jsonb(c)::text from field_sales.confirmation_challenges c where id=$1',[issuePayload.id])).includes(code));
 check('customer acceptance creates one evidence row and leaves the canonical draft unchanged',await value("select (select count(*)=1 from field_sales.order_responses) and (select status='draft' from sales.sales_orders where id=(select canonical_order_id from field_sales.order_requests where id=$1))",[ids.request]));
 await reject('even verified acceptance cannot bypass the separate company progression gate','55000',()=>db.query('update sales.sales_orders set notes=notes where id=(select canonical_order_id from field_sales.order_requests where id=$1)',[ids.request]),'COMPANY_PROGRESSION_UNAVAILABLE');
 await anon();
 await reject('anonymous client cannot read canonical company orders','42501',()=>db.query('select * from sales.sales_orders'));
 await reject('anonymous client cannot read response evidence snapshots','42501',()=>db.query('select * from field_sales.order_responses'));
 await actor(ids.owner);
 await reject('contact selector enforces its maximum page size','22023',()=>value('select api.field_sales_confirmation_contacts($1,$2,$3,$4,null,201)',[t,e,b,ids.customer]));
 await scenario(async()=>{
  await db.exec('reset role');await db.query('update field_sales.price_policies set unit_price=2,version=2 where id=$1',[ids.policy]);await actor(ids.owner);
  const recovered=await value('select api.field_sales_confirmation_receipt($1,$2,$3,$4)',[t,e,b,issueKey]);
  check('company can recover the original issue receipt after a later source revision',recovered.state==='committed'&&recovered.receipt.command_id===issueCommand&&recovered.receipt.entity.id===issuePayload.id);
 });
 await scenario(async()=>{
  for(let i=0;i<4;i++)await command('issue_order',{...issuePayload,id:randomUUID()});
  await reject('recipient issue rate is bounded across superseded challenges','54000',()=>command('issue_order',{...issuePayload,id:randomUUID()}),'CONFIRMATION_RATE_LIMITED');
 });
}
