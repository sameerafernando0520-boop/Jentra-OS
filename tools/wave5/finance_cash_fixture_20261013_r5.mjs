import crypto from 'node:crypto';
import { hashBytes, immutableJson, isUuid } from './runtime_contract.mjs';
import { FIXTURE_CAPS } from './runtime_fixture_spec.mjs';

// New bounded administration fixture only. It is not a user posting or W4
// payroll approval/calculation result. No receipt, Auth row, permission or
// actor claim is manufactured. Every created row carries synthetic provenance.
export const FINANCE_SCOPE = immutableJson({ key: 'runtime', tenantId: 'babe6c86-a764-4d3a-80a3-952a7c096c2c',
  entityId: 'caa2bb06-219a-47e9-8132-66d1271b0ffd', branchId: '3813692c-f0de-4c69-8e34-d56cf54695b1' });
export const FINANCE_ACTOR = '8b740ab8-24f7-4455-a78b-aea0d99d20f6';
export const FINANCE_CALENDAR = immutableJson({ fixtureDay: '2026-10-13', issueDate: '2026-10-09', settlementDate: '2026-10-11',
  reversalDate: '2026-10-14', horizonStart: '2026-10-14', horizonEnd: '2026-10-21', dueDate: '2026-10-16', delayedDate: '2026-10-17' });
export const financeId = label => {
  if (typeof label !== 'string' || !/^[a-z][a-z0-9.-]{0,70}$/.test(label)) throw Error('EXACT_FINANCE_FIXTURE_LABEL_REQUIRED');
  const hex = crypto.createHash('sha256').update('jentra.wave5.finance.r5.20261013:' + label).digest('hex').slice(0,32);
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
};
export const FINANCE_ACCOUNTS = immutableJson([
  ['bank','asset','debit','current_asset'], ['inventory','asset','debit','inventory'],
  ['receivable','asset','debit','current_asset'], ['payable','liability','credit','current_liability'],
  ['payroll','liability','credit','current_liability'], ['reimbursement','liability','credit','current_liability'],
  ['equity','equity','credit','equity'], ['revenue','revenue','credit','revenue'],
  ['cost','expense','debit','cost_of_sales'], ['expense','expense','debit','operating_expense']
].map(([key,type,normal,label])=>({key,id:financeId('account.'+key),type,normal,label})));
export const FINANCE_JOURNALS = immutableJson([
  ['capital','bank','equity','100000.000001','issueDate'],
  ['stock','inventory','equity','1000.000001','issueDate'],
  ['revenue','receivable','revenue','3000.000001','issueDate'],
  ['cost','cost','payable','1200.000002','issueDate'],
  ['payroll','expense','payroll','10.000001','issueDate'],
  ['recovery','payroll','expense','2.000002','issueDate'],
  ['reimbursement','expense','reimbursement','4.000004','issueDate'],
  ['settlement','payroll','bank','3.000000','settlementDate'],
  ['future-reversal','bank','payroll','3.000000','reversalDate']
].map(([key,debit,credit,amount,dateKey])=>({key,id:financeId('journal.'+key),debit:financeId('account.'+debit),
  credit:financeId('account.'+credit),amount,date:FINANCE_CALENDAR[dateKey]})));
export const FINANCE_COUNTS = immutableJson({ accounts:10, journals:9, journalLines:18, openItems:2, incidentalParties:2,
  payrollObligations:1, payrollCorrections:1, projectReimbursements:1, financialPublications:3,
  classificationReviews:1, cashScenarios:2, governedExports:4 });
export const FINANCE_EXPECTED = immutableJson({ revenue:'3000.000001', expenses:'1212.000005', netProfit:'1787.999996',
  assets:'103997.000003', liabilities:'1209.000005', equity:'101000.000002', currentEarnings:'1787.999996',
  openingCash:'99997.000001', payrollOpening:'7.000001', payrollAfterReversal:'10.000001', recovery:'-2.000002', reimbursement:'4.000004',
  cashFinalBalance:'101787.999997', hypotheticalFinalBalance:'101788.999998',
  authoritativeNonemptyFamilies:['bank_cash','receivables','payables','payroll','project_reimbursements'] });
