-- Governed synthetic fixed-asset candidate. Included only in BEGIN/ROLLBACK.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table asset_client_samples(label text primary key,body jsonb not null);
create function pg_temp.asset_capture(label text,k text default 'a',b text default 'branch') returns void language plpgsql as $$
declare item jsonb; section text;begin
 foreach section in array array['books','effects','proposals'] loop
  item:=api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('asset.'||k),section,null);
  insert into asset_client_samples values(label||'.'||section,item);
 end loop;
end $$;
select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='assets' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity),8,
 'all eight asset tables are forced RLS');
select is(assets.round_even(0.005,2),0::numeric,'asset exact even tie');
select is(assets.round_even(0.015,2),0.02::numeric,'asset exact odd tie');
select is(assets.ratio(99999999999999999999::numeric*9007199254740991-1,9007199254740991,6),99999999999999999999::numeric,
 'large rational quotient does not acquire a rounded division increment');
select is((assets.schedule('0.03','0','0','0',5,'straight_line',1,1,2,'2026-01-01')->4->>'depreciation'),
 '0.010000','asset tiny final residue conserves exactly');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='assets' and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')),'no direct asset table reads');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='assets' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'asset helpers denied to authenticated clients');
select throws_ok($q$select assets.schedule('1','0','0','2',3,'straight_line',1,1,2,'2026-01-01')$q$,
 '22023','ASSET_BOOK_INVALID','residual exceeds carrying');
select throws_ok($q$select assets.schedule('1.001','0','0','0',3,'straight_line',1,1,2,'2026-01-01')$q$,
 '22023','ASSET_BOOK_INVALID','unrepresentable currency precision rejected');
select is(assets.schedule('1000','0','0','100',3,'reducing_balance',1,5,2,'2026-01-01')->2->>'depreciation',
 '540.000000','exact declining balance final residue');
