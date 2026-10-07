-- Scoped role fixtures, inside the strict outer candidate rollback.
reset role;select pg_temp.wactor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p from unnest(array['creator','reviewer']) x
cross join unnest(array['projects.expenses.evidence.view','projects.expenses.evidence.export','projects.expenses.retention.manage']) p on conflict do nothing;
create temporary table expense_evidence_samples(label text primary key,body jsonb);
grant select,insert,update on expense_evidence_samples to authenticated,service_role;
create function pg_temp.eec(p jsonb,v bigint,k text) returns jsonb language sql as $$
 select api.projects_expense_evidence_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('ee.command.'||k),pg_temp.wid('ee.command.'||k),now(),p,v) $$;
create function pg_temp.eep(a text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('ee.document'),'project_id',pg_temp.wid('finance'),'expense_id',pg_temp.wid('pf.evidence')) $$;
create function pg_temp.eer() returns jsonb language sql as $$
 select pg_temp.eep('reserve')||jsonb_build_object('mime','text/plain','byte_size',14,'checksum',repeat('c',64),'purpose','Synthetic receipt bytes') $$;
create function pg_temp.eet(operation text) returns jsonb language sql as $$
 select api.projects_expense_evidence_ticket(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.evidence'),pg_temp.wid('ee.document'),operation) $$;
-- Simulates the owner-only integration call while retaining the current human JWT.
create function pg_temp.eef(proofs jsonb,mode text default 'freeze',expense uuid default pg_temp.wid('pf.evidence')) returns jsonb
language sql security definer set search_path='' as $$
 select projects.expense_evidence_assert(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),expense,proofs,mode) $$;
select ok(not has_table_privilege('authenticated','expense_private.documents','SELECT') and not has_table_privilege('service_role','expense_private.documents','SELECT'),
 'FR426 private evidence base rows denied to both client and trusted role');
select ok(not has_function_privilege('authenticated','projects.expense_evidence_assert(uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),
 'FR426 attachment proof helper cannot be invoked directly by clients');
select ok(not(select public from storage.buckets where id='jentra-project-expense-private'),'FR426 bucket is physically private and separate');
set local role authenticated;
select is(pg_temp.eef('[]'),'[]'::jsonb,'FR426 explicit narrative-only synthetic evidence needs no provider activation');
select is(api.projects_expense_evidence_access(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.evidence'))->>'available','false',
 'FR426 attachment availability remains gated before policy and worker');
select pg_temp.eec(jsonb_build_object('action','policy_create','id',pg_temp.wid('ee.policy'),'retention_days',30,'purpose','Explicit synthetic financial retention choice'),0,'policy');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('branch-manager.role'),p from unnest(array['projects.expenses.evidence.view','projects.expenses.retention.manage']) p on conflict do nothing;
select pg_temp.wactor('branch-manager');set local role authenticated;
select throws_ok($$select pg_temp.eec(jsonb_build_object('action','policy_create','id',pg_temp.wid('ee.branch.policy'),'retention_days',30,'purpose','Branch-only choice'),0,'branch.policy')$$,
 '42501',null,'FR426 branch-only retention manager cannot choose an entity-wide policy');
reset role;update core.role_assignments set branch_id=pg_temp.wid('branch') where tenant_id=pg_temp.wid('tenant') and membership_id=pg_temp.wid('creator.membership');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.eec(jsonb_build_object('action','policy_create','id',pg_temp.wid('ee.policy'),'retention_days',30,'purpose','Explicit synthetic financial retention choice'),0,'policy')$$,
 '42501',null,'FR426 entity policy scope is rechecked before confirmed replay');
select throws_ok($$select api.projects_expense_evidence_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('ee.command.policy'))$$,
 '42501',null,'FR426 entity policy receipt requires current entity-wide authority');