const q = text => `'${String(text).replaceAll("'","''")}'`;
const uid = label => q(financeId(label))+'::uuid';
const {tenantId,entityId,branchId}=FINANCE_SCOPE;
const tables = ['crm.parties','finance.accounts','finance.fiscal_periods','finance.journal_entries','finance.journal_lines','finance.cash_bank_accounts','finance.open_items',
  'people.employees','people_payroll.settings_versions','people_payroll.runs','people_payroll.run_employees','people_payroll.run_revisions',
  'people_payroll.employee_calculations','people_payroll.obligations','people_payroll.obligation_effects','people_payroll.settlements',
  'people_payroll.settlement_allocations','people_payroll.corrections','people_payroll.correction_balances','people_payroll.correction_balance_effects',
  'projects.register','projects.expenses','projects.expense_revisions','projects.reimbursements','projects.reimbursement_effects'];

export function validateFinanceFixture(review) {
  const approved = review?.syntheticScopes?.find(s=>s.key==='runtime');
  if (review?.projectId!=='xpdoufauvrbdmxgngetv' || review.bundleSha256!=='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b'
    || ['tenantId','entityId','branchId'].some(key=>approved?.[key]!==FINANCE_SCOPE[key])) throw Error('EXACT_REVIEWED_FINANCE_SCOPE_REQUIRED');
  if (FINANCE_COUNTS.journals>FIXTURE_CAPS.perTenant.postedJournals || FINANCE_COUNTS.journalLines>FIXTURE_CAPS.perTenant.journalLines
    || FINANCE_COUNTS.openItems>FIXTURE_CAPS.perTenant.openItems || Object.entries(FIXTURE_CAPS.runtimeOnly).some(([key,cap])=>FINANCE_COUNTS[key]>cap))
    throw Error('APPROVED_FINANCE_FIXTURE_CAP_REQUIRED');
  if (FINANCE_JOURNALS.some(j=>!isUuid(j.id)||j.debit===j.credit||!/^\d+\.\d{6}$/.test(j.amount))) throw Error('EXACT_BALANCED_FIXTURE_REQUIRED');
  return immutableJson({scope:FINANCE_SCOPE,calendar:FINANCE_CALENDAR,counts:FINANCE_COUNTS,expected:FINANCE_EXPECTED,
    administrativeSourceFixture:true,userJournalPostingProved:false,operationalPayrollApprovalProved:false,
    incidentalNewCrmParties:2,existingCrmRowsModified:false,permissionMutation:false,authMutation:false,existingRowsModified:false});
}