select is(assets.schedule('1000','200','300','100',2,'straight_line',1,1,2,'2026-01-01')->1->>'accumulated_closing',
 '600.000000','impairment stays separate from depreciation history');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.assets',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer','branch-manager']) x
 cross join core.permissions p where p.module='assets';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'assets.view');
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 select pg_temp.wid('asset.account.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),upper(x),'Synthetic asset '||x,
 case when x in('cost','accum','impair','bank') then 'asset' when x in('expense','loss') then 'expense' when x='gain' then 'revenue' else 'equity' end,
 case when x in('accum','impair','gain','offset','surplus') then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['cost','accum','impair','bank','expense','loss','gain','offset','surplus']) x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 values(pg_temp.wid('asset.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic asset period',pg_temp.wdate()-400,pg_temp.wdate()+400,
 pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
 select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(x),'journal_entry','SYNTHETIC-ASSET-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['branch','branch2']) x;
create function pg_temp.acmd(payload jsonb,v bigint,k text,b text default 'branch') returns jsonb language sql as $$
 select api.assets_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('asset.command.'||k),
  pg_temp.wid('asset.command.'||k),now(),payload,v) $$;
create function pg_temp.abook(resid text default '100',months integer default 3) returns jsonb language sql as $$
 select jsonb_build_object('residual',resid,'remaining_months',months,'method','straight_line','convention','in_service_month',
  'rate_numerator',1,'rate_denominator',1,'precision',2,'expense_account_id',pg_temp.wid('asset.account.expense')) $$;
create function pg_temp.aopening(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','opening','id',pg_temp.wid('asset.'||k),'proposal_id',pg_temp.wid('asset.proposal.'||k),
 'source_id',pg_temp.wid('asset.source.'||k),'source_reference','SYNTHETIC-'||upper(k),'code',upper(k),'name','Synthetic asset '||k,
 'ownership','Synthetic owned','currency_code','LKR','in_service',(date_trunc('month',pg_temp.wdate())-interval '3 months')::date,
 'location_id',pg_temp.wid('asset.location.branch'),'custodian_id',null,'cost','1000','opening_accumulated','400',
 'cost_components',jsonb_build_array(jsonb_build_object('code','OPENING','name','Governed synthetic opening','amount','1000')),
 'cost_account_id',pg_temp.wid('asset.account.cost'),'accumulated_account_id',pg_temp.wid('asset.account.accum'),
 'impairment_account_id',pg_temp.wid('asset.account.impair'),'offset_account_id',pg_temp.wid('asset.account.offset'),
 'book',pg_temp.abook(),'posting_date',(date_trunc('month',pg_temp.wdate())-interval '3 months')::date,'reason','Synthetic governed opening') $$;
create function pg_temp.astate(k text default 'a') returns jsonb language sql as $$select assets.summary(pg_temp.wid('asset.'||k)) $$;
create function pg_temp.aproposal(action text,k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action',action,'id',r.id,'proposal_id',p.id,'digest',p.digest,'reason','Synthetic exact proposal '||action)
 from assets.register r join assets.proposals p on p.id=r.current_proposal_id where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.adep(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','depreciate','id',r.id,'book_id',r.current_book_id,'period_index',r.posted_periods+1,'reason','Synthetic exact period')
 from assets.register r where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.areverse(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','reverse','id',r.id,'effect_id',r.last_effect_id,'reason','Synthetic original effect reversal')
 from assets.register r where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.aprop(kind text,extra jsonb,k text default 'a',proposal text default 'p') returns jsonb language sql as $$
 select jsonb_build_object('action','propose','id',pg_temp.wid('asset.'||k),'proposal_id',pg_temp.wid('asset.proposal.'||proposal),
  'kind',kind,'posting_date',pg_temp.wdate(),'reason','Synthetic governed '||kind)||extra $$;
select pg_temp.wactor('creator');
select pg_temp.acmd(jsonb_build_object('action','location','id',pg_temp.wid('asset.location.branch'),'code','LAB','name','Synthetic lab','reason','Synthetic location'),0,'location');
select pg_temp.acmd(jsonb_build_object('action','location','id',pg_temp.wid('asset.location.branch2'),'code','LAB','name','Synthetic second lab','reason','Synthetic location'),0,'location2','branch2');
select is(pg_temp.acmd(pg_temp.aopening(),0,'opening')->'entity'->>'status','draft','opening creates no authoritative cost');
select is(pg_temp.astate()->>'cost','0.000000','cost remains zero until independent approval');
select pg_temp.asset_capture('opening');
select is(api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.a'),'books',null)->'labels'->>'expense_account_id',
 'EXPENSE · Synthetic asset expense','approval review exposes the exact scoped named expense mapping');
select is(assets.label(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),'account',pg_temp.wid('asset.account.expense')),null::text,
 'named reference projection cannot read another tenant');
select is(jsonb_typeof(api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.a'),'books',null)->'opening'->'cost'),
 'string','opening wire amounts retain exact decimal strings');
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('currency')||'{"currency_code":"USD"}',0,'currency-mismatch')$q$,
 '55000','ASSET_BASE_CURRENCY_CHANGED','opening cannot reinterpret a client-frozen currency');
select is(pg_temp.acmd(pg_temp.aopening(),0,'opening')->'entity'->>'version','1','exact opening replay is stable');
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening()||'{"name":"Changed body"}',0,'opening')$q$,
 '22023','IDEMPOTENCY_MISMATCH','changed opening body cannot replay');
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('b')||'{"source_reference":"synthetic-a"}',0,'duplicate')$q$,
 '55000','ASSET_SOURCE_ALREADY_OWNED','opening evidence cannot be owned twice even under a new source UUID');
select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('post'),1,'unapproved')$q$,
 '55000','ASSET_APPROVAL_REQUIRED','capitalization requires exact approval');
select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('approve'),1,'self-approve')$q$,
 '42501','ASSET_INDEPENDENT_APPROVAL_REQUIRED','preparer cannot approve own opening');
select pg_temp.wactor('creator','aal1');
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening(),0,'opening')$q$,'42501','Permission denied or multi-factor authentication required.','MFA rechecked before replay');
select pg_temp.wactor('reviewer');
select is(pg_temp.acmd(pg_temp.aproposal('approve'),1,'approve')->'entity'->>'version','2','independent approval binds exact proposal');
select pg_temp.wactor('creator');
select is(pg_temp.acmd(pg_temp.aproposal('post'),2,'capitalize')->'entity'->>'status','active','governed opening posts atomically');
select is(pg_temp.astate()->>'carrying','600.000000','opening cost minus original accumulation');
select is((select count(*)::integer from assets.schedules where book_id=pg_temp.wid('asset.proposal.a')),3,'original immutable schedule materialized');
select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id=(select journal_id from assets.effects where kind='capitalize')),0::numeric,'capitalization journal balanced');
select is(pg_temp.acmd(pg_temp.adep(),3,'dep1')->'entity'->>'version','4','first period posts once');
select is(pg_temp.astate()->>'accumulated','566.670000','exact cumulative allocation matches Dart');
select pg_temp.asset_capture('active');
select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),3,'stale-period')$q$,'40001','VERSION_CONFLICT','stale asset version cannot post');
select throws_ok($q$select pg_temp.acmd(jsonb_build_object('action','reverse','id',pg_temp.wid('asset.a'),'effect_id',
 (select id from assets.effects where kind='capitalize'),'reason','Synthetic reversal'),4,'dependent-reverse')$q$,
 '55000','ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL','later depreciation blocks capitalization reversal');
