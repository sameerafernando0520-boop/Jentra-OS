-- Exact r5 runtime finance administration fixture. No user posting/approval claim.
-- All source labels are synthetic; existing CRM, roles, receipts and Auth remain unchanged.
-- Unknown outcome: inspect exact IDs read-only; do not rerun or pick replacement IDs.
BEGIN;
DO $fixture$
DECLARE t uuid:='babe6c86-a764-4d3a-80a3-952a7c096c2c'; e uuid:='caa2bb06-219a-47e9-8132-66d1271b0ffd'; b uuid:='3813692c-f0de-4c69-8e34-d56cf54695b1'; actor uuid:='8b740ab8-24f7-4455-a78b-aea0d99d20f6';
 r record; name text; before_hashes jsonb:='{}'; after_hash text; guard_hash text; guard_after text;
 basis jsonb:=jsonb_build_object('kind','synthetic_admin_finance_fixture','revision',1,'day','2026-10-13','userPosting',false,'operationalApproval',false);
 fixture_digest text; n bigint;
BEGIN
 IF (statement_timestamp() AT TIME ZONE 'UTC')::date<>'2026-10-13'::date THEN RAISE EXCEPTION 'EXACT_FINANCE_FIXTURE_DAY_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('jentra.w5.finance.fixture.'||t::text,513));
 IF NOT EXISTS(SELECT 1 FROM core.branches WHERE tenant_id=t AND legal_entity_id=e AND id=b AND status='active')
 OR NOT EXISTS(SELECT 1 FROM core.legal_entities WHERE tenant_id=t AND id=e AND currency_code='LKR')
 OR NOT EXISTS(SELECT 1 FROM core.memberships WHERE tenant_id=t AND user_id=actor AND status='active') THEN RAISE EXCEPTION 'EXACT_BOOTSTRAPPED_FINANCE_SCOPE_REQUIRED'; END IF;
 FOREACH name IN ARRAY ARRAY['crm.parties','finance.accounts','finance.fiscal_periods','finance.journal_entries','finance.journal_lines','finance.cash_bank_accounts','finance.open_items','people.employees','people_payroll.settings_versions','people_payroll.runs','people_payroll.run_employees','people_payroll.run_revisions','people_payroll.employee_calculations','people_payroll.obligations','people_payroll.obligation_effects','people_payroll.settlements','people_payroll.settlement_allocations','people_payroll.corrections','people_payroll.correction_balances','people_payroll.correction_balance_effects','projects.register','projects.expenses','projects.expense_revisions','projects.reimbursements','projects.reimbursement_effects'] LOOP
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
 VALUES('7c66db03-4be6-35f9-dd57-a86744908fef'::uuid,t,'W5SYN-CUSTOMER','Synthetic admin fixture customer','Synthetic admin fixture customer','customer',actor,actor,basis),
  ('b8f2ccf5-e132-c982-ab79-88720c59de8f'::uuid,t,'W5SYN-SUPPLIER','Synthetic admin fixture supplier','Synthetic admin fixture supplier','supplier',actor,actor,basis);
 INSERT INTO finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by) VALUES
 ('0390289d-fbd0-adbf-5e57-2790c3da06e9'::uuid,t,e,'W5SYN-BANK','Synthetic admin fixture bank','asset','debit',actor,actor),