export function financeFixtureSql({commit=false}={}) {
  if (typeof commit!=='boolean') throw Error('EXACT_FINANCE_TRANSACTION_MODE_REQUIRED');
  const accountValues=FINANCE_ACCOUNTS.map(a=>`(${q(a.id)}::uuid,t,e,${q('W5SYN-'+a.key.toUpperCase())},${q('Synthetic admin fixture '+a.key)},${q(a.type)},${q(a.normal)},actor,actor)`).join(',\n');
  const journalValues=FINANCE_JOURNALS.map(j=>`(${q(j.id)}::uuid,${q(j.key)},${q(j.debit)}::uuid,${q(j.credit)}::uuid,${q(j.amount)}::numeric,${q(j.date)}::date)`).join(',\n');
  return `-- Exact r5 runtime finance administration fixture. No user posting/approval claim.
-- All source labels are synthetic; existing CRM, roles, receipts and Auth remain unchanged.
-- Unknown outcome: inspect exact IDs read-only; do not rerun or pick replacement IDs.
BEGIN;
DO $fixture$
DECLARE t uuid:=${q(tenantId)}; e uuid:=${q(entityId)}; b uuid:=${q(branchId)}; actor uuid:=${q(FINANCE_ACTOR)};
 r record; name text; before_hashes jsonb:='{}'; after_hash text; guard_hash text; guard_after text;
 basis jsonb:=jsonb_build_object('kind','synthetic_admin_finance_fixture','revision',1,'day',${q(FINANCE_CALENDAR.fixtureDay)},'userPosting',false,'operationalApproval',false);
 fixture_digest text; n bigint;
BEGIN
 IF (statement_timestamp() AT TIME ZONE 'UTC')::date<>${q(FINANCE_CALENDAR.fixtureDay)}::date THEN RAISE EXCEPTION 'EXACT_FINANCE_FIXTURE_DAY_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('jentra.w5.finance.fixture.'||t::text,513));
 IF NOT EXISTS(SELECT 1 FROM core.branches WHERE tenant_id=t AND legal_entity_id=e AND id=b AND status='active')
 OR NOT EXISTS(SELECT 1 FROM core.legal_entities WHERE tenant_id=t AND id=e AND currency_code='LKR')
 OR NOT EXISTS(SELECT 1 FROM core.memberships WHERE tenant_id=t AND user_id=actor AND status='active') THEN RAISE EXCEPTION 'EXACT_BOOTSTRAPPED_FINANCE_SCOPE_REQUIRED'; END IF;
 FOREACH name IN ARRAY ARRAY[${tables.map(q).join(',')}] LOOP
  EXECUTE format('SELECT count(*) FROM %s WHERE tenant_id=$1',name) INTO n USING t;
  IF n<>0 THEN RAISE EXCEPTION 'FINANCE_FIXTURE_COLLISION_INSPECT_ORIGINAL_IDS'; END IF;
  EXECUTE format('SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]'')::text,''sha256''),''hex'') FROM %s x WHERE tenant_id<>$1',name) INTO after_hash USING t;
  before_hashes:=jsonb_set(before_hashes,ARRAY[name],to_jsonb(after_hash));
 END LOOP;
 SELECT encode(extensions.digest(jsonb_build_object('roles',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM core.roles x WHERE tenant_id=t),
  'permissions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY role_id,permission_code),'[]') FROM core.role_permissions x WHERE tenant_id=t),
  'assignments',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM core.role_assignments x WHERE tenant_id=t),
  'crm',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM crm.opportunities x WHERE tenant_id=t),
  'process',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM workflow.process_events x WHERE tenant_id=t))::text,'sha256'),'hex') INTO guard_hash;
 fixture_digest:=encode(extensions.digest(basis::text,'sha256'),'hex');
 INSERT INTO crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by,source_context)
 VALUES(${uid('party.customer')},t,'W5SYN-CUSTOMER','Synthetic admin fixture customer','Synthetic admin fixture customer','customer',actor,actor,basis),
  (${uid('party.supplier')},t,'W5SYN-SUPPLIER','Synthetic admin fixture supplier','Synthetic admin fixture supplier','supplier',actor,actor,basis);
 INSERT INTO finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by) VALUES
 ${accountValues};
 INSERT INTO finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 VALUES(${uid('period')},t,e,'Synthetic admin finance fixture October 2026','2026-10-01','2026-10-31',actor,actor);
 INSERT INTO finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
 VALUES(${uid('bank')},t,e,b,'W5SYN-BANK','Synthetic admin cash source','bank',${uid('account.bank')},'LKR',actor,actor);
 FOR r IN SELECT * FROM (VALUES ${journalValues}) v(id,label,debit,credit,amount,posting_date) LOOP
  INSERT INTO finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,posting_date,source_type,source_id,
   currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
  VALUES(r.id,t,e,b,${uid('period')},'W5SYN-FIN-'||r.label,r.posting_date,'w5_synthetic_admin_fixture',r.id,'LKR','LKR',1,r.id,r.id,r.id,actor);
  INSERT INTO finance.journal_lines(id,tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,currency_code,
   transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
  VALUES((md5(r.id::text||'.debit'))::uuid,t,e,b,r.id,1,r.debit,'LKR',r.amount,0,r.amount,0,r.posting_date,actor),
   ((md5(r.id::text||'.credit'))::uuid,t,e,b,r.id,2,r.credit,'LKR',0,r.amount,0,r.amount,r.posting_date,actor);
  UPDATE finance.journal_entries SET status='posted' WHERE tenant_id=t AND id=r.id AND status='draft';
 END LOOP;
 INSERT INTO finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,
  base_currency_code,exchange_rate,original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 VALUES(${uid('open.ar')},t,e,b,'AR',${uid('party.customer')},'w5_synthetic_admin_ar',${uid('open.ar')},'W5SYN-AR','LKR','LKR',1,3000.000001,3000.000001,
  '2026-10-09','2026-10-16',${uid('journal.revenue')},${uid('open.ar')},${uid('open.ar')},${uid('open.ar')},actor),
  (${uid('open.ap')},t,e,b,'AP',${uid('party.supplier')},'w5_synthetic_admin_ap',${uid('open.ap')},'W5SYN-AP','LKR','LKR',1,1200.000002,1200.000002,
  '2026-10-09','2026-10-16',${uid('journal.cost')},${uid('open.ap')},${uid('open.ap')},${uid('open.ap')},actor);
 INSERT INTO people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by)
 VALUES(${uid('employee')},t,e,'W5SYN-EMPLOYEE','Synthetic admin source employee',actor,actor);
 INSERT INTO people_payroll.settings_versions(id,tenant_id,legal_entity_id,version,net_account_id,reason,published_by)
 VALUES(${uid('payroll.settings')},t,e,1,${uid('account.payroll')},'Synthetic administration fixture; no operational payroll approval',actor);
 INSERT INTO people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,status,posted_journal_id,created_by)
 VALUES(${uid('payroll.run')},t,e,b,'Synthetic admin-issued source fixture','2026-10-01','2026-10-09','2026-10-09','LKR','posted',${uid('journal.payroll')},actor);
 INSERT INTO people_payroll.run_employees(tenant_id,legal_entity_id,branch_id,run_id,employee_id)
 VALUES(t,e,b,${uid('payroll.run')},${uid('employee')});
 INSERT INTO people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
 VALUES(${uid('payroll.revision')},t,e,${uid('payroll.run')},1,${uid('payroll.settings')},fixture_digest,1,actor);
 UPDATE people_payroll.runs SET current_revision_id=${uid('payroll.revision')} WHERE tenant_id=t AND id=${uid('payroll.run')};
 INSERT INTO people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
 VALUES(${uid('payroll.calculation')},t,e,${uid('payroll.run')},${uid('payroll.revision')},${uid('employee')},basis,fixture_digest,
  jsonb_build_object('fixture',true,'gross','10.000001','deductions','0.000000','net','10.000001','operationalApproval',false),10.000001,0,0,10.000001);
 INSERT INTO people_payroll.obligations(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,kind,account_id,currency_code,amount)
 VALUES(${uid('payroll.obligation')},t,e,b,${uid('payroll.run')},${uid('employee')},${uid('payroll.calculation')},'net',${uid('account.payroll')},'LKR',10.000001);
 INSERT INTO people_payroll.obligation_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,recorded_by)
 VALUES(${uid('payroll.issue')},t,e,${uid('payroll.obligation')},'issue',10.000001,${uid('payroll.run')},actor);
 INSERT INTO people_payroll.settlements(id,tenant_id,legal_entity_id,branch_id,run_id,posting_date,bank_id,bank_account_id,currency_code,bank_version,
  evidence_reference,reason,status,journal_id,reversal_journal_id,recorded_by)
 VALUES(${uid('payroll.settlement')},t,e,b,${uid('payroll.run')},'2026-10-11',${uid('bank')},${uid('account.bank')},'LKR',1,'W5SYN-PARTIAL',
  'Synthetic admin partial settlement with future effective reversal','reversed',${uid('journal.settlement')},${uid('journal.future-reversal')},actor);
 INSERT INTO people_payroll.settlement_allocations(tenant_id,legal_entity_id,settlement_id,obligation_id,amount)
 VALUES(t,e,${uid('payroll.settlement')},${uid('payroll.obligation')},3.000000);
 INSERT INTO people_payroll.obligation_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,reversal_of,recorded_by)
 VALUES(${uid('payroll.settle-effect')},t,e,${uid('payroll.obligation')},'settle',-3,${uid('payroll.settlement')},null,actor),
  (${uid('payroll.reverse-effect')},t,e,${uid('payroll.obligation')},'settlement_reverse',3,${uid('payroll.settlement')},${uid('payroll.settle-effect')},actor);
 INSERT INTO people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,chain_version,
  posting_date,currency_code,status,digest,before_calculation,after_calculation,difference,prepared_by,posted_journal_id,reason)
 VALUES(${uid('payroll.correction')},t,e,b,${uid('payroll.calculation')},${uid('employee')},${uid('payroll.run')},0,'2026-10-09','LKR','posted',fixture_digest,
  basis,basis,jsonb_build_object('syntheticRecovery','-2.000002','operationalApproval',false),actor,${uid('journal.recovery')},'Synthetic administration recovery fixture; no operational approval');
 INSERT INTO people_payroll.correction_balances(id,tenant_id,legal_entity_id,branch_id,correction_id,employee_id,kind,account_id,currency_code,amount)
 VALUES(${uid('payroll.recovery')},t,e,b,${uid('payroll.correction')},${uid('employee')},'net',${uid('account.payroll')},'LKR',-2.000002);
 INSERT INTO people_payroll.correction_balance_effects(id,tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by)
 VALUES(${uid('payroll.recovery-effect')},t,e,${uid('payroll.recovery')},'issue',-2.000002,${uid('payroll.correction')},actor);
 INSERT INTO projects.register(id,tenant_id,legal_entity_id,branch_id,code,name,manager_id,currency_code,precision,start_date,end_date_exclusive,created_by)
 VALUES(${uid('project')},t,e,b,'W5SYN-PROJECT','Synthetic admin reimbursement source',${uid('employee')},'LKR',6,'2026-10-01','2026-10-31',actor);
 INSERT INTO projects.expenses(id,tenant_id,legal_entity_id,branch_id,project_id,employee_id,current_revision_id,status,external_reference,created_by)
 VALUES(${uid('expense')},t,e,b,${uid('project')},${uid('employee')},${uid('expense.revision')},'posted','W5SYN-EXPENSE',actor);
 INSERT INTO projects.expense_revisions(id,tenant_id,legal_entity_id,project_id,expense_id,version,service_date,purpose,evidence_reference,
  original_currency,base_currency,original_precision,base_precision,net,tax,gross,base_net,base_tax,base_gross,tax_rounding_residue,tax_basis,
  no_tax_reason,fx_numerator,fx_denominator,fx_basis,expense_account_id,liability_account_id,bill_amount,billable,digest,reason,recorded_by)
 VALUES(${uid('expense.revision')},t,e,${uid('project')},${uid('expense')},1,'2026-10-09','Synthetic admin fixture','W5SYN-RECEIPT',
  'LKR','LKR',6,6,4.000004,0,4.000004,4.000004,0,4.000004,0,basis,'Synthetic fixture; no statutory tax calculation',1,1,basis,
  ${uid('account.expense')},${uid('account.reimbursement')},0,false,fixture_digest,'Synthetic administration fixture; no operational approval',actor);
 INSERT INTO projects.reimbursements(id,tenant_id,legal_entity_id,branch_id,project_id,expense_id,revision_id,currency_code,amount,account_id,posting_date,journal_id,recorded_by)
 VALUES(${uid('reimbursement')},t,e,b,${uid('project')},${uid('expense')},${uid('expense.revision')},'LKR',4.000004,${uid('account.reimbursement')},'2026-10-09',${uid('journal.reimbursement')},actor);
 INSERT INTO projects.reimbursement_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,recorded_by)
 VALUES(${uid('reimbursement.issue')},t,e,${uid('reimbursement')},'issue',4.000004,${uid('expense')},${uid('journal.reimbursement')},'2026-10-09',actor);
 SET CONSTRAINTS ALL IMMEDIATE;
 IF (SELECT count(*) FROM finance.journal_entries WHERE tenant_id=t)<>9 OR (SELECT count(*) FROM finance.journal_lines WHERE tenant_id=t)<>18
 OR (SELECT count(*) FROM crm.parties WHERE tenant_id=t)<>2 OR (SELECT count(*) FROM finance.open_items WHERE tenant_id=t)<>2
 OR (SELECT count(*) FROM people_payroll.obligations WHERE tenant_id=t)<>1 OR (SELECT count(*) FROM people_payroll.correction_balances WHERE tenant_id=t)<>1
 OR (SELECT count(*) FROM projects.reimbursements WHERE tenant_id=t)<>1 THEN RAISE EXCEPTION 'EXACT_FINANCE_FIXTURE_COUNT_REQUIRED'; END IF;
 FOREACH name IN ARRAY ARRAY[${tables.map(q).join(',')}] LOOP
  EXECUTE format('SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]'')::text,''sha256''),''hex'') FROM %s x WHERE tenant_id<>$1',name) INTO after_hash USING t;
  IF before_hashes->>name IS DISTINCT FROM after_hash THEN RAISE EXCEPTION 'PROTECTED_OUTSIDE_FINANCE_SCOPE_CHANGED'; END IF;
 END LOOP;
 SELECT encode(extensions.digest(jsonb_build_object('roles',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM core.roles x WHERE tenant_id=t),
  'permissions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY role_id,permission_code),'[]') FROM core.role_permissions x WHERE tenant_id=t),
  'assignments',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM core.role_assignments x WHERE tenant_id=t),
  'crm',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM crm.opportunities x WHERE tenant_id=t),
  'process',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM workflow.process_events x WHERE tenant_id=t))::text,'sha256'),'hex') INTO guard_after;
 IF guard_hash IS DISTINCT FROM guard_after THEN RAISE EXCEPTION 'FINANCE_FIXTURE_AUTHORITY_OR_CRM_CHANGED'; END IF;
END $fixture$;
${commit?'COMMIT;':'ROLLBACK;'}
`;
}

export function financeFixtureDigest(mode={}) { return hashBytes(financeFixtureSql(mode)); }
