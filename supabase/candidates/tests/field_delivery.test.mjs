import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {sendOne} from '../../../workers/field-sales/mail_worker.mjs';

export async function exercise(db,checks,ctx){
 const value=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
 const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);};
 const deny=async(name,code,work)=>{await db.exec('savepoint delivery_denial');let error;try{await work();}catch(e){error=e;}
  await db.exec('rollback to savepoint delivery_denial;release savepoint delivery_denial');assert.equal(error?.code,code,name+': '+error?.message);checks.push(name);};
 const {tenantId:t,entityId:e,branchId:b,ownerId:owner,repId:rep,orderId:oid}=ctx;
 await db.exec('reset role');
 const actor=async(user,aal='aal2')=>{await db.exec('reset role');const session=user?await value('select id from auth.sessions where user_id=$1',[user]):null;
  await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(user?{sub:user,aal,session_id:session}:{})]);await db.exec('set local role '+(user?'authenticated':'anon'));};
 const order=(await db.query('select * from sales.sales_orders where id=$1',[oid])).rows[0];
 const ol=(await db.query('select * from sales.sales_order_lines where sales_order_id=$1 order by id',[oid])).rows[0];
 const contact=(await db.query('update field_sales.confirmation_contacts set active=true where tenant_id=$1 returning *',[t])).rows[0];
 await db.query('update field_sales.mail_policies set enabled=true where tenant_id=$1',[t]);
 for(const type of ['delivery','journal_entry'])await db.query(`insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
  values($1,$2,$3,$4,$5,$6,$6) on conflict do nothing`,[t,e,b,type,'SYNTHETIC-'+type+'-',owner]);
 await db.query(`insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
  values($1,$2,$3,'Synthetic delivery period',current_date-1,current_date+30,$4,$4)`,[randomUUID(),t,e,owner]);
 const lifecycle={states:['draft','submitted','approved','rejected','posted','settled','fulfilled','closed','cancelled','reversed'],
  transitions:[['draft','submitted'],['submitted','approved'],['submitted','rejected'],['approved','posted'],['rejected','draft'],['draft','cancelled'],['submitted','cancelled']],
  posting_transitions:[['submitted','posted'],['submitted','draft'],['approved','draft']],requires_approval:false};
 await db.query(`insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
  values($1,$2,$3,'delivery','Synthetic delivery workflow','active',$4,$5,$5)`,[randomUUID(),t,e,lifecycle,owner]);
 await actor(owner);
 const did=randomUUID(),lineId=randomUUID(),today=new Date().toISOString().slice(0,10);
 const header={id:did,customer_id:order.customer_id,document_date:today,due_date:today,currency_code:order.currency_code,
  sales_order_id:oid,warehouse_id:order.warehouse_id,lines:[{line_id:lineId,sales_order_line_id:ol.id,base_quantity:'0.500000'}]};
 const draft=await value('select api.upsert_delivery($1,$2,$3,$4,$5,now(),$6,null)',[t,e,b,randomUUID(),randomUUID(),header]);
 const cmd=async(action,payload,version=null,key=randomUUID(),command=randomUUID())=>value('select api.field_sales_delivery_command($1,$2,$3,$4,$5,now(),$6,$7,$8)',[t,e,b,command,key,action,payload,version]);
 await deny('unposted deliveries cannot request recipient acknowledgement','55000',()=>cmd('issue_delivery',{id:randomUUID(),delivery_id:did}));
 const submitted=await value('select api.transition_operational_document($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,randomUUID(),randomUUID(),{document_type:'delivery',document_id:did,action:'submit'},draft.entity.version]);
 const postKey=randomUUID(),postCommand=randomUUID();
 const posted=await value('select api.post_delivery($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,postCommand,postKey,{document_id:did},submitted.entity.version]);
 check('company fulfillment posts through the canonical partial-delivery workflow',posted.entity.status==='posted');
 assert.deepEqual(await value('select api.post_delivery($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,postCommand,postKey,{document_id:did},submitted.entity.version]),posted);
 checks.push('partial-delivery posting retains the original canonical receipt on retry');
 const subjects=await value('select api.field_sales_delivery_subjects($1,$2,$3)',[t,e,b]);
 const subject=subjects.items.find(x=>x.id===did);
 check('company delivery subjects bind the posted version and exact base quantities',subject.delivery_version===posted.entity.version.toString()
  &&subject.offer.lines[0].posted_base_quantity==='0.500000'&&subject.delivery_state==='not_requested');
 const payload={id:randomUUID(),delivery_id:did,delivery_version:subject.delivery_version,delivery_digest:subject.delivery_digest,contact_id:contact.id,contact_version:contact.version.toString()};
 await actor(owner,'aal1');await deny('delivery issuance requires current company MFA','42501',()=>cmd('issue_delivery',payload));
 await actor(rep);await deny('representative cannot issue or enumerate company delivery acknowledgements','42501',()=>value('select api.field_sales_delivery_subjects($1,$2,$3)',[t,e,b]));
 await actor(owner);
 await deny('delivery contact revision must be the one explicitly reviewed','40001',()=>cmd('issue_delivery',{...payload,contact_version:'999'}));
 await deny('changed posted delivery digest cannot be issued','40001',()=>cmd('issue_delivery',{...payload,delivery_digest:'a'.repeat(64)}));
 const issueKey=randomUUID(),issueCommand=randomUUID();
 const issued=await cmd('issue_delivery',payload,null,issueKey,issueCommand);
 check('company delivery issuance queues a distinct challenge without acknowledging goods',issued.entity.state==='queued_link'&&issued.entity.delivery_id===did);
 assert.deepEqual(await cmd('issue_delivery',payload,null,issueKey,issueCommand),issued);checks.push('delivery issuance retries bind the exact original payload');
 await deny('same delivery command cannot replace its reviewed contact or digest','22023',()=>cmd('issue_delivery',{...payload,contact_version:'999'},null,issueKey,issueCommand));
 await db.exec('reset role;set local role service_role');
 const calls=[],rpc=async(name,p)=>name==='field_sales_mail_claim'
  ?value('select api.field_sales_mail_claim($1,$2)',[p.p_tenant_ids,p.p_lease_id])
  :value('select api.field_sales_mail_step($1,$2,$3,$4,$5,$6)',[p.p_tenant_id,p.p_job_id,p.p_lease_id,p.p_action,p.p_secret??null,p.p_provider_reference??null]);
 const fetchImpl=async(url,init)=>{calls.push([url,init]);return Response.json({id:randomUUID()});};
 const opts={tenantIds:[t],rpc,providerKeys:{platform:'private-test-provider'},secretKeys:{v1:'c'.repeat(64)},fetchImpl};
 await sendOne(opts);
 const message=JSON.parse(calls[0][1].body),token=message.text.match(/#delivery=([0-9a-f]{64})/)[1];
 check('delivery email uses a different fragment and idempotency purpose',calls[0][1].headers['Idempotency-Key'].includes('/delivery_link/')&&!message.text.includes('#confirm='));
 await actor(null);await db.query("select set_config('request.method','GET',true)");
 check('opening or scanning a delivery link cannot request a code',(await value('select api.field_sales_delivery_request_code($1)',[token])).state==='unavailable');
 await db.query("select set_config('request.method','POST',true)");
 check('delivery tokens cannot enter the order-response API',(await value('select api.field_sales_confirmation_request_code($1)',[token])).state==='unavailable');
 check('delivery response requires a separately delivered code',(await value('select api.field_sales_delivery_request_code($1)',[token])).state==='check_email');
 await db.exec('reset role;set local role service_role');await sendOne(opts);
 const code=JSON.parse(calls[1][1].body).text.match(/code: (\d{6})/)[1];
 await actor(null);
 const review=await value('select api.field_sales_delivery_verify($1,$2)',[token,code]);
 check('verified delivery review discloses exact posted quantities without prices',review.state==='review'&&review.offer.delivery_digest===subject.delivery_digest
  &&review.offer.lines[0].posted_base_quantity==='0.500000'&&!JSON.stringify(review.offer).includes('unit_price'));
 const quantities=[{id:lineId,received:'0.300000',refused:'0.100000',short:'0.100000'}];
 const respond=(q=quantities,proof=review.proof,authorized=true,reason='One part refused, one part short')=>value('select api.field_sales_delivery_respond($1,$2,$3,$4,$5)',[token,proof,q,reason,authorized]);
 check('a response proof cannot be substituted after the posted offer review',(await respond(quantities,'f'.repeat(64))).state==='unavailable');
 check('delivery declaration is required even after code verification',(await respond(quantities,review.proof,false)).state==='review_required');
 check('quantities cannot exceed or omit posted demand',(await respond([{...quantities[0],received:'0.500000'}])).state==='quantities_invalid');
 check('JSON numbers cannot replace exact quantity strings',(await respond([{...quantities[0],received:0.3}])).state==='quantities_invalid');
 check('a foreign or duplicate line cannot substitute a posted line',(await respond([{...quantities[0],id:randomUUID()}])).state==='quantities_invalid');
 check('duplicate posted lines cannot multiply acknowledged demand',(await respond([quantities[0],quantities[0]])).state==='quantities_invalid');
 check('refusal or shortage requires an explicit note',(await respond(quantities,review.proof,true,'')).state==='review_required');
 const result=await respond();
 assert.deepEqual(result.quantities,quantities);
 check('explicit received refused and short quantities are recorded as separate evidence',result.state==='recorded'&&result.response==='exception'
  &&result.method==='delivery_email_and_code'&&result.delivery_id===did);
 assert.deepEqual(await respond(),result);checks.push('uncertain delivery response recovers its exact original evidence');
 check('conflicting delivery quantities cannot replace recorded evidence',(await respond([{id:lineId,received:'0.500000',refused:'0',short:'0'}])).state==='already_recorded');
 await db.exec('reset role');
 const beforeFailures=await value('select failures from field_sales.delivery_challenges where id=$1',[payload.id]);
 await actor(null);await value('select api.field_sales_delivery_verify($1,$2)',[token,code==='000000'?'000001':'000000']);
 await db.exec('reset role');
 check('later bad guesses cannot revoke completed delivery evidence',await value('select failures from field_sales.delivery_challenges where id=$1',[payload.id])===beforeFailures);
 check('delivery evidence changes no posted stock quantities invoices or payment ledgers',await value('select delivered_quantity::text from sales.sales_order_lines where id=$1',[ol.id])==='0.500000'
  &&await value('select count(*)=0 from sales.sales_invoices')&&await value('select count(*)=0 from sales.customer_receipts'));
 check('all internal canonical progression permits were removed',await value('select count(*)=0 from field_sales.progression_permits'));
 await actor(owner);
 const updated=await value('select api.field_sales_confirmation_subjects($1,$2,$3)',[t,e,b]);
 check('order acceptance company approval and delivery exception remain independent',updated.items[0].customer_state==='accepted'
  &&updated.items[0].company_state==='approved'&&updated.items[0].delivery_state==='attention_required');
 await deny('completed delivery evidence cannot be silently replaced by another request','55000',()=>cmd('issue_delivery',{...payload,id:randomUUID()}));
 await actor(null);
 await deny('anonymous recipients cannot enumerate raw delivery responses','42501',()=>db.query('select * from field_sales.delivery_responses'));
 await db.exec('reset role');
 check('anonymous API surface contains exactly separate order and delivery recipient operations',(await db.query("select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and has_function_privilege('anon',p.oid,'execute')")).rows.length===6);
 await actor(owner);
 const secondId=randomUUID(),secondLine=randomUUID();
 const secondDraft=await value('select api.upsert_delivery($1,$2,$3,$4,$5,now(),$6,null)',[t,e,b,randomUUID(),randomUUID(),
  {...header,id:secondId,lines:[{line_id:secondLine,sales_order_line_id:ol.id,base_quantity:'0.250000'}]}]);
 const secondSubmitted=await value('select api.transition_operational_document($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,randomUUID(),randomUUID(),
  {document_type:'delivery',document_id:secondId,action:'submit'},secondDraft.entity.version]);
 await value('select api.post_delivery($1,$2,$3,$4,$5,now(),$6,$7)',[t,e,b,randomUUID(),randomUUID(),{document_id:secondId},secondSubmitted.entity.version]);
 const secondSubject=(await value('select api.field_sales_delivery_subjects($1,$2,$3)',[t,e,b])).items.find(x=>x.id===secondId);
 const secondIssue=await cmd('issue_delivery',{id:randomUUID(),delivery_id:secondId,delivery_version:secondSubject.delivery_version,
  delivery_digest:secondSubject.delivery_digest,contact_id:contact.id,contact_version:contact.version.toString()});
 check('separate partial deliveries of the same order each retain their own acknowledgement challenge',secondIssue.entity.delivery_id===secondId
  &&secondSubject.offer.lines[0].posted_base_quantity==='0.250000');
 await db.exec('reset role');
 check('a later partial delivery preserves the original immutable quantity response',await value('select count(*)=1 from field_sales.delivery_responses where delivery_id=$1',[did]));
 return ctx;
}