('6a27969f-5fdb-f9ba-4fda-e91ceaeb59a4'::uuid,t,e,'W5SYN-INVENTORY','Synthetic admin fixture inventory','asset','debit',actor,actor),
('694a79b3-7cad-ac20-0e33-4349c25b9fa3'::uuid,t,e,'W5SYN-RECEIVABLE','Synthetic admin fixture receivable','asset','debit',actor,actor),
('f8608d9c-66e9-51fc-8b62-17f9afd816da'::uuid,t,e,'W5SYN-PAYABLE','Synthetic admin fixture payable','liability','credit',actor,actor),
('c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,t,e,'W5SYN-PAYROLL','Synthetic admin fixture payroll','liability','credit',actor,actor),
('a8ab8e1d-0d16-b2a6-15ec-7c4f4b1f9120'::uuid,t,e,'W5SYN-REIMBURSEMENT','Synthetic admin fixture reimbursement','liability','credit',actor,actor),
('6616b546-18c8-7b13-85e6-b633980f5e3e'::uuid,t,e,'W5SYN-EQUITY','Synthetic admin fixture equity','equity','credit',actor,actor),
('06170b3f-268d-9299-5d6e-f60efd1741b3'::uuid,t,e,'W5SYN-REVENUE','Synthetic admin fixture revenue','revenue','credit',actor,actor),
('d33b0770-ca66-1f95-a30c-006ac18cab28'::uuid,t,e,'W5SYN-COST','Synthetic admin fixture cost','expense','debit',actor,actor),
('c13d84fd-a9ab-b146-ecb7-ed3686bb922c'::uuid,t,e,'W5SYN-EXPENSE','Synthetic admin fixture expense','expense','debit',actor,actor);
 INSERT INTO finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 VALUES('227927b0-17ef-195b-2887-791afbc06a13'::uuid,t,e,'Synthetic admin finance fixture October 2026','2026-10-01','2026-10-31',actor,actor);
 INSERT INTO finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
 VALUES('0b800db6-5b63-9e32-3f2e-08219bbe1795'::uuid,t,e,b,'W5SYN-BANK','Synthetic admin cash source','bank','0390289d-fbd0-adbf-5e57-2790c3da06e9'::uuid,'LKR',actor,actor);
 FOR r IN SELECT * FROM (VALUES ('22ef9e30-c9e6-6097-ec2a-afc0692ae925'::uuid,'capital','0390289d-fbd0-adbf-5e57-2790c3da06e9'::uuid,'6616b546-18c8-7b13-85e6-b633980f5e3e'::uuid,'100000.000001'::numeric,'2026-10-09'::date),
('b5b03448-e75a-78f1-9864-3f731bc85875'::uuid,'stock','6a27969f-5fdb-f9ba-4fda-e91ceaeb59a4'::uuid,'6616b546-18c8-7b13-85e6-b633980f5e3e'::uuid,'1000.000001'::numeric,'2026-10-09'::date),
('6c971524-dc53-69d8-3fb0-1075390c6ae8'::uuid,'revenue','694a79b3-7cad-ac20-0e33-4349c25b9fa3'::uuid,'06170b3f-268d-9299-5d6e-f60efd1741b3'::uuid,'3000.000001'::numeric,'2026-10-09'::date),
('2005a0cb-8457-03a0-7ee7-99a0d7bfa2aa'::uuid,'cost','d33b0770-ca66-1f95-a30c-006ac18cab28'::uuid,'f8608d9c-66e9-51fc-8b62-17f9afd816da'::uuid,'1200.000002'::numeric,'2026-10-09'::date),
('dba4fef5-665d-1d1d-7dce-850bac3ea5db'::uuid,'payroll','c13d84fd-a9ab-b146-ecb7-ed3686bb922c'::uuid,'c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'10.000001'::numeric,'2026-10-09'::date),
('2ba4fff3-6c1b-87da-374a-2e2be34b5156'::uuid,'recovery','c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'c13d84fd-a9ab-b146-ecb7-ed3686bb922c'::uuid,'2.000002'::numeric,'2026-10-09'::date),
('c606a99a-96e8-1805-db2b-acab30a0c7f9'::uuid,'reimbursement','c13d84fd-a9ab-b146-ecb7-ed3686bb922c'::uuid,'a8ab8e1d-0d16-b2a6-15ec-7c4f4b1f9120'::uuid,'4.000004'::numeric,'2026-10-09'::date),
('0a70c270-3901-a7b0-994b-1199cfe05244'::uuid,'settlement','c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'0390289d-fbd0-adbf-5e57-2790c3da06e9'::uuid,'3.000000'::numeric,'2026-10-11'::date),
('905e182c-3a5e-75f0-1f11-786cb48a103e'::uuid,'future-reversal','0390289d-fbd0-adbf-5e57-2790c3da06e9'::uuid,'c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'3.000000'::numeric,'2026-10-14'::date)) v(id,label,debit,credit,amount,posting_date) LOOP
  INSERT INTO finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,posting_date,source_type,source_id,
   currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
  VALUES(r.id,t,e,b,'227927b0-17ef-195b-2887-791afbc06a13'::uuid,'W5SYN-FIN-'||r.label,r.posting_date,'w5_synthetic_admin_fixture',r.id,'LKR','LKR',1,r.id,r.id,r.id,actor);
  INSERT INTO finance.journal_lines(id,tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,currency_code,
   transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
  VALUES((md5(r.id::text||'.debit'))::uuid,t,e,b,r.id,1,r.debit,'LKR',r.amount,0,r.amount,0,r.posting_date,actor),
   ((md5(r.id::text||'.credit'))::uuid,t,e,b,r.id,2,r.credit,'LKR',0,r.amount,0,r.amount,r.posting_date,actor);
  UPDATE finance.journal_entries SET status='posted' WHERE tenant_id=t AND id=r.id AND status='draft';
 END LOOP;
 INSERT INTO finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,
  base_currency_code,exchange_rate,original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 VALUES('899371bd-35e5-d2d2-e265-f8823c41b240'::uuid,t,e,b,'AR','7c66db03-4be6-35f9-dd57-a86744908fef'::uuid,'w5_synthetic_admin_ar','899371bd-35e5-d2d2-e265-f8823c41b240'::uuid,'W5SYN-AR','LKR','LKR',1,3000.000001,3000.000001,
  '2026-10-09','2026-10-16','6c971524-dc53-69d8-3fb0-1075390c6ae8'::uuid,'899371bd-35e5-d2d2-e265-f8823c41b240'::uuid,'899371bd-35e5-d2d2-e265-f8823c41b240'::uuid,'899371bd-35e5-d2d2-e265-f8823c41b240'::uuid,actor),
  ('8502cb88-aa85-bbb4-4c55-e2286a459807'::uuid,t,e,b,'AP','b8f2ccf5-e132-c982-ab79-88720c59de8f'::uuid,'w5_synthetic_admin_ap','8502cb88-aa85-bbb4-4c55-e2286a459807'::uuid,'W5SYN-AP','LKR','LKR',1,1200.000002,1200.000002,
  '2026-10-09','2026-10-16','2005a0cb-8457-03a0-7ee7-99a0d7bfa2aa'::uuid,'8502cb88-aa85-bbb4-4c55-e2286a459807'::uuid,'8502cb88-aa85-bbb4-4c55-e2286a459807'::uuid,'8502cb88-aa85-bbb4-4c55-e2286a459807'::uuid,actor);
 INSERT INTO people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by)
 VALUES('685a1074-c086-3008-310d-e700cef1698c'::uuid,t,e,'W5SYN-EMPLOYEE','Synthetic admin source employee',actor,actor);
 INSERT INTO people_payroll.settings_versions(id,tenant_id,legal_entity_id,version,net_account_id,reason,published_by)
 VALUES('d93d3cda-dbcb-cc07-a753-a86a3e749113'::uuid,t,e,1,'c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'Synthetic administration fixture; no operational payroll approval',actor);
 INSERT INTO people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,status,posted_journal_id,created_by)
 VALUES('a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,t,e,b,'Synthetic admin-issued source fixture','2026-10-01','2026-10-09','2026-10-09','LKR','posted','dba4fef5-665d-1d1d-7dce-850bac3ea5db'::uuid,actor);
 INSERT INTO people_payroll.run_employees(tenant_id,legal_entity_id,branch_id,run_id,employee_id)
 VALUES(t,e,b,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,'685a1074-c086-3008-310d-e700cef1698c'::uuid);
 INSERT INTO people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
 VALUES('042beade-21b2-0f2d-db3e-8cc8df571674'::uuid,t,e,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,1,'d93d3cda-dbcb-cc07-a753-a86a3e749113'::uuid,fixture_digest,1,actor);
 UPDATE people_payroll.runs SET current_revision_id='042beade-21b2-0f2d-db3e-8cc8df571674'::uuid WHERE tenant_id=t AND id='a0a08806-438d-9f35-190d-c7b34c98304d'::uuid;
 INSERT INTO people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
 VALUES('271214b6-5f4a-640c-3f9d-694d4e2f03c3'::uuid,t,e,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,'042beade-21b2-0f2d-db3e-8cc8df571674'::uuid,'685a1074-c086-3008-310d-e700cef1698c'::uuid,basis,fixture_digest,
  jsonb_build_object('fixture',true,'gross','10.000001','deductions','0.000000','net','10.000001','operationalApproval',false),10.000001,0,0,10.000001);
 INSERT INTO people_payroll.obligations(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,kind,account_id,currency_code,amount)
 VALUES('65f5bde8-5cee-4ce0-f592-585cd454bd5c'::uuid,t,e,b,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,'685a1074-c086-3008-310d-e700cef1698c'::uuid,'271214b6-5f4a-640c-3f9d-694d4e2f03c3'::uuid,'net','c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'LKR',10.000001);
 INSERT INTO people_payroll.obligation_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,recorded_by)
 VALUES('af91eac1-2250-7dec-9c09-05d6ad8ecd07'::uuid,t,e,'65f5bde8-5cee-4ce0-f592-585cd454bd5c'::uuid,'issue',10.000001,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,actor);
 INSERT INTO people_payroll.settlements(id,tenant_id,legal_entity_id,branch_id,run_id,posting_date,bank_id,bank_account_id,currency_code,bank_version,
  evidence_reference,reason,status,journal_id,reversal_journal_id,recorded_by)
 VALUES('61ede12f-09b8-9119-235a-589d910a38aa'::uuid,t,e,b,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,'2026-10-11','0b800db6-5b63-9e32-3f2e-08219bbe1795'::uuid,'0390289d-fbd0-adbf-5e57-2790c3da06e9'::uuid,'LKR',1,'W5SYN-PARTIAL',
  'Synthetic admin partial settlement with future effective reversal','reversed','0a70c270-3901-a7b0-994b-1199cfe05244'::uuid,'905e182c-3a5e-75f0-1f11-786cb48a103e'::uuid,actor);
 INSERT INTO people_payroll.settlement_allocations(tenant_id,legal_entity_id,settlement_id,obligation_id,amount)
 VALUES(t,e,'61ede12f-09b8-9119-235a-589d910a38aa'::uuid,'65f5bde8-5cee-4ce0-f592-585cd454bd5c'::uuid,3.000000);
 INSERT INTO people_payroll.obligation_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,reversal_of,recorded_by)
 VALUES('ee5d3f5d-8af2-c99c-1f14-fa5871412414'::uuid,t,e,'65f5bde8-5cee-4ce0-f592-585cd454bd5c'::uuid,'settle',-3,'61ede12f-09b8-9119-235a-589d910a38aa'::uuid,null,actor),
  ('b4c2c88b-d59e-7a55-060b-d39f2777e79c'::uuid,t,e,'65f5bde8-5cee-4ce0-f592-585cd454bd5c'::uuid,'settlement_reverse',3,'61ede12f-09b8-9119-235a-589d910a38aa'::uuid,'ee5d3f5d-8af2-c99c-1f14-fa5871412414'::uuid,actor);
 INSERT INTO people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,chain_version,
  posting_date,currency_code,status,digest,before_calculation,after_calculation,difference,prepared_by,posted_journal_id,reason)
 VALUES('98140d77-7d5a-3919-8c13-71bec7761b8a'::uuid,t,e,b,'271214b6-5f4a-640c-3f9d-694d4e2f03c3'::uuid,'685a1074-c086-3008-310d-e700cef1698c'::uuid,'a0a08806-438d-9f35-190d-c7b34c98304d'::uuid,0,'2026-10-09','LKR','posted',fixture_digest,
  basis,basis,jsonb_build_object('syntheticRecovery','-2.000002','operationalApproval',false),actor,'2ba4fff3-6c1b-87da-374a-2e2be34b5156'::uuid,'Synthetic administration recovery fixture; no operational approval');
 INSERT INTO people_payroll.correction_balances(id,tenant_id,legal_entity_id,branch_id,correction_id,employee_id,kind,account_id,currency_code,amount)
 VALUES('051d3c5e-677e-40b6-636b-ba4730bcb4fc'::uuid,t,e,b,'98140d77-7d5a-3919-8c13-71bec7761b8a'::uuid,'685a1074-c086-3008-310d-e700cef1698c'::uuid,'net','c76a0989-9e19-3e0f-c38f-6e622d7c617b'::uuid,'LKR',-2.000002);
 INSERT INTO people_payroll.correction_balance_effects(id,tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by)
 VALUES('bc4030c2-c514-7177-8d93-18e4d70720f5'::uuid,t,e,'051d3c5e-677e-40b6-636b-ba4730bcb4fc'::uuid,'issue',-2.000002,'98140d77-7d5a-3919-8c13-71bec7761b8a'::uuid,actor);
 INSERT INTO projects.register(id,tenant_id,legal_entity_id,branch_id,code,name,manager_id,currency_code,precision,start_date,end_date_exclusive,created_by)
 VALUES('5ea9f123-fb72-c95f-97ae-b5017eaf4412'::uuid,t,e,b,'W5SYN-PROJECT','Synthetic admin reimbursement source','685a1074-c086-3008-310d-e700cef1698c'::uuid,'LKR',6,'2026-10-01','2026-10-31',actor);
 INSERT INTO projects.expenses(id,tenant_id,legal_entity_id,branch_id,project_id,employee_id,current_revision_id,status,external_reference,created_by)
 VALUES('9c5e7224-dd92-506d-2236-601d6b200fac'::uuid,t,e,b,'5ea9f123-fb72-c95f-97ae-b5017eaf4412'::uuid,'685a1074-c086-3008-310d-e700cef1698c'::uuid,'d3fa4257-6b18-2241-f40a-9a44de6307f3'::uuid,'posted','W5SYN-EXPENSE',actor);
 INSERT INTO projects.expense_revisions(id,tenant_id,legal_entity_id,project_id,expense_id,version,service_date,purpose,evidence_reference,
  original_currency,base_currency,original_precision,base_precision,net,tax,gross,base_net,base_tax,base_gross,tax_rounding_residue,tax_basis,
  no_tax_reason,fx_numerator,fx_denominator,fx_basis,expense_account_id,liability_account_id,bill_amount,billable,digest,reason,recorded_by)
 VALUES('d3fa4257-6b18-2241-f40a-9a44de6307f3'::uuid,t,e,'5ea9f123-fb72-c95f-97ae-b5017eaf4412'::uuid,'9c5e7224-dd92-506d-2236-601d6b200fac'::uuid,1,'2026-10-09','Synthetic admin fixture','W5SYN-RECEIPT',
  'LKR','LKR',6,6,4.000004,0,4.000004,4.000004,0,4.000004,0,basis,'Synthetic fixture; no statutory tax calculation',1,1,basis,
  'c13d84fd-a9ab-b146-ecb7-ed3686bb922c'::uuid,'a8ab8e1d-0d16-b2a6-15ec-7c4f4b1f9120'::uuid,0,false,fixture_digest,'Synthetic administration fixture; no operational approval',actor);
 INSERT INTO projects.reimbursements(id,tenant_id,legal_entity_id,branch_id,project_id,expense_id,revision_id,currency_code,amount,account_id,posting_date,journal_id,recorded_by)
 VALUES('5a6d135f-83ac-8fb6-6337-a4db033c895e'::uuid,t,e,b,'5ea9f123-fb72-c95f-97ae-b5017eaf4412'::uuid,'9c5e7224-dd92-506d-2236-601d6b200fac'::uuid,'d3fa4257-6b18-2241-f40a-9a44de6307f3'::uuid,'LKR',4.000004,'a8ab8e1d-0d16-b2a6-15ec-7c4f4b1f9120'::uuid,'2026-10-09','c606a99a-96e8-1805-db2b-acab30a0c7f9'::uuid,actor);
 INSERT INTO projects.reimbursement_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,recorded_by)
 VALUES('419a0487-8045-7426-b1cf-1794ac6f9d8f'::uuid,t,e,'5a6d135f-83ac-8fb6-6337-a4db033c895e'::uuid,'issue',4.000004,'9c5e7224-dd92-506d-2236-601d6b200fac'::uuid,'c606a99a-96e8-1805-db2b-acab30a0c7f9'::uuid,'2026-10-09',actor);
 SET CONSTRAINTS ALL IMMEDIATE;
 IF (SELECT count(*) FROM finance.journal_entries WHERE tenant_id=t)<>9 OR (SELECT count(*) FROM finance.journal_lines WHERE tenant_id=t)<>18
 OR (SELECT count(*) FROM crm.parties WHERE tenant_id=t)<>2 OR (SELECT count(*) FROM finance.open_items WHERE tenant_id=t)<>2
 OR (SELECT count(*) FROM people_payroll.obligations WHERE tenant_id=t)<>1 OR (SELECT count(*) FROM people_payroll.correction_balances WHERE tenant_id=t)<>1
 OR (SELECT count(*) FROM projects.reimbursements WHERE tenant_id=t)<>1 THEN RAISE EXCEPTION 'EXACT_FINANCE_FIXTURE_COUNT_REQUIRED'; END IF;
 FOREACH name IN ARRAY ARRAY['crm.parties','finance.accounts','finance.fiscal_periods','finance.journal_entries','finance.journal_lines','finance.cash_bank_accounts','finance.open_items','people.employees','people_payroll.settings_versions','people_payroll.runs','people_payroll.run_employees','people_payroll.run_revisions','people_payroll.employee_calculations','people_payroll.obligations','people_payroll.obligation_effects','people_payroll.settlements','people_payroll.settlement_allocations','people_payroll.corrections','people_payroll.correction_balances','people_payroll.correction_balance_effects','projects.register','projects.expenses','projects.expense_revisions','projects.reimbursements','projects.reimbursement_effects'] LOOP
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
ROLLBACK;