select throws_ok($q$update assets.schedules set facts='{}' where book_id=pg_temp.wid('asset.proposal.a')$q$,
 '55000','ASSET_HISTORY_IMMUTABLE','schedule facts cannot be overwritten');
select is(pg_temp.acmd(pg_temp.aprop('book_revision',jsonb_build_object('book',pg_temp.abook('100',2)),proposal=>'book2'),4,'book2-propose')->'entity'->>'version','5','prospective book proposed');
select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),5,'blocked-period')$q$,'55000','ASSET_SCHEDULE_STALE','pending book freezes competing depreciation');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),5,'book2-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),6,'book2-post');
select is((select basis->>'opening_accumulated' from assets.books where id=pg_temp.wid('asset.proposal.book2')),'566.670000','prospective book retains posted accumulation');
select is((select basis->>'start_date' from assets.books where id=pg_temp.wid('asset.proposal.book2')),
 ((date_trunc('month',pg_temp.wdate())-interval '2 months')::date)::text,'prospective book begins at first unposted month');
select pg_temp.acmd(pg_temp.adep(),7,'book2-dep');
select is(pg_temp.astate()->>'accumulated','733.330000','prospective half-even amount preserves total');
select pg_temp.acmd(pg_temp.areverse(),8,'book2-dep-reverse');
select is(pg_temp.astate()->>'accumulated','566.670000','original period reversal restores exact prior accumulation');
select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),9,'same-period-again')$q$,
 '55000','ASSET_REBOOK_AFTER_REVERSAL_REQUIRED','reversed period requires a new governed book');
select pg_temp.acmd(pg_temp.areverse(),9,'book2-reverse');
select is(pg_temp.astate()->>'book_id',pg_temp.wid('asset.proposal.a')::text,'book reversal restores original schedule identity');
select pg_temp.acmd(pg_temp.aprop('impair',jsonb_build_object('amount','100','loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'impair'),10,'impair-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),11,'impair-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),12,'impair-post');
select pg_temp.asset_capture('impaired');
select is(pg_temp.astate()->>'impairment','100.000000','impairment reserve is explicit');
select is(pg_temp.astate()->>'accumulated','566.670000','impairment does not rewrite depreciation history');
select pg_temp.acmd(pg_temp.areverse(),13,'impair-reverse');
select is(pg_temp.astate()->>'impairment','0.000000','original impairment reversal restores reserve');
select pg_temp.acmd(pg_temp.aprop('revalue',jsonb_build_object('cost','1100','surplus_account_id',pg_temp.wid('asset.account.surplus'),
 'loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'revalue'),14,'revalue-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),15,'revalue-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),16,'revalue-post');
select is(pg_temp.astate()->>'cost','1100.000000','configured revaluation retains revised gross cost');
select pg_temp.acmd(pg_temp.areverse(),17,'revalue-reverse');
select is(pg_temp.astate()->>'cost','1000.000000','original revaluation reversal restores cost');
select pg_temp.acmd(pg_temp.aprop('dispose',jsonb_build_object('proceeds','500','proceeds_account_id',pg_temp.wid('asset.account.bank'),
 'gain_account_id',pg_temp.wid('asset.account.gain'),'loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'dispose'),18,'dispose-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),19,'dispose-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),20,'dispose-post');
select pg_temp.asset_capture('disposed');
select is(pg_temp.astate()->>'status','disposed','disposal commits with original cost and accumulation');
select is((select sum(base_credit-base_debit) from finance.journal_lines where account_id=pg_temp.wid('asset.account.gain')),66.67::numeric,'exact disposal gain matches original carrying');
select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),21,'disposed-dep')$q$,'55000','ASSET_SCHEDULE_STALE','disposed asset denies depreciation');
select pg_temp.acmd(pg_temp.areverse(),21,'dispose-reverse');
select is(pg_temp.astate()->>'status','active','original disposal reversal restores active state');
select is(pg_temp.astate()->>'carrying','433.330000','original disposal reversal restores exact carrying');
-- Both branch authorities are required on original command and replay.
select pg_temp.wactor('branch-manager');
select throws_ok($q$select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),
 'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),proposal=>'transfer'),22,'narrow-transfer')$q$,
 '42501','Permission denied or multi-factor authentication required.','source-only branch role cannot authorize destination');
select pg_temp.wactor('creator');
select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),
 'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),proposal=>'transfer'),22,'transfer-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),23,'transfer-approve');
