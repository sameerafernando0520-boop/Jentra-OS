import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function exerciseReversal(db, checks) {
  const one = async (sql,args=[]) => (await db.query(sql,args)).rows[0];
  const scalar = async (sql,args=[]) => Object.values(await one(sql,args))[0];
  const check = (label,value) => {assert.ok(value,label);checks.push(label);};
  const reject = async (label,code,operation,message) => {
    await db.exec('savepoint reversal_rejection');
    let error;
    try {await operation();} catch (caught) {error=caught;}
    await db.exec('rollback to savepoint reversal_rejection; release savepoint reversal_rejection');
    assert.equal(error?.code,code,label+': '+(error?.message??'allowed'));
    if (message) assert.equal(error.message,message,label);
    checks.push(label);
  };
  const maker=randomUUID(),reviewer=randomUUID(),alternate=randomUUID(),outsider=randomUUID();
  const user=async (id,aal='aal2') => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({
      sub:id,aal,amr:[{method:'totp',timestamp:Math.floor(Date.now()/1000)}],
    })]);
    await db.exec('set local role authenticated');
  };
  await db.exec('reset role');
  for (const id of [maker,reviewer,alternate,outsider]) {
    await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@reversal.invalid']);
  }
  await user(maker);
  const scope=await scalar("select api.bootstrap_tenant('Opening reversal test','opening-reversal','Reversal Company','RC','Main','HQ','Asia/Colombo','LKR',$1)",[randomUUID()]);
  const {tenant_id:tenant,legal_entity_id:entity,branch_id:branch}=scope;
  const scopeArgs=[tenant,entity,branch];
  const ar=randomUUID(),ap=randomUUID(),clearing=randomUUID(),tax=randomUUID(),expense=randomUUID(),gain=randomUUID();
  const customer=randomUUID(),supplier=randomUUID(),period=randomUUID(),reviewerRole=randomUUID(),rate=randomUUID();
  await db.exec('reset role');
  await db.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values($1,$2,'reversal_review','Reversal reviewer',true)",[reviewerRole,tenant]);
  for (const actor of [reviewer,alternate]) {
    const membership=randomUUID();
    await db.query("insert into core.memberships(id,tenant_id,user_id,status) values($1,$2,$3,'active')",[membership,tenant,actor]);
    await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values($1,$2,$3,$4,$5,$6)',
      [tenant,membership,reviewerRole,entity,branch,maker]);
  }
  await db.query(`insert into core.role_permissions(tenant_id,role_id,permission_code)
    select $1,role.id,permission.code from core.roles role cross join core.permissions permission
    where role.tenant_id=$1 and (role.code='tenant_owner' or role.id=$2)
      and (permission.code like 'finance.openings.%' or permission.code in
        ('finance.view','finance.receivables.view','finance.controls.reconcile','finance.receipts.allocate',
         'finance.payments.allocate','finance.receipts.reverse','finance.payments.reverse','finance.fx.post',
         'finance.period.close','finance.cash_flow.configure'))
    on conflict do nothing`,[tenant,reviewerRole]);
  for (const [id,code,type,side] of [[ar,'AR','asset','debit'],[ap,'AP','liability','credit'],
    [clearing,'CLEAR','equity','credit'],[tax,'TAX','asset','debit'],[expense,'LOSS','expense','debit'],[gain,'GAIN','revenue','credit']]) {
    await db.query(`insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
      values($1,$2,$3,$4,$4,$5,$6,$7,$7)`,[id,tenant,entity,code,type,side,maker]);
  }
  await db.query(`insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
    values($1,$2,'receivable_control',$3,$6,$6),($1,$2,'exchange_gain',$4,$6,$6),($1,$2,'exchange_loss',$5,$6,$6)`,
    [tenant,entity,ar,gain,expense,maker]);
  await db.query(`insert into procurement.supplier_bill_controls(tenant_id,legal_entity_id,payable_account_id,input_tax_account_id,variance_account_id,updated_by)
    values($1,$2,$3,$4,$5,$6)`,[tenant,entity,ap,tax,expense,maker]);
  const grni=randomUUID();
  await db.query(`insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
    values($1,$2,$3,'GRNI','GRNI','liability','credit',$4,$4)`,[grni,tenant,entity,maker]);
  await db.query(`insert into procurement.receipt_controls(tenant_id,legal_entity_id,grni_account_id,
    expense_account_id,maximum_over_receipt_percent,updated_by) values($1,$2,$3,$4,0,$5)`,[tenant,entity,grni,expense,maker]);
  const cash=randomUUID(),cashBank=randomUUID();
  await db.query(`insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
    values($1,$2,$3,'CASH','Cash','asset','debit',$4,$4)`,[cash,tenant,entity,maker]);
  await db.query(`insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
    values($1,$2,$3,$4,'CASH','Cash account','cash',$5,'LKR',$6,$6)`,[cashBank,...scopeArgs,cash,maker]);
  for (const [id,code,kind] of [[customer,'CUS','customer'],[supplier,'SUP','supplier']]) {
    await db.query(`insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
      values($1,$2,$3,$3,$3,$4,$5,$5)`,[id,tenant,code,kind,maker]);
  }
  await db.query(`insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
    values($1,$2,$3,'Reversal month','2026-09-01','2026-09-30',$4,$4),
          ($5,$2,$3,'Next month','2026-10-01','2026-10-31',$4,$4)`,[period,tenant,entity,maker,randomUUID()]);
  await db.query(`insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
    values($1,$2,$3,'journal_entry','RJ',$4,$4)`,[tenant,entity,branch,maker]);
  await db.query(`insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,target_currency_code,
    rate,rate_type,effective_date,created_by,updated_by) values($1,$2,$3,'USD','LKR',310,'closing','2026-09-01',$4,$4)`,[rate,tenant,entity,maker]);
  const identity=(payload,version=null) => [...scopeArgs,randomUUID(),randomUUID(),new Date().toISOString(),payload,version];
  const call=(operation,args) => scalar('select api.'+operation+'($1,$2,$3,$4,$5,$6,$7,$8)',args);
  const batchDetail=id => scalar('select api.finance_opening_batch($1,$2,$3,$4)',[...scopeArgs,id]);
  const reversalDetail=id => scalar('select api.finance_opening_reversal($1,$2,$3,$4)',[...scopeArgs,id]);
  const prepareArgs=(batch,overrides={}) => identity({id:randomUUID(),document_id:batch.id,posting_date:'2026-09-20',reason:'Correct erroneous legacy import',...overrides},0);
  const transitionArgs=(request,action) => identity({document_id:request.id,batch_id:request.batch_id,action,reason:'Independent source review'},request.version);
  const postArgs=request => identity({document_id:request.id,batch_id:request.batch_id},request.version);
  const createBatch=async (kind='AR',currency='LKR') => {
    const foreign=currency==='USD';
    const payload={id:randomUUID(),kind,source_system:'Reversal legacy fixture',cutoff_date:'2026-09-15',currency_code:currency,
      control_account_id:kind==='AR'?ar:ap,clearing_account_id:clearing,file_sha256:'cd'.repeat(32),
      lines:[{row_number:2,external_document_key:randomUUID(),party_code:kind==='AR'?'CUS':'SUP',document_number:'Legacy debit',
        document_date:'2026-08-01',due_date:'2026-08-31',currency,outstanding_amount:foreign?'10.25':'120.25',carrying_base_amount:foreign?'3075.13':'120.25'},
        {row_number:3,external_document_key:randomUUID(),party_code:kind==='AR'?'CUS':'SUP',document_number:'Legacy credit',
          document_date:'2026-08-02',due_date:'2026-09-01',currency,outstanding_amount:foreign?'-1.25':'-20.25',carrying_base_amount:foreign?'-371.13':'-20.25'}]};
    await user(maker);
    const draft=(await call('upsert_finance_opening_batch',identity(payload,0))).entity;
    await call('transition_finance_opening_batch',identity({document_id:draft.id,action:'submit'},draft.version));
    await user(reviewer);
    const approved=(await call('transition_finance_opening_batch',identity({document_id:draft.id,action:'approve'},2))).entity;
    await user(maker);
    return (await call('post_finance_opening_batch',identity({document_id:draft.id},approved.version))).entity;
  };
  const arBatch=await createBatch();
  const apBatch=await createBatch('AP');
  await db.exec('reset role');
  const original=await scalar(`select jsonb_build_object('batch',to_jsonb(batch),'lines',
    (select jsonb_agg(to_jsonb(line) order by line.id) from finance.opening_lines line where line.batch_id=batch.id),
    'items',(select jsonb_agg(to_jsonb(item) order by item.id) from finance.open_items item
      where item.id in (select open_item_id from finance.opening_lines where batch_id=batch.id)))
    from finance.opening_batches batch where id=$1`,[arBatch.id]);
  await user(maker,'aal1');
  await reject('reversal request requires verified MFA','42501',() => call('prepare_finance_opening_reversal',prepareArgs(arBatch)));
  await user(maker);
  await reject('reversal date cannot precede original cutoff','22023',() => call('prepare_finance_opening_reversal',prepareArgs(arBatch,{posting_date:'2026-09-14'})),'OPENING_REVERSAL_INPUT_INVALID');
  const preparedArgs=prepareArgs(arBatch);
  const requested=(await call('prepare_finance_opening_reversal',preparedArgs)).entity;
  check('reversal request preserves exact source evidence under its own version',requested.status==='pending_approval'&&requested.version===1&&requested.batch_id===arBatch.id&&requested.lines.length===2);
  assert.deepEqual((await call('prepare_finance_opening_reversal',preparedArgs)).entity,requested);
  checks.push('exact reversal preparation replay recovers the same request');
  await reject('only one active reversal can claim a batch','55000',() => call('prepare_finance_opening_reversal',prepareArgs(arBatch)),'OPENING_REVERSAL_ALREADY_REQUESTED');
  await reject('approval is required before posting','55000',
    () => call('post_finance_opening_reversal',postArgs(requested)),'OPENING_REVERSAL_APPROVAL_REQUIRED');
  await reject('original preparer cannot approve the reversal','42501',() => call('transition_finance_opening_reversal',transitionArgs(requested,'approve')),'SEGREGATION_OF_DUTIES_VIOLATION');
  await user(reviewer);
  const approved=(await call('transition_finance_opening_reversal',transitionArgs(requested,'approve'))).entity;
  check('independent reviewer approves the exact reversal snapshot',approved.status==='approved'&&approved.version===2&&approved.approved_by===reviewer);
  await user(maker);
  const postIdentity=postArgs(approved);
  await db.exec('savepoint late_reversal_failure; reset role');
  await db.exec(`create function finance.fail_second_fixture_counter() returns trigger language plpgsql as $$
    begin
      if new.source_type = 'opening_receivable_reversal' and new.document_number = 'Reversal Legacy credit' then
        raise exception using errcode='55000', message='FIXTURE_SECOND_COUNTER_FAILED';
      end if;
      return new;
    end $$;
    create trigger fixture_second_counter_failure before insert on finance.open_items
      for each row execute function finance.fail_second_fixture_counter()`);
  await user(maker);
  await reject('failure on the second counter rolls back the whole batch','55000',
    () => call('post_finance_opening_reversal',postIdentity),'FIXTURE_SECOND_COUNTER_FAILED');
  await db.exec('reset role');
  const atomicRollback = await scalar(`select
    not exists(select 1 from finance.opening_reversal_lines where reversal_id=$1)
    and not exists(select 1 from finance.open_items where tenant_id=$2 and command_id=$3)
    and not exists(select 1 from finance.journal_entries where tenant_id=$2 and command_id=$3)
    and not exists(select 1 from finance.open_item_allocations where tenant_id=$2 and command_id=$3)
    and not exists(select 1 from core.command_receipts where tenant_id=$2 and command_id=$3)`,
    [approved.id,tenant,postIdentity[3]]);
  check('failed reversal leaves no counter, journal, allocation or receipt',atomicRollback);
  await db.exec('rollback to savepoint late_reversal_failure; release savepoint late_reversal_failure');
  await user(maker);
  const posted=(await call('post_finance_opening_reversal',postIdentity)).entity;
  check('AR reversal creates exact counter items and permanent allocation links',posted.status==='posted'&&posted.version===3&&posted.lines.every(line=>line.id&&line.reversal_open_item_id&&line.journal_entry_id&&line.allocation_id));
  assert.deepEqual((await call('post_finance_opening_reversal',postIdentity)).entity,posted);
  checks.push('exact posted reversal replay does not duplicate ledger effects');
  const changedReplay=[...postIdentity];
  changedReplay[6]={...changedReplay[6], batch_id:apBatch.id};
  await reject('changed reversal replay is refused','22023',
    () => call('post_finance_opening_reversal',changedReplay),'IDEMPOTENCY_MISMATCH');
  await reject('revoked reversal posting authority blocks receipt recovery','42501',async () => {
    await db.exec('reset role');
    await db.query(`delete from core.role_permissions permission using core.roles role
      where permission.role_id=role.id and role.tenant_id=$1 and role.code='tenant_owner'
        and permission.permission_code='finance.openings.reverse'`,[tenant]);
    await user(maker);
    await call('post_finance_opening_reversal',postIdentity);
  });
  const batchWithReversal=await batchDetail(arBatch.id);
  check('original batch advertises bounded reversal status',batchWithReversal.reversal_supported===true&&batchWithReversal.reversal.id===posted.id&&batchWithReversal.reversal.status==='posted');
  await db.exec('reset role');
  const after=await scalar(`select jsonb_build_object('batch',to_jsonb(batch),'lines',
    (select jsonb_agg(to_jsonb(line) order by line.id) from finance.opening_lines line where line.batch_id=batch.id),
    'items',(select jsonb_agg(to_jsonb(item) order by item.id) from finance.open_items item
      where item.id in (select open_item_id from finance.opening_lines where batch_id=batch.id)))
    from finance.opening_batches batch where id=$1`,[arBatch.id]);
  assert.deepEqual(after,original);
  checks.push('posted reversal preserves original batch lines and item history byte for byte');
  check('all original and counter residuals close on reversal date',await scalar(`select bool_and((finance.flow_residual($1,item.id,'2026-09-20')->>'amount')::numeric=0
    and (finance.flow_residual($1,item.id,'2026-09-20')->>'base_amount')::numeric=0) from finance.open_items item where tenant_id=$1 and kind='AR'`,[tenant]));
  check('as-of residuals retain the unpaid original before reversal',Number(await scalar("select finance.flow_residual($1,$2,'2026-09-19')->>'amount'",[tenant,arBatch.lines[0].open_item_id]))===120.25);
  await user(maker);
  const source=await scalar('select api.finance_opening_source($1,$2,$3,$4)',[...scopeArgs,posted.lines[0].id]);
  check('counter source detail retains original lineage and actual counter dates',source.source_type==='opening_receivable_reversal'&&source.reversal_id===posted.id&&source.reversal_of_source_id===arBatch.lines[0].id&&source.due_date==='2026-09-20'&&source.original_due_date==='2026-08-31'&&source.outstanding_amount==='-120.250000');
  await reject('system AR closing allocation cannot be generically reversed','55000',() => call('reverse_customer_allocation',identity({allocation_id:posted.lines[0].allocation_id,posting_date:'2026-09-21',reason:'Attempt to reopen corrected source'})),'OPENING_REVERSAL_ALLOCATION_IMMUTABLE');
  const rejectedRequest=(await call('prepare_finance_opening_reversal',prepareArgs(apBatch))).entity;
  await user(reviewer);
  const rejected=(await call('transition_finance_opening_reversal',transitionArgs(rejectedRequest,'reject'))).entity;
  check('independent rejection is terminal and a new request is allowed',rejected.status==='rejected');
  await user(maker);
  const cancelledRequest=(await call('prepare_finance_opening_reversal',prepareArgs(apBatch))).entity;
  const cancelled=(await call('transition_finance_opening_reversal',transitionArgs(cancelledRequest,'cancel'))).entity;
  check('the preparer can cancel a pending reversal',cancelled.status==='cancelled');
  const apRequested=(await call('prepare_finance_opening_reversal',prepareArgs(apBatch,{posting_date:'2026-10-02'}))).entity;
  await user(reviewer);
  const apApproved=(await call('transition_finance_opening_reversal',transitionArgs(apRequested,'approve'))).entity;
  await user(maker);
  await db.exec('savepoint stale_reversal_account; reset role');
  await db.query('update finance.accounts set version=version+1 where tenant_id=$1 and id=$2',[tenant,clearing]);
  await user(maker);
  await reject('a changed account revision invalidates reversal approval','55000',
    () => call('post_finance_opening_reversal',postArgs(apApproved)),'OPENING_REVERSAL_STALE');
  await db.exec('rollback to savepoint stale_reversal_account; release savepoint stale_reversal_account');
  await reject('active supplier payment selection blocks reversal posting','55000',async () => {
    await db.exec('reset role');
    const proposal=randomUUID();
    await db.query(`insert into procurement.payment_proposals(id,tenant_id,legal_entity_id,branch_id,supplier_id,cash_bank_account_id,
      document_date,currency_code,base_currency_code,exchange_rate,total,base_total,lines,created_by,prepared_by,updated_by)
      values($1,$2,$3,$4,$5,$6,'2026-09-21','LKR','LKR',1,10,10,'[]',$7,$7,$7)`,
      [proposal,...scopeArgs,supplier,cashBank,maker]);
    await db.query(`insert into procurement.payment_claims(tenant_id,legal_entity_id,branch_id,proposal_id,open_item_id,amount)
      values($1,$2,$3,$4,$5,10)`,[...scopeArgs,proposal,apBatch.lines[0].open_item_id]);
    await user(maker);
    await call('post_finance_opening_reversal',postArgs(apApproved));
  },'PAYABLE_ITEM_ALREADY_SELECTED');
  const allocateAp=()=>call('allocate_supplier_credit',identity({
    source_open_item_id:apBatch.lines[1].open_item_id,posting_date:'2026-09-21',reason:'Fixture settlement',
    allocations:[{target_open_item_id:apBatch.lines[0].open_item_id,source_amount:'20.25',transaction_amount:'20.25'}],
  }));
  await db.exec('savepoint reversal_after_settlement');
  const allocated=(await allocateAp()).entity.allocations[0];
  await call('reverse_supplier_allocation',identity({
    allocation_id:allocated.allocation_id,posting_date:'2026-09-22',reason:'Fixture settlement reversal',
  }));
  await reject('even reversed settlement history blocks posting after approval','55000',
    () => call('post_finance_opening_reversal',postArgs(apApproved)),'OPENING_REVERSAL_SETTLEMENT_HISTORY');
  const obsolete=(await call('transition_finance_opening_reversal',transitionArgs(apApproved,'cancel'))).entity;
  check('an obsolete approval can still be cancelled',obsolete.status==='cancelled');
  await db.exec('rollback to savepoint reversal_after_settlement; release savepoint reversal_after_settlement');
  const apPosted=(await call('post_finance_opening_reversal',postArgs(apApproved))).entity;
  check('base-currency AP can reverse in a later open period',apPosted.status==='posted'&&apPosted.lines.length===2);
  await reject('system AP closing allocation cannot be generically reversed','55000',() => call('reverse_supplier_allocation',identity({allocation_id:apPosted.lines[0].allocation_id,posting_date:'2026-10-03',reason:'Attempt to reopen corrected AP source'})),'OPENING_REVERSAL_ALLOCATION_IMMUTABLE');
  for (const [kind,control] of [['AR',ar],['AP',ap]]) {
    const report=(await call('generate_control_reconciliation_report',identity({id:randomUUID(),kind,as_of:'2026-10-02'},0))).entity;
    const accounts=await scalar("select api.control_reconciliation_report_page($1,$2,$3,$4,'accounts',0,null)",[...scopeArgs,report.id]);
    check(kind+' reversed subledger and GL reconcile to exact zero',accounts.items.some(account=>account.evidence_key===control&&Number(account.subledger_value)===0&&Number(account.gl_value)===0&&Number(account.difference)===0));
  }
  const foreignBatch=await createBatch('AR','USD');
  const fxArgs=asOf => identity({id:randomUUID(),period_id:period,action:'post',as_of:asOf,
    currency_code:'USD',exchange_rate_id:rate,reason:'Fixture FX run'},0);
  await db.exec('savepoint reversal_after_fx');
  const fxBefore=(await call('post_exchange_revaluation',fxArgs('2026-09-18'))).entity;
  check('fixture FX captures the original foreign items',fxBefore.item_count===2);
  await reject('an existing FX snapshot blocks reversal','55000',
    () => call('prepare_finance_opening_reversal',prepareArgs(foreignBatch)),'OPENING_REVERSAL_FX_HISTORY');
  await db.exec('rollback to savepoint reversal_after_fx; release savepoint reversal_after_fx');
  await reject('foreign-currency reversal must remain in the original period','55000',
    () => call('prepare_finance_opening_reversal',prepareArgs(foreignBatch,{posting_date:'2026-10-02'})),
    'OPENING_REVERSAL_FX_PERIOD');
  const foreignRequested=(await call('prepare_finance_opening_reversal',prepareArgs(foreignBatch))).entity;
  await user(reviewer);
  const foreignApproved=(await call('transition_finance_opening_reversal',transitionArgs(foreignRequested,'approve'))).entity;
  await user(maker);
  const foreignPosted=(await call('post_finance_opening_reversal',postArgs(foreignApproved))).entity;
  check('foreign-currency reversal preserves original carrying value exactly',
    foreignPosted.lines[0].carrying_base_amount==='-3075.130000');
  await reject('a backdated FX run cannot pick up corrected opening items','55000',
    () => call('post_exchange_revaluation',fxArgs('2026-09-19')),'OPENING_REVERSED_SOURCE_FX');
  const periodEndFx=(await call('post_exchange_revaluation',fxArgs('2026-09-30'))).entity;
  check('period-end FX remains available after an in-period reversal',
    periodEndFx.item_count===0 && periodEndFx.journal_entry_id===null);
  for (const [accountId,category] of [[cash,'cash'],[ar,'working_capital'],[ap,'working_capital'],[clearing,'noncash_adjustment']]) {
    await call('configure_cash_flow_mapping',identity({
      id:randomUUID(),account_id:accountId,category,effective_date:'2026-09-01',
      reason:'Fixture cash-flow mapping',
    },0));
  }
  const lock = async (action,version) => (await call('period_governance_command',identity({
    id:randomUUID(),period_id:period,action,reason:'Fixture reversal period close',
  },version))).entity;
  const softLocked=await lock('soft_lock',1);
  const hardLocked=await lock('hard_lock',softLocked.period_version);
  assert.equal(hardLocked.status,'hard_locked',JSON.stringify(hardLocked.exceptions));
  check('foreign reversal preserves the ability to hard-close its source period',hardLocked.exceptions.length===0);
  await user(outsider);
  await reject('foreign caller cannot read reversal details','42501',()=>reversalDetail(posted.id));
  await user(maker);
  await reject('private reversal staging remains inaccessible','42501',()=>scalar('select count(*) from finance.opening_reversals'));
  return {
    scope:{tenant:'Opening reversal test',entity:'Reversal Company',branch:'Main'},
    postingDates:{ar:'2026-09-20',ap:'2026-10-02'},
    reversedLines:{ar:posted.lines.length,ap:apPosted.lines.length,foreign:foreignPosted.lines.length},
    atomicRollback,periodEndFxItems:periodEndFx.item_count,sourcePeriodStatus:hardLocked.status,
  };
}