reset role;update core.role_assignments set branch_id=null where tenant_id=pg_temp.wid('tenant') and membership_id=pg_temp.wid('creator.membership');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.eec(pg_temp.eer(),0,'reserve')$$,'55000','EXPENSE_RETENTION_WORKER_UNAVAILABLE','FR426 reserve denied until storage worker proof');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_register(repeat('a',64),repeat('b',64));
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into expense_evidence_samples values('reserved',pg_temp.eec(pg_temp.eer(),0,'reserve'));
select is((select body->'entity'->>'record_version' from expense_evidence_samples where label='reserved'),'1','FR426 reservation has exact initial lifecycle version');
select is(pg_temp.eec(pg_temp.eer(),0,'reserve'),(select body from expense_evidence_samples where label='reserved'),'FR426 exact reserve replay is immutable');
select throws_ok($$select pg_temp.eec(pg_temp.eer()||'{"byte_size":15}',0,'reserve')$$,'22023','IDEMPOTENCY_MISMATCH','FR426 changed reserved bytes cannot replay');
select throws_ok($$select pg_temp.eec(pg_temp.eep('complete'),1,'complete')$$,'55000','EXPENSE_EVIDENCE_VERIFICATION_REQUIRED','FR426 unverified content cannot be attached');
insert into expense_evidence_samples values('ticket',pg_temp.eet('upload'));
insert into expense_evidence_samples values('state-ticket',pg_temp.eet('upload'));
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into expense_evidence_samples values('service',api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator')));
select is((select body->>'object_path' from expense_evidence_samples where label='service'),
 pg_temp.wid('tenant')||'/'||pg_temp.wid('entity')||'/'||pg_temp.wid('finance')||'/'||pg_temp.wid('pf.evidence')||'/'||pg_temp.wid('ee.document'),
 'FR426 trusted ticket binds every document path to its expense privacy unit');
select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 service ticket cannot be consumed twice');
reset role;update core.branches set status='inactive' where id=pg_temp.wid('branch');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='state-ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 issued ticket is denied after branch deactivation');
select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14)$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 uploaded bytes cannot verify after branch deactivation');
reset role;update core.branches set status='active' where id=pg_temp.wid('branch');update core.legal_entities set status='inactive' where id=pg_temp.wid('entity');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='state-ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 issued ticket is denied after entity deactivation');
select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14)$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 uploaded bytes cannot verify after entity deactivation');
reset role;update core.legal_entities set status='active' where id=pg_temp.wid('entity');update core.tenants set status='suspended' where id=pg_temp.wid('tenant');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='state-ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 issued ticket is denied after tenant suspension');
select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14)$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 uploaded bytes cannot verify after tenant suspension');
reset role;update core.tenants set status='active' where id=pg_temp.wid('tenant');
select is((select status from expense_private.documents where id=pg_temp.wid('ee.document')),'reserved','FR426 deactivated scope never verifies or activates bytes');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('d',64),14)$$,
 '22023','EXPENSE_EVIDENCE_BYTES_MISMATCH','FR426 verification rejects different byte checksum');
select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14);
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into expense_evidence_samples values('active',pg_temp.eec(pg_temp.eep('complete'),1,'complete'));
insert into expense_evidence_samples select 'proof',jsonb_build_array((body->'entity')-array['tenant_id','legal_entity_id','branch_id','record_version','status','project_id','expense_id','action']) from expense_evidence_samples where label='active';
select is((select body->'entity'->>'record_version' from expense_evidence_samples where label='active'),'2','FR426 verified completion advances lifecycle once');
select is(pg_temp.eef((select body from expense_evidence_samples where label='proof')),(select body from expense_evidence_samples where label='proof'),'FR426 freeze stores only canonical immutable proof');
select throws_ok($$select pg_temp.eef((select body from expense_evidence_samples where label='proof'),'freeze',pg_temp.wid('pf.other-expense'))$$,
 '40001','EXPENSE_EVIDENCE_CONFLICT','FR426 document cannot be attached to another expense');
select throws_ok($$select pg_temp.eef((select body||body from expense_evidence_samples where label='proof'))$$,'22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 duplicate document proof rejected');
select throws_ok($$select pg_temp.eef((select jsonb_agg(p.body->0) from expense_evidence_samples p cross join generate_series(1,11) where label='proof'))$$,
 '22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 proof list is bounded before effects');
select throws_ok($$select pg_temp.eef((select jsonb_build_array((body->0)||'{"object_path":"guess"}') from expense_evidence_samples where label='proof'))$$,
 '22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 proof rejects caller paths and unknown private fields');
