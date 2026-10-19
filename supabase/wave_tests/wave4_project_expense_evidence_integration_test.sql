-- Actual candidate expense commands consume verified private provider proofs.
-- Every fixture row and trusted worker simulation is inside the outer rollback.
reset role;select pg_temp.wactor('creator');
create temporary table finance_evidence_samples(label text primary key,body jsonb);
grant insert,select on finance_evidence_samples to authenticated,service_role;
create function pg_temp.fe_command(a text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('fe.document'),'project_id',pg_temp.wid('finance'),'expense_id',pg_temp.wid('pf.attached')) $$;
create function pg_temp.fe_reserve() returns jsonb language sql as $$
 select pg_temp.fe_command('reserve')||jsonb_build_object('mime','text/plain','byte_size',14,'checksum',repeat('f',64),'purpose','Synthetic attached receipt') $$;
create function pg_temp.fe_create() returns jsonb language sql as $$
 select pg_temp.pfe('attached')||jsonb_build_object('billable',false,'bill_amount','0','evidence_documents',(select body from finance_evidence_samples where label='proof')) $$;
set local role authenticated;
select pg_temp.eec(pg_temp.fe_reserve(),0,'fe.reserve');
insert into finance_evidence_samples values('ticket',api.projects_expense_evidence_ticket(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.attached'),pg_temp.wid('fe.document'),'upload'));
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from finance_evidence_samples where label='ticket'),pg_temp.wid('creator'));
select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from finance_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('f',64),14);
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into finance_evidence_samples values('active',pg_temp.eec(pg_temp.fe_command('complete'),1,'fe.complete'));
insert into finance_evidence_samples select 'proof',jsonb_build_array((body->'entity')-array['tenant_id','legal_entity_id','branch_id','record_version','status','project_id','expense_id','action']) from finance_evidence_samples where label='active';
select is(api.projects_finance_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'projects.expenses.manage')->>'attachments_available','true','FR426 finance advertises only currently authorized ready evidence provider');
select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('evidence_documents',(select jsonb_build_array((body->0)||'{"version":2}') from finance_evidence_samples where label='proof')),0,'fe.invalid-version')$$,
 '22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 expense rejects lifecycle version as immutable content proof');
select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('evidence_documents',(select jsonb_build_array((body->0)||jsonb_build_object('digest',repeat('0',64))) from finance_evidence_samples where label='proof')),0,'fe.invalid-digest')$$,
 '40001','EXPENSE_EVIDENCE_CONFLICT','FR426 expense cannot freeze a caller-invented digest');
select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('id',pg_temp.wid('pf.different-evidence')),0,'fe.foreign')$$,
 '40001','EXPENSE_EVIDENCE_CONFLICT','FR426 expense cannot borrow another expense document');
