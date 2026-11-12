import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function exercise(db, checks) {
  const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
  const scalar = async (sql, args = []) => Object.values(await one(sql, args))[0];
  const check = (label, value) => { assert.ok(value, label); checks.push(label); };
  const reject = async (label, code, call, message) => {
    await db.exec('savepoint opening_attack');
    let error;
    try { await call(); } catch (caught) { error = caught; }
    await db.exec('rollback to savepoint opening_attack; release savepoint opening_attack');
    assert.equal(error?.code, code, label + ': ' + (error?.message ?? 'allowed'));
    if (message) assert.equal(error.message, message, label);
    checks.push(label);
  };
  const owner = randomUUID(), approver = randomUUID(), outsider = randomUUID();
  const user = async (id, aal = 'aal2') => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
      sub: id, aal, amr: [{ method: 'totp', timestamp: Math.floor(Date.now() / 1000) }],
    })]);
    await db.exec('set local role authenticated');
  };
  for (const id of [owner, approver, outsider]) {
    await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())', [id, id + '@opening.invalid']);
  }
  await user(owner);
  const scope = await scalar("select api.bootstrap_tenant('Opening Test','opening-test','Opening Company','OC','Main Branch','HQ','Asia/Colombo','LKR',$1)", [randomUUID()]);
  const { tenant_id: tenant, legal_entity_id: entity, branch_id: branch } = scope;
  const scopeArgs = [tenant, entity, branch];
  const ar = randomUUID(), ap = randomUUID(), clearing = randomUUID(), tax = randomUUID(), variance = randomUUID();
  const customer = randomUUID(), supplier = randomUUID(), member = randomUUID(), role = randomUUID(), period = randomUUID();
  await db.exec('reset role');
  await db.query("insert into core.memberships(id,tenant_id,user_id,status) values($1,$2,$3,'active')", [member, tenant, approver]);
  await db.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values($1,$2,'opening_reviewer','Opening reviewer',true)", [role, tenant]);
  await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values($1,$2,$3,$4,$5,$6)', [tenant, member, role, entity, branch, owner]);
  await db.query(`insert into core.role_permissions(tenant_id,role_id,permission_code)
    select $1,r.id,p.code from core.roles r cross join core.permissions p
    where r.tenant_id=$1 and (r.code='tenant_owner' or r.id=$2)
      and (p.code like 'finance.openings.%' or p.code in ('finance.view','finance.controls.reconcile',
        'finance.receivables.view','finance.period.close','finance.receipts.allocate','finance.payments.allocate',
        'finance.receipts.reverse','finance.payments.reverse','finance.fx.post','finance.cash_flow.configure',
        'finance.journals.post','workflow.approvals.decide'))
    on conflict do nothing`, [tenant, role]);
  const gain = randomUUID(), legacyEquity = randomUUID(), cash = randomUUID(), grni = randomUUID();
  for (const [id, code, type, side] of [[ar,'AR','asset','debit'],[ap,'AP','liability','credit'],
    [clearing,'CLEAR','equity','credit'],[tax,'TAX','asset','debit'],[variance,'VAR','expense','debit'],
    [gain,'GAIN','revenue','credit'],[legacyEquity,'LEGACY-EQ','equity','credit'],
    [cash,'CASH','asset','debit'],[grni,'GRNI','liability','credit']]) {
    await db.query(`insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
      values($1,$2,$3,$4,$4,$5,$6,$7,$7)`, [id, tenant, entity, code, type, side, owner]);
  }
  await db.query(`insert into finance.cash_bank_accounts(tenant_id,legal_entity_id,branch_id,code,
    name,account_kind,account_id,currency_code,created_by,updated_by)
    values($1,$2,$3,'CASH','Synthetic cash account','cash',$4,'LKR',$5,$5)`,[...scopeArgs,cash,owner]);
  await db.query(`insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
    values($1,$2,'receivable_control',$3,$6,$6),($1,$2,'exchange_loss',$4,$6,$6),($1,$2,'exchange_gain',$5,$6,$6)`,
    [tenant, entity, ar, variance, gain, owner]);
  await db.query(`insert into procurement.supplier_bill_controls(tenant_id,legal_entity_id,payable_account_id,input_tax_account_id,variance_account_id,updated_by)
    values($1,$2,$3,$4,$5,$6)`, [tenant, entity, ap, tax, variance, owner]);
  await db.query(`insert into procurement.receipt_controls(tenant_id,legal_entity_id,grni_account_id,
    expense_account_id,maximum_over_receipt_percent,updated_by) values($1,$2,$3,$4,0,$5)`,
    [tenant,entity,grni,variance,owner]);
  for (const [id, code, kind] of [[customer,'CUS','customer'], [supplier,'SUP','supplier']]) {
    await db.query(`insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
      values($1,$2,$3,$3,$3,$4,$5,$5)`, [id, tenant, code, kind, owner]);
  }
  await db.query(`insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
    values($1,$2,$3,'Cutover month','2026-09-01','2026-09-30',$4,$4)`, [period, tenant, entity, owner]);
  await db.query(`insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
    values($1,$2,$3,'journal_entry','OJ',$4,$4),($1,$2,$3,'manual_journal','MJ',$4,$4)`, [tenant, entity, branch, owner]);
  const journalWorkflow = randomUUID();
  await db.query(`insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,
    name,status,lifecycle,created_by,updated_by)
    values($1,$2,$3,'manual_journal','Journal approval','active',$4,$5,$5)`, [journalWorkflow,tenant,entity,{
    states:['draft','submitted','approved','rejected','posted','settled','fulfilled','closed','cancelled','reversed'],
    transitions:[['draft','submitted'],['submitted','approved'],['submitted','rejected'],['rejected','draft'],
      ['draft','cancelled'],['submitted','cancelled'],['approved','posted']],
    posting_transitions:[['submitted','draft'],['approved','draft']],
    requires_approval:true,
  },owner]);
  await db.query(`insert into workflow.approval_matrix_steps(tenant_id,workflow_definition_id,role_id,
    step_order,created_by,updated_by) values($1,$2,$3,1,$4,$4)`,[tenant,journalWorkflow,role,owner]);
  const closingRate = randomUUID();
  await db.query(`insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,
    target_currency_code,rate,rate_type,effective_date,created_by,updated_by)
    values($1,$2,$3,'USD','LKR',320,'closing','2026-09-16',$4,$4)`, [closingRate,tenant,entity,owner]);

  const row = (overrides = {}) => ({
    external_document_key: 'AR-100', party_code: 'CUS', document_number: 'Legacy invoice 100',
    document_date: '2026-08-01', due_date: '2026-08-31', currency: 'USD',
    outstanding_amount: '10.25', carrying_base_amount: '3075.13',
    legacy_original_amount: '20.25', legacy_settled_amount: '10',
    ...overrides,
  });
  const batch = (overrides = {}) => ({
    id: randomUUID(), kind: 'AR', source_system: 'Existing ledger', cutoff_date: '2026-09-15',
    currency_code: 'USD', control_account_id: ar, clearing_account_id: clearing,
    file_sha256: 'ab'.repeat(32), lines: [row()], ...overrides,
  });
  const preview = payload => scalar('select api.preview_finance_opening_batch($1,$2,$3,$4)', [...scopeArgs, payload]);
  const identity = (payload, version = null) => [...scopeArgs, randomUUID(), randomUUID(), new Date().toISOString(), payload, version];
  const call = (operation, args) => scalar('select api.' + operation + '($1,$2,$3,$4,$5,$6,$7,$8)', args);
  const save = (payload, version = null) => call('upsert_finance_opening_batch', identity(payload, version));
  const transition = (id, action, version, reason = 'Reviewed opening evidence') =>
    call('transition_finance_opening_batch', identity({ document_id: id, action, reason }, version));
  const post = args => call('post_finance_opening_batch', args);
  const detail = id => scalar('select api.finance_opening_batch($1,$2,$3,$4)', [...scopeArgs, id]);

  await user(owner);
  const arBatch = batch({ lines: [row(), row({ external_document_key:'AR-credit', document_number:'Legacy credit', outstanding_amount:'-1.25', carrying_base_amount:'-371.13', legacy_original_amount:null, legacy_settled_amount:null })] });
  const reviewed = await preview(arBatch);
  check('public preview shows exact signed totals and both valid rows',
    reviewed.valid && reviewed.issues.length === 0 && reviewed.totals.row_count === 2 &&
    reviewed.totals.outstanding_amount === '9.000000' && reviewed.totals.carrying_base_amount === '2704.000000');
  const invalid = batch({ lines: [row({ party_code: 'SUP', due_date: '2026-02-31', outstanding_amount: '1.234' }),
    row({ external_document_key: 'bad-money', outstanding_amount: '2', carrying_base_amount: '-3' })] });
  const invalidPreview = await preview(invalid);
  check('invalid rows identify affected row and field', !invalidPreview.valid &&
    invalidPreview.issues.some(issue => issue.row === 2 && issue.field === 'party_code') &&
    invalidPreview.issues.some(issue => issue.row === 2 && issue.field === 'due_date') &&
    invalidPreview.issues.some(issue => issue.row === 2 && issue.field === 'outstanding_amount') &&
    invalidPreview.issues.some(issue => issue.row === 3 && issue.field === 'carrying_base_amount'));
  await reject('invalid batch save is rejected atomically', '22023', () => save(invalid), 'OPENING_VALIDATION_FAILED');
  const draft = (await save(arBatch)).entity;
  check('saved draft preserves the normalized source and stable line IDs',
    draft.status === 'draft' && draft.version === 1 && draft.lines.every(line => line.id) &&
    draft.lines[0].document_date === '2026-08-01');
  await reject('stale update cannot replace draft', '40001', () => save(arBatch, 9), 'VERSION_CONFLICT');
  await db.exec('savepoint opening_editor_history');
  const draftLineIds = draft.lines.map(line => line.id);
  await user(approver);
  const collaboratorDraft = (await save(arBatch, 1)).entity;
  assert.deepEqual(collaboratorDraft.lines.map(line => line.id), draftLineIds);
  await user(owner);
  const ownerDraft = (await save(arBatch, 2)).entity;
  await transition(draft.id, 'submit', ownerDraft.version);
  await user(approver);
  await reject('an earlier contributing editor cannot independently approve', '42501',
    () => transition(draft.id, 'approve', 4), 'SEGREGATION_OF_DUTIES_VIOLATION');
  await db.exec('rollback to savepoint opening_editor_history; release savepoint opening_editor_history');
  const pending = (await transition(draft.id, 'submit', draft.version)).entity;
  check('submit freezes source under a new version', pending.status === 'pending_approval' && pending.version === 2);
  await db.exec('savepoint opening_lifecycle');
  await reject('pending source cannot be edited before an explicit recall', '55000',
    () => save(arBatch, pending.version), 'OPENING_DRAFT_REQUIRED');
  await db.exec('savepoint opening_cancel_pending');
  const pendingCancelled = (await transition(draft.id,'cancel',2,'Cancel pending source')).entity;
  check('a pending batch can be cancelled before posting',
    pendingCancelled.status === 'cancelled' && pendingCancelled.version === 3);
  await db.exec('rollback to savepoint opening_cancel_pending; release savepoint opening_cancel_pending');
  const recalled = (await transition(draft.id,'recall',2,'Correct the staged source')).entity;
  check('recall returns pending source to draft and clears submission authority',
    recalled.status === 'draft' && recalled.version === 3 &&
    recalled.submitted_by === null && recalled.submitted_at === null &&
    recalled.approved_by === null && recalled.approved_at === null);
  const editedPayload = {
    ...arBatch, file_sha256:'ef'.repeat(32),
    lines:arBatch.lines.map((line,index) => index ? line : {...line,document_number:'Revised legacy invoice'}),
  };
  const edited = (await save(editedPayload,recalled.version)).entity;
  check('recalled draft accepts a versioned edit while preserving source line identities',
    edited.status === 'draft' && edited.version === 4 &&
    edited.content_hash !== recalled.content_hash && edited.lines[0].document_number === 'Revised legacy invoice' &&
    edited.lines.every((line,index) => line.id === draft.lines[index].id));
  const resubmitted = (await transition(draft.id,'submit',edited.version)).entity;
  await user(approver);
  const rejected = (await transition(draft.id,'reject',resubmitted.version,'Source needs correction')).entity;
  check('independent rejection returns the batch to an editable draft without approval',
    rejected.status === 'draft' && rejected.version === 6 &&
    rejected.submitted_by === null && rejected.approved_by === null && rejected.approved_at === null);
  await user(owner);
  const corrected = (await save(arBatch,rejected.version)).entity;
  const correctedPending = (await transition(draft.id,'submit',corrected.version)).entity;
  await user(approver);
  const correctedApproved = (await transition(draft.id,'approve',correctedPending.version)).entity;
  await user(owner);
  await reject('approved source cannot be edited before an explicit recall','55000',
    () => save(editedPayload,correctedApproved.version),'OPENING_DRAFT_REQUIRED');
  await db.exec('savepoint opening_cancel_approved');
  const approvedCancelled = (await transition(draft.id,'cancel',correctedApproved.version,'Cancel approved source')).entity;
  check('an approved batch can be cancelled before posting',
    approvedCancelled.status === 'cancelled' && approvedCancelled.version === 10 &&
    approvedCancelled.approved_by === null && approvedCancelled.approved_at === null);
  await db.exec('rollback to savepoint opening_cancel_approved; release savepoint opening_cancel_approved');
  const approvedRecalled = (await transition(draft.id,'recall',correctedApproved.version,'Reopen approved source')).entity;
  check('recalling an approved batch removes its previous approval',
    approvedRecalled.status === 'draft' && approvedRecalled.version === 10 &&
    approvedRecalled.approved_by === null && approvedRecalled.approved_at === null &&
    approvedRecalled.submitted_by === null);
  const revisedAgain = (await save(editedPayload,approvedRecalled.version)).entity;
  const draftCancelled = (await transition(draft.id,'cancel',revisedAgain.version,'Abandon staged source')).entity;
  check('a corrected draft can be cancelled before posting',
    draftCancelled.status === 'cancelled' && draftCancelled.version === 12);
  await reject('a cancelled batch cannot resume editing','55000',
    () => save(arBatch,draftCancelled.version),'OPENING_DRAFT_REQUIRED');
  await reject('a cancelled batch cannot be resubmitted','55000',
    () => transition(draft.id,'submit',draftCancelled.version),'OPENING_TRANSITION_INVALID');
  await db.exec('rollback to savepoint opening_lifecycle; release savepoint opening_lifecycle');
  await reject('preparer cannot approve own batch', '42501', () => transition(draft.id, 'approve', 2), 'SEGREGATION_OF_DUTIES_VIOLATION');
  await reject('unapproved batch cannot post', '55000', () => post(identity({ document_id:draft.id }, 2)), 'OPENING_APPROVAL_REQUIRED');
  await user(approver, 'aal1');
  await reject('approval requires verified MFA', '42501', () => transition(draft.id, 'approve', 2));
  await user(approver);
  const approved = (await transition(draft.id, 'approve', 2)).entity;
  check('independent reviewer approves exact source', approved.status === 'approved' && approved.approved_by === approver);
  await reject('modified party revision prevents posting an approved snapshot', '40001', async () => {
    await db.exec('reset role');
    await db.query("update crm.parties set display_name='Changed Customer' where id=$1", [customer]);
    await user(owner);
    await post(identity({ document_id:draft.id }, 3));
  }, 'OPENING_SOURCE_CHANGED');
  for (const [label,accountId] of [['control',ar],['clearing',clearing]]) {
    await reject('changed '+label+' account revision invalidates approval','40001',async () => {
      await db.exec('reset role');
      await db.query("update finance.accounts set name=name||' revised' where id=$1",[accountId]);
      await user(owner);
      await post(identity({document_id:draft.id},3));
    },'OPENING_SOURCE_CHANGED');
  }
  await reject('closed period prevents posting', '55000', async () => {
    await user(owner);
    await call('period_governance_command', identity({
      id:randomUUID(), period_id:period, action:'soft_lock', reason:'Exercise locked period',
    }, 1));
    await post(identity({ document_id:draft.id }, 3));
  }, 'PERIOD_CLOSED');
  await reject('changed open-period revision invalidates the approval', '40001', async () => {
    await db.exec('reset role');
    await db.query("update finance.fiscal_periods set name='Edited cutover month' where id=$1", [period]);
    await user(owner);
    await post(identity({ document_id:draft.id }, 3));
  }, 'OPENING_SOURCE_CHANGED');
  await user(owner);
  const postArgs = identity({ document_id:draft.id }, approved.version);
  await db.exec('savepoint opening_late_row_failure; reset role');
  await db.exec(`
    create function finance.fail_second_opening_fixture() returns trigger language plpgsql as $$
    begin
      if new.document_number='Legacy credit' then
        raise exception using errcode='23514', message='INJECTED_SECOND_ROW_FAILURE';
      end if;
      return new;
    end $$;
    create trigger fail_second_opening_fixture before insert on finance.open_items
      for each row execute function finance.fail_second_opening_fixture();
  `);
  await user(owner);
  await reject('a later posting failure aborts the whole batch', '23514', () => post(postArgs), 'INJECTED_SECOND_ROW_FAILURE');
  await db.exec('reset role');
  check('late failure leaves approval, both sources, ledger and receipt unchanged', await scalar(`
    select (select status='approved' from finance.opening_batches where id=$1)
      and (select count(*)=2 from finance.opening_lines where batch_id=$1 and open_item_id is null)
      and not exists(select 1 from finance.open_items)
      and not exists(select 1 from finance.journal_entries)
      and not exists(select 1 from core.command_receipts where command_id=$2)`, [draft.id,postArgs[3]]));
  await db.exec('rollback to savepoint opening_late_row_failure; release savepoint opening_late_row_failure');
  const receipt = await post(postArgs);
  const posted = receipt.entity;
  check('posting records one open item and one journal per opening document',
    posted.status === 'posted' && posted.open_item_ids.length === 2 && posted.journal_entry_ids.length === 2);
  assert.deepEqual(await post(postArgs), receipt);
  checks.push('exact posting retry recovers original acknowledgement');
  await reject('a revoked posting grant blocks recovery of an existing receipt', '42501', async () => {
    await db.exec('reset role');
    await db.query(`delete from core.role_permissions rp using core.roles r
      where rp.role_id=r.id and r.tenant_id=$1 and r.code='tenant_owner' and rp.permission_code='finance.openings.post'`, [tenant]);
    await user(owner);
    await post(postArgs);
  });
  const changed = [...postArgs]; changed[6] = { document_id:randomUUID() };
  await reject('changed posting replay is rejected', '22023', () => post(changed));
  await reject('posted batch cancellation is refused', '55000',
    () => transition(draft.id, 'cancel', posted.version),'OPENING_TRANSITION_INVALID');
  const source = await scalar('select api.finance_opening_source($1,$2,$3,$4)', [...scopeArgs, posted.lines[0].id]);
  check('source detail retains original and cutover dates separately',
    source.document_date === '2026-08-01' && source.due_date === '2026-08-31' &&
    source.cutoff_date === '2026-09-15' && Number(source.legacy_original_amount) === 20.25);
  const repeated = batch({ source_system: 'EXISTING LEDGER', cutoff_date: '2026-09-16', file_sha256: 'cd'.repeat(32) });
  const duplicate = await preview(repeated);
  check('external document uniqueness spans cutoffs and file digests', !duplicate.valid &&
    duplicate.issues.some(issue => issue.code === 'OPENING_DUPLICATE_DOCUMENT'));
  await reject('duplicate batch cannot save', '22023', () => save(repeated), 'OPENING_VALIDATION_FAILED');
  const arAge = await scalar('select api.customer_statement($1,$2,$3,$4,$5,$6,$7)',
    [...scopeArgs,customer,'USD','2026-09-15',[30,60,90]]);
  check('customer statement uses cutover residual and real original due date',
    arAge.rows.some(item => item.source_type === 'opening_receivable' && item.due_date === '2026-08-31' &&
      item.open_amount === '10.250000' && item.bucket === 1));

  const apBatch = batch({ kind:'AP', currency_code:'LKR', control_account_id:ap,
    lines:[row({external_document_key:'AP-100',party_code:'SUP',document_number:'Legacy supplier bill',currency:'LKR',
      outstanding_amount:'2000.50',carrying_base_amount:'2000.50',legacy_original_amount:null,legacy_settled_amount:null}),
      row({external_document_key:'AP-credit',party_code:'SUP',document_number:'Legacy supplier advance',currency:'LKR',
        outstanding_amount:'-800.25',carrying_base_amount:'-800.25',legacy_original_amount:null,legacy_settled_amount:null})] });
  const apDraft = (await save(apBatch)).entity;
  await transition(apDraft.id,'submit',1);
  await user(approver);
  await transition(apDraft.id,'approve',2);
  await user(owner);
  const apPosted = (await post(identity({ document_id:apDraft.id },3))).entity;
  check('AP credits and debits create payable items', apPosted.status === 'posted' && apPosted.open_item_ids.length === 2);
  const reconcile = kind => call('generate_control_reconciliation_report', identity({
    id:randomUUID(), kind, as_of:'2026-09-15',
  }, 0));
  const arReport = (await reconcile('AR')).entity;
  const apReport = (await reconcile('AP')).entity;
  const sections = (id, name) => scalar('select api.control_reconciliation_report_page($1,$2,$3,$4,$5,0,null)',
    [...scopeArgs,id,name]);
  const arAccounts = await sections(arReport.id,'accounts');
  const apAccounts = await sections(apReport.id,'accounts');
  check('AR control report reconciles exact 2704 carrying value to GL', arAccounts.items.some(item =>
    item.evidence_key === ar && Number(item.subledger_value) === 2704 && Number(item.gl_value) === 2704 && Number(item.difference) === 0));
  check('AP control report reconciles exact 1200.25 carrying value to GL', apAccounts.items.some(item =>
    item.evidence_key === ap && Number(item.subledger_value) === 1200.25 && Number(item.gl_value) === 1200.25 && Number(item.difference) === 0));
  const statement = async (kind, asOf) => (await call('generate_financial_statement', identity({
    id:randomUUID(), kind, period_id:period, as_of:asOf,
  },0))).entity;
  const statementAccounts = async report => (await scalar(
    "select api.financial_statement_page($1,$2,$3,$4,'accounts')", [...scopeArgs,report.id])).items;
  const amount = (accounts, id) => Number(accounts.find(account => account.account_id === id)?.closing_balance);
  const opening = await statement('trial_balance','2026-09-15');
  const openingAccounts = await statementAccounts(opening);
  check('opening trial balance agrees with the synthetic approved AR/AP schedule and clearing',
    opening.status === 'generated' && opening.journal_count === 8 &&
    Number(opening.difference) === 0 && amount(openingAccounts,ar) === 2704 &&
    amount(openingAccounts,ap) === -1200.25 && amount(openingAccounts,clearing) === -1503.75);

  await user(outsider);
  await reject('foreign user cannot read an opening batch', '42501', () => detail(draft.id));
  await reject('foreign user cannot preview an opening batch', '42501', () => preview(arBatch));
  await user(owner);
  await reject('application users cannot read private staging tables', '42501',
    () => scalar('select count(*) from finance.opening_lines'));
  await db.exec('reset role');
  check('posting creates no invented commerce, tax or allocations',
    await scalar(`select (select count(*) from sales.sales_invoices)=0 and
      (select count(*) from procurement.supplier_bills)=0 and
      (select count(*) from finance.open_item_allocations)=0 and
      (select count(*) from finance.journal_lines)=8`));
  check('AR posting refreshes exact customer credit exposure',
    Number(await scalar('select due_exposure from sales.customer_credit_exposures where customer_id=$1',[customer])) === 10.25);
  await user(owner);
  const complement = {
    id:randomUUID(), document_date:'2026-09-15', currency_code:'LKR',
    description:'Complementary legacy opening equity', reason:'Synthetic opening trial balance',
    lines:[
      {line_id:randomUUID(),account_id:clearing,debit:'1503.75',credit:'0'},
      {line_id:randomUUID(),account_id:legacyEquity,debit:'0',credit:'1503.75'},
    ],
  };
  await reject('manual journals cannot be used to repair a posted opening AR balance','55000', () => {
    const lines = [{...complement.lines[0],account_id:ar},complement.lines[1]];
    return call('upsert_manual_journal',identity({...complement,lines},0));
  },'SUBLEDGER_CONTROL_REQUIRES_SOURCE');
  const complementDraft = (await call('upsert_manual_journal',identity(complement,0))).entity;
  const complementPending = (await call('transition_manual_journal',
    identity({document_id:complement.id,action:'submit'},complementDraft.version))).entity;
  await user(approver);
  const complementApproved = (await call('transition_manual_journal',
    identity({document_id:complement.id,decision:'approved'},complementPending.version))).entity;
  const complementPosted = (await call('post_manual_journal',
    identity({document_id:complement.id},complementApproved.version))).entity;
  await user(owner);
  const completedOpening = await statement('trial_balance','2026-09-15');
  const completedOpeningAccounts = await statementAccounts(completedOpening);
  check('complementary governed opening journal clears the opening account without touching AR/AP',
    complementPosted.status === 'posted' && completedOpening.journal_count === 10 &&
    Number(completedOpening.difference) === 0 && amount(completedOpeningAccounts,clearing) === 0 &&
    amount(completedOpeningAccounts,legacyEquity) === -1503.75 &&
    amount(completedOpeningAccounts,ar) === 2704 && amount(completedOpeningAccounts,ap) === -1200.25);

  const apAge = await scalar('select api.supplier_statement($1,$2,$3,$4,$5,$6,$7)',
    [...scopeArgs,supplier,'LKR','2026-09-15',[30,60,90]]);
  check('supplier statement includes the opening bill and the separate unapplied advance', apAge.rows.some(item =>
    item.source_type === 'opening_payable' && item.open_amount === '2000.500000' && item.bucket === 1) &&
    apAge.rows.some(item => item.source_type === 'opening_payable' && item.open_amount === '-800.250000' && item.bucket === -1));
  const apTargets = await scalar('select api.payable_allocation_targets($1,$2,$3,$4,null)',
    [...scopeArgs,apPosted.lines[1].open_item_id]);
  check('existing payable target reader offers the imported bill for the imported advance',
    apTargets.items.some(item => item.id === apPosted.lines[0].open_item_id && item.source_type === 'opening_payable'));
  const arAllocated = await call('allocate_customer_receipt', identity({
    posting_date:'2026-09-16', source_open_item_id:posted.lines[1].open_item_id,
    allocations:[{ target_open_item_id:posted.lines[0].open_item_id, source_amount:'1.25', transaction_amount:'1.25' }],
  }));
  check('customer allocation uses carrying value from opening journals and records exact realized FX',
    Number(arAllocated.entity.allocations[0].exchange_difference) === -3.89 &&
    Number(arAllocated.entity.allocations[0].target_residual.amount) === 9 &&
    Number(arAllocated.entity.allocations[0].target_residual.base_amount) === 2700.11);
  const apAllocated = await call('allocate_supplier_credit', identity({
    posting_date:'2026-09-16', reason:'Apply legacy supplier advance', source_open_item_id:apPosted.lines[1].open_item_id,
    allocations:[{ target_open_item_id:apPosted.lines[0].open_item_id, source_amount:'800.25', transaction_amount:'800.25' }],
  }));
  check('supplier allocation clears the opening advance with exact carrying balance',
    Number(apAllocated.entity.source_residual.amount) === 0 &&
    Number(apAllocated.entity.allocations[0].target_residual.base_amount) === 1200.25);
  for (const [kind, control, remaining] of [['AR',ar,2700.11],['AP',ap,1200.25]]) {
    const report = await call('generate_control_reconciliation_report', identity({
      id:randomUUID(),kind,as_of:'2026-09-16',
    },0));
    const accounts = await sections(report.entity.id,'accounts');
    check(kind+' control stays reconciled after ordinary settlement', accounts.items.some(item =>
      item.evidence_key === control && Number(item.subledger_value) === remaining &&
      Number(item.gl_value) === remaining && Number(item.difference) === 0));
  }
  const arReversed = await call('reverse_customer_allocation', identity({
    posting_date:'2026-09-17', reason:'Reverse the tested AR allocation',
    allocation_id:arAllocated.entity.allocations[0].allocation_id,
  }));
  const apReversed = await call('reverse_supplier_allocation', identity({
    posting_date:'2026-09-17', reason:'Reverse the tested AP allocation',
    allocation_id:apAllocated.entity.allocations[0].allocation_id,
  }));
  check('existing allocation reversals restore the original carrying values',
    arReversed.entity.target_residual.base_amount === '3075.130000' &&
    arReversed.entity.source_residual.base_amount === '-371.130000' &&
    apReversed.entity.target_residual.base_amount === '2000.500000' &&
    apReversed.entity.source_residual.base_amount === '-800.250000');

  const fx = (await call('post_exchange_revaluation', identity({
    id:randomUUID(), period_id:period, action:'post', as_of:'2026-09-30', currency_code:'USD',
    exchange_rate_id:closingRate, reason:'Revalue the imported foreign residuals',
  },0))).entity;
  const fxDetail = await scalar('select api.exchange_revaluation_detail($1,$2,$3,$4)', [...scopeArgs,fx.id]);
  check('closing FX sees both opening sources and values them against their immutable AR control',
    fx.item_count === 2 && Number(fx.control_delta_base) === 176 &&
    fxDetail.items.every(item => item.source_type === 'opening_receivable' && item.control_account_id === ar));
  for (const [accountId, category] of [[cash,'cash'],[ar,'working_capital'],[ap,'working_capital'],
    [clearing,'noncash_adjustment'],[legacyEquity,'noncash_adjustment']]) {
    await call('configure_cash_flow_mapping',identity({
      id:randomUUID(), account_id:accountId, category, effective_date:'2026-09-01',
      reason:'Synthetic cash-flow mapping',
    },0));
  }
  const closing = await statement('trial_balance','2026-09-30');
  const closingAccounts = await statementAccounts(closing);
  const balance = await statement('balance_sheet','2026-09-30');
  const cashFlow = await statement('cash_flow','2026-09-30');
  check('first-close statements balance with FX revaluation and zero opening clearing',
    closing.status === 'generated' && closing.journal_count === 18 && Number(closing.difference) === 0 &&
    amount(closingAccounts,ar) === 2880 && amount(closingAccounts,ap) === -1200.25 &&
    amount(closingAccounts,clearing) === 0 && amount(closingAccounts,legacyEquity) === -1503.75 &&
    balance.status === 'generated' && Number(balance.difference) === 0 && Number(balance.current_earnings) === 176 &&
    cashFlow.status === 'generated' && Number(cashFlow.cash_flow.net_cash_change) === 0);
  const lock = async (action, version) => (await call('period_governance_command',identity({
    id:randomUUID(), period_id:period, action, reason:'Synthetic September close',
  },version))).entity;
  const softLock = await lock('soft_lock',1);
  const hardLock = await lock('hard_lock',softLock.period_version);
  assert.equal(hardLock.status,'hard_locked',JSON.stringify(hardLock.exceptions));
  check('synthetic September period hard-locks with no close exceptions', hardLock.exceptions.length === 0);
  const batchList = await scalar('select api.finance_opening_batches($1,$2,$3,null,1)',scopeArgs);
  const batchNext = await scalar('select api.finance_opening_batches($1,$2,$3,$4,1)',[...scopeArgs,batchList.next_cursor]);
  check('batch register provides bounded cursor pages without line payloads', batchList.items.length === 1 &&
    batchList.next_cursor && batchNext.items.length === 1 && batchNext.items[0].id !== batchList.items[0].id &&
    !('lines' in batchList.items[0]));
  const currencies = await scalar("select api.finance_opening_reference_options($1,$2,$3,'AR',null,'currencies')",scopeArgs);
  check('reference currency options include entity base precision and foreign currencies',
    currencies.base_currency_code === 'LKR' && currencies.base_scale === 2 && currencies.items.some(item=>item.code==='USD'));

  return {
    scope: {tenant:'Opening Test', entity:'Opening Company', branch:'Main Branch', baseCurrency:'LKR'},
    opening: {
      asOf:opening.as_of,
      importedDocuments:posted.open_item_ids.length+apPosted.open_item_ids.length,
      importJournalLines:opening.journal_count,
      receivableBaseDebit:openingAccounts.find(account => account.account_id===ar).closing_balance,
      payableBaseCredit:apAccounts.items.find(account => account.evidence_key===ap).gl_value,
      clearingBeforeComplement:openingAccounts.find(account => account.account_id===clearing).closing_balance,
      clearingAfterComplement:completedOpeningAccounts.find(account => account.account_id===clearing).closing_balance,
      trialBalanceDifference:completedOpening.difference,
    },
    firstClose: {
      asOf:closing.as_of, journalLines:closing.journal_count, periodStatus:hardLock.status,
      exceptions:hardLock.exceptions, trialBalanceDifference:closing.difference, balanceSheetDifference:balance.difference,
      assets:balance.assets, liabilities:balance.liabilities, equity:balance.equity, earnings:balance.current_earnings,
      fxControlDelta:fx.control_delta_base, netCashChange:cashFlow.cash_flow.net_cash_change,
    },
  };
}