select is(api.projects_expense_evidence_list(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.evidence'))->'items'->0->>'status','active',
 'FR426 scoped private metadata names verified content');
select ok(not((select body::text from expense_evidence_samples where label='active')~'(object_path|checksum|Synthetic receipt bytes)'),
 'FR426 generic confirmation has no filename path bytes or private purpose');
reset role;
select throws_ok($$update expense_private.documents set checksum=repeat('e',64) where id=pg_temp.wid('ee.document')$$,'55000','EXPENSE_EVIDENCE_IMMUTABLE','FR426 document content basis is immutable');
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('creator.role') and permission_code='projects.expenses.evidence.view';
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.eec(pg_temp.eer(),0,'reserve')$$,'42501',null,'FR426 attachment view permission is rechecked before confirmed replay');
select is(pg_temp.eef('[]'),'[]'::jsonb,'FR426 evidence-free narrative does not require attachment view');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.expenses.evidence.view');
select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($$select pg_temp.eet('download')$$,'42501',null,'FR426 private download requires fresh MFA');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.eec(pg_temp.eep('retire')||'{"reason":"Synthetic terminal retention"}',2,'retire')$$,
 '55000','EXPENSE_FINANCIAL_RETENTION_REQUIRED','FR426 unlinked or active financial content cannot be retired');
select pg_temp.pfc(pg_temp.pfe('evidence'),0,'evidence.create');
select pg_temp.pfc(pg_temp.pfa('expense_cancel','evidence'),1,'evidence.cancel');
select pg_temp.eec(pg_temp.eep('retire')||'{"reason":"Synthetic terminal retention"}',2,'retire');
select is(pg_temp.eef((select body from expense_evidence_samples where label='proof'),'read'),(select body from expense_evidence_samples where label='proof'),
 'FR426 retired evidence retains original financial proof history');
reset role;
select ok((select purge_after>now()+interval '29 days' from expense_private.documents where id=pg_temp.wid('ee.document')),'FR426 chosen terminal retention is preserved before purge');
update expense_private.documents set purge_after=clock_timestamp()-interval '1 second' where id=pg_temp.wid('ee.document');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.eec(pg_temp.eep('hold')||jsonb_build_object('reason','Synthetic reviewed hold','review_date',current_date+30),3,'hold');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select is(jsonb_array_length(api.projects_expense_evidence_worker_claim(1)->'items'),0,'FR426 held evidence is not physically claimed');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.eec(pg_temp.eep('release_hold')||'{"reason":"Synthetic reviewed release"}',4,'release');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into expense_evidence_samples values('purge',api.projects_expense_evidence_worker_claim(1));
select is(jsonb_array_length((select body->'items' from expense_evidence_samples where label='purge')),1,'FR426 expired terminal document receives one bounded lease');
select throws_ok($$select api.projects_expense_evidence_worker_complete((select(body->'items'->0->>'job_id')::uuid from expense_evidence_samples where label='purge'),pg_temp.wid('wrong.lease'))$$,
 '42501','EXPENSE_WORKER_LEASE_INVALID','FR426 wrong worker lease cannot redact proof status');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.eec(pg_temp.eep('hold')||jsonb_build_object('reason','Late hold','review_date',current_date+30),6,'latehold')$$,
 '55000','EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE','FR426 a hold cannot race an already claimed physical deletion');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_complete((select(body->'items'->0->>'job_id')::uuid from expense_evidence_samples where label='purge'),
 (select(body->'items'->0->>'lease_id')::uuid from expense_evidence_samples where label='purge'));
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.eet('download')$$,'42501','EXPENSE_EVIDENCE_DENIED','FR426 physically purged bytes cannot be downloaded');
select throws_ok($$select pg_temp.eef((select body from expense_evidence_samples where label='proof'),'decision')$$,
 '55000','EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE','FR426 a purged proof cannot authorize a new financial decision');
select is(pg_temp.eef((select body from expense_evidence_samples where label='proof'),'read'),(select body from expense_evidence_samples where label='proof'),
 'FR426 physical purge preserves authorized immutable financial history');
reset role;
select is((select content_version from expense_private.documents where id=pg_temp.wid('ee.document')),1::bigint,'FR426 retained immutable proof version survives physical purge');
select ok((select checksum=repeat('c',64) and purged_at is not null from expense_private.documents where id=pg_temp.wid('ee.document')),'FR426 purge retains original financial evidence basis and completion timestamp');