select pg_temp.wactor('creator');
create temporary table asset_saved_requests as select pg_temp.aproposal('post') as transfer_post;
grant select on asset_saved_requests to authenticated;
select is(pg_temp.acmd((select transfer_post from asset_saved_requests),24,'transfer-post')->'entity'->>'current_branch_id',
 pg_temp.wid('branch2')::text,'transfer retains command branch and resulting accountable branch separately');
select is((api.assets_register(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))->'items'->0->>'original_branch_id'),
 pg_temp.wid('branch')::text,'original ownership branch survives transfer');
-- Narrow the creator to its source branch after completion; destination replay must deny.
update core.role_assignments set branch_id=pg_temp.wid('branch') where role_id=pg_temp.wid('creator.role');
select throws_ok($q$select pg_temp.acmd((select transfer_post from asset_saved_requests),24,'transfer-post')$q$,
 '42501','Permission denied or multi-factor authentication required.','revoked destination authority denies completed transfer replay');
select throws_ok($q$select api.assets_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('asset.command.transfer-post'),'post')$q$,'42501','Permission denied or multi-factor authentication required.',
 'receipt lookup rechecks original destination transfer authority');
update core.role_assignments set branch_id=null where role_id=pg_temp.wid('creator.role');
select pg_temp.acmd(pg_temp.areverse(),25,'transfer-reverse','branch2');
select is(pg_temp.astate()->>'branch_id',pg_temp.wid('branch')::text,'original transfer reversal restores branch and location');
select is(pg_temp.astate()->>'location_id',pg_temp.wid('asset.location.branch')::text,'original location restored exactly');
update finance.fiscal_periods set state='soft_locked' where id=pg_temp.wid('asset.period');
select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),26,'closed-dep')$q$,'55000','PERIOD_CLOSED','closed period denies exact scheduled posting');
select throws_ok($q$select pg_temp.acmd(pg_temp.areverse(),26,'closed-reverse')$q$,'55000','PERIOD_CLOSED','closed original period denies reversal');
select is(pg_temp.astate()->>'accumulated','566.670000','closed-period failures preserve all balances');
update finance.fiscal_periods set state='open' where id=pg_temp.wid('asset.period');
select pg_temp.acmd(pg_temp.adep(),26,'a-dep2');
select pg_temp.acmd(pg_temp.adep(),27,'a-dep3');
select is(pg_temp.astate()->>'carrying','100.000000','original full life preserves exact residual after correction chain');
-- A late failure must roll back journal numbering, books, asset state and effects.
select pg_temp.acmd(pg_temp.aopening('b'),0,'b-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','b'),1,'b-approve');
select pg_temp.wactor('creator');
create temporary table asset_late_before as select to_jsonb(s) as sequence from core.document_sequences s
 where tenant_id=pg_temp.wid('tenant') and branch_id=pg_temp.wid('branch') and document_type='journal_entry';
create function pg_temp.asset_fail_outbox() returns trigger language plpgsql as $$begin
 if new.topic='assets.post' then raise exception using errcode='P0001',message='SYNTHETIC_ASSET_LATE_FAIL';end if;return new;end $$;
create trigger asset_synthetic_late_fail before insert on core.outbox_events for each row execute function pg_temp.asset_fail_outbox();
select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('post','b'),2,'b-post')$q$,
 'P0001','SYNTHETIC_ASSET_LATE_FAIL','late outbox failure aborts entire capitalization');
select is(pg_temp.astate('b')->>'cost','0.000000','late failure restores provisional zero cost');
select is(pg_temp.astate('b')->>'version','2','late failure restores approved version');
select is((select count(*)::integer from assets.books where asset_id=pg_temp.wid('asset.b')),0,'late failure leaves no materialized books');
select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.b')),0,'late failure leaves no authoritative effects');
select is((select to_jsonb(s) from core.document_sequences s where tenant_id=pg_temp.wid('tenant') and branch_id=pg_temp.wid('branch') and document_type='journal_entry'),
 (select sequence from asset_late_before),'late failure rolls back document numbering');