insert into finance_evidence_samples values('created',pg_temp.pfc(pg_temp.fe_create(),0,'fe.create'));
select is(pg_temp.pfc(pg_temp.fe_create(),0,'fe.create'),(select body from finance_evidence_samples where label='created'),'FR426 verified attached expense has immutable exact replay');
insert into project_finance_client_samples values('attachedExpenses',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses',null,pg_temp.wid('pf.attached')));
reset role;
select is((select evidence_documents from projects.expense_revisions where expense_id=pg_temp.wid('pf.attached')),(select body from finance_evidence_samples where label='proof'),'FR426 immutable revision freezes canonical provider proof');
select ok((select digest=encode(extensions.digest(convert_to(((pg_temp.fe_create()-array['action','reason'])||jsonb_build_object('evidence_documents',evidence_documents))::text,'UTF8'),'sha256'),'hex') from projects.expense_revisions where expense_id=pg_temp.wid('pf.attached')),'FR426 revision digest binds actual canonical evidence');
select throws_ok($$update projects.expense_revisions set evidence_documents='[]' where expense_id=pg_temp.wid('pf.attached')$$,'55000','PROJECT_HISTORY_IMMUTABLE','FR426 original attached revision cannot lose evidence');
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('creator.role') and permission_code='projects.expenses.evidence.view';
set local role authenticated;
select throws_ok($$select pg_temp.pfc(pg_temp.fe_create(),0,'fe.create')$$,'42501',null,'FR426 attachment authority checked before confirmed expense replay');
select throws_ok($$select api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses',null,pg_temp.wid('pf.attached'))$$,'42501',null,'FR426 private expense projection rechecks attachment view');
select throws_ok($$select api.projects_finance_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.command.fe.create'),'expense_create')$$,'42501',null,'FR426 own receipt cannot bypass original attachment authority');
select is(api.projects_finance_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'projects.expenses.manage')->>'attachments_available','false','FR426 attachment denial stays explicit without denying operational financial authority');
select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('action','expense_correct','evidence_documents','[]'::jsonb),1,'fe.detach')$$,'42501',null,'FR426 correction cannot erase original evidence to bypass revoked attachment access');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.expenses.evidence.view');
update expense_private.worker_readiness set verified_at=now()-interval '27 hours';
set local role authenticated;
select is(api.projects_finance_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'projects.expenses.manage')->>'attachments_available','false','FR426 stale worker is explicit in financial provider availability');
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_submit','attached'),1,'fe.submit')$$,'55000','EXPENSE_RETENTION_WORKER_UNAVAILABLE','FR426 submitted expense requires current evidence worker');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_register(repeat('a',64),repeat('b',64));
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pfc(pg_temp.pfa('expense_submit','attached'),1,'fe.submit');
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_approve','attached'),2,'fe.self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','FR426 attached evidence preserves independent expense approval');
select pg_temp.wactor('reviewer');
insert into finance_evidence_samples values('approved',pg_temp.pfc(pg_temp.pfa('expense_approve','attached'),2,'fe.approve'));
reset role;
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('reviewer.role') and permission_code='projects.expenses.evidence.view';
set local role authenticated;
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_approve','attached'),2,'fe.approve')$$,'42501',null,'FR426 independent confirmed approval replay rechecks original proof access');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reviewer.role'),'projects.expenses.evidence.view');
set local role authenticated;
insert into finance_evidence_samples values('posted',pg_temp.pfc(pg_temp.pfa('expense_post','attached'),3,'fe.post'));
reset role;
select is((select amount from projects.reimbursements where expense_id=pg_temp.wid('pf.attached')),0.03::numeric,'FR426 evidence attachment keeps exact original journal obligation');
select ok(not exists(select 1 from core.command_receipts where command_id in(pg_temp.wid('pf.command.fe.create'),pg_temp.wid('pf.command.fe.approve'),pg_temp.wid('pf.command.fe.post')) and response::text~'evidence_documents|object_path|checksum|Synthetic attached receipt'),'FR426 generic financial confirmation excludes private attachment metadata');
update expense_private.worker_readiness set verified_at=now()-interval '27 hours';
set local role authenticated;
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_post','attached'),3,'fe.post')$$,'55000','EXPENSE_RETENTION_WORKER_UNAVAILABLE','FR426 confirmed journal post replay rechecks live worker readiness');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_register(repeat('a',64),repeat('b',64));
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pfc(pg_temp.pfa('expense_reverse','attached'),4,'fe.reverse');
select pg_temp.eec(pg_temp.fe_command('retire')||'{"reason":"Synthetic financial reversal retention"}',2,'fe.retire');
select is(api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses',null,pg_temp.wid('pf.attached'))->'rows'->0->'evidence_documents',(select body from finance_evidence_samples where label='proof'),'FR426 retired bytes retain original immutable expense proof history');
select is(api.projects_finance_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.command.fe.post'),'expense_post'),(select body from finance_evidence_samples where label='posted'),'FR426 original actor can reconcile historical confirmed post after retirement');
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_post','attached'),3,'fe.post')$$,'55000','EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE','FR426 retired content cannot authorize confirmed financial decision replay');
reset role;