drop trigger asset_synthetic_late_fail on core.outbox_events;
select pg_temp.acmd(pg_temp.aproposal('post','b'),2,'b-post');
select pg_temp.acmd(pg_temp.areverse('b'),3,'b-reverse');
select is(pg_temp.astate('b')->>'status','reversed','opening reversal retains terminal ownership history');
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('c')||'{"source_reference":"SYNTHETIC-B"}',0,'b-source-again')$q$,
 '55000','ASSET_SOURCE_ALREADY_OWNED','reversal does not release the same opening evidence for another capitalization');
-- Final schedule conservation and explicit zero periods against the installed journal.
select pg_temp.acmd(pg_temp.aopening('tiny')||jsonb_build_object('cost','0.03','opening_accumulated','0',
 'cost_components',jsonb_build_array(jsonb_build_object('code','TINY','name','Synthetic tiny value','amount','0.03')),
 'book',pg_temp.abook('0',5),'in_service',(date_trunc('month',pg_temp.wdate())-interval '6 months')::date,
 'posting_date',(date_trunc('month',pg_temp.wdate())-interval '6 months')::date),0,'tiny-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','tiny'),1,'tiny-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','tiny'),2,'tiny-post');
select pg_temp.acmd(pg_temp.adep('tiny'),3,'tiny-dep1');
select pg_temp.acmd(pg_temp.adep('tiny'),4,'tiny-dep2');
select pg_temp.acmd(pg_temp.adep('tiny'),5,'tiny-dep3');
select pg_temp.acmd(pg_temp.adep('tiny'),6,'tiny-dep4');
select pg_temp.acmd(pg_temp.adep('tiny'),7,'tiny-dep5');
select is(pg_temp.astate('tiny')->>'carrying','0.000000','final period conserves exact depreciable value');
select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate'),5,'zero periods are retained facts');
select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate' and journal_id is null),2,'zero periods do not fabricate zero journals');
select is((select sum(base_debit) from finance.journal_lines where account_id=pg_temp.wid('asset.account.expense') and source_line_id in
 (select id from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate')),0.03::numeric,'tiny journals conserve original cost');
select throws_ok($q$select pg_temp.acmd(pg_temp.adep('tiny'),8,'tiny-beyond-life')$q$,'55000','ASSET_SCHEDULE_STALE','posting beyond final life rejected');
select pg_temp.acmd(pg_temp.aopening('paged')||jsonb_build_object('book',pg_temp.abook('100',1200)),0,'paged-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','paged'),1,'paged-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','paged'),2,'paged-post');
select is(jsonb_array_length(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'))->'items'),50,'1200-month schedule response remains bounded at 50');
select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'))->>'next_cursor','50','ordinal schedule cursor identifies the final returned period');
select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1150)->'items'->49->>'closing_carrying','100.000000','last bounded page retains original final residual');
select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1150)->>'next_cursor',null::text,'terminal schedule page has no false continuation');
select throws_ok($q$select api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1201)$q$,'22023','ASSET_PAGE_INVALID','unbounded schedule cursor rejected');
select is(api.assets_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'assets.view')->>'procurement_provider','false','unimplemented procurement provider explicit');
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('x')||'{"action":"procurement"}',0,'fake-procurement')$q$,
 '22023','ASSET_COMMAND_INVALID','invented procurement metadata cannot capitalize');
select pg_temp.wactor('branch-manager');
set local role authenticated;
select throws_ok($q$select api.assets_register(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))$q$,
 '42501','Permission denied or multi-factor authentication required.','authenticated branch actor cannot read other branch register');
select throws_ok($q$select api.assets_register(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501','Permission denied or multi-factor authentication required.','cross-tenant scope denied before data');
select throws_ok($q$select count(*) from assets.register$q$,'42501',null,'authenticated direct asset table access denied');
reset role;
select pg_temp.wactor('creator');
update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
select throws_ok($q$select pg_temp.acmd(pg_temp.aopening(),0,'opening')$q$,'42501','ASSET_ENTITLEMENT_REQUIRED','entitlement rechecked before replay');
update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'assets.%'
 and(response::text like '%600.000000%' or response::text like '%Synthetic owned%' or response::text like '%SYNTHETIC-A%')),'generic receipts contain no source/financial evidence');
select ok(not exists(select 1 from audit.events where tenant_id=pg_temp.wid('tenant') and event_type like 'assets.%'
 and(after_context::text like '%600.000000%' or after_context::text like '%Synthetic owned%')),'generic audit contains no financial/ownership evidence');
