import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const sourcePath = 'supabase/migrations/20260922001000_ar_ap_control_reconciliation.sql';
const targetPath = 'supabase/migrations/20260927200703_wave3_historical_controls.sql';
const source = readFileSync(sourcePath, 'utf8');
const start = source.indexOf('create function finance.build_control_report(');
const end = source.indexOf('revoke all on function finance.build_control_report(', start);
if (start < 0 || end < 0) throw new Error('Authoritative control builder missing');
let builder = source.slice(start, end).replace('create function finance.build_control_report(', 'create or replace function finance.build_ar_ap_control_report_v1(');
const originalSet = `  union select payable_account_id from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e and k='AP')a where id is not null;`;
const expandedSet = `  union select payable_account_id from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e and k='AP'
  union select account_id from finance.control_account_basis where tenant_id=t and legal_entity_id=e and kind=k
   and observed_at < (d + 1)::timestamptz)a where id is not null;`;
if (!builder.includes(originalSet)) throw new Error('Control-set anchor changed');
builder = builder.replace(originalSet, expandedSet);
const originalSummary = ` result:=jsonb_build_object('summary',jsonb_build_object(`;
const expandedSummary = ` select coalesce(jsonb_agg(x||jsonb_build_object('basis',coalesce((
  select jsonb_agg(jsonb_build_object('source',basis.source_type,'source_id',basis.source_id,
   'observed_at',basis.observed_at) order by basis.observed_at,basis.id)
  from finance.control_account_basis basis where basis.tenant_id=t and basis.legal_entity_id=e
   and basis.kind=k and basis.account_id=(x->>'id')::uuid and basis.observed_at<(d+1)::timestamptz),'[]'::jsonb)) order by x->>'id'),'[]')
 into accounts from jsonb_array_elements(accounts)x;
 result:=jsonb_build_object('summary',jsonb_build_object(`;
if (!builder.includes(originalSummary)) throw new Error('Control summary anchor changed');
builder = builder.replace(originalSummary, expandedSummary);
const declaration = ` ids uuid[];sv numeric;gv numeric;begin`;
if (!builder.includes(declaration)) throw new Error('Control declaration anchor changed');
builder = builder.replace(declaration, ` ids uuid[];sv numeric;gv numeric;unsupported bigint;begin`);
const beforeResult = ` result:=jsonb_build_object('summary',jsonb_build_object(`;
const countUnsupported = ` select count(*) into unsupported from audit.events ev cross join lateral
 (values(ev.before_context),(ev.after_context)) snapshot(body)
 where ev.tenant_id=t and ev.legal_entity_id=e and ev.aggregate_type in('posting_mappings','supplier_bill_controls')
  and ev.occurred_at<(d+1)::timestamptz
  and ((k='AR' and ev.aggregate_type='posting_mappings' and snapshot.body->>'purpose'='receivable_control'
    and snapshot.body ? 'account_id' and not exists(select 1 from finance.control_account_basis basis
     where basis.tenant_id=t and basis.kind=k and basis.source_id=ev.id and basis.account_id::text=snapshot.body->>'account_id'))
   or (k='AP' and ev.aggregate_type='supplier_bill_controls' and snapshot.body ? 'payable_account_id'
    and not exists(select 1 from finance.control_account_basis basis
     where basis.tenant_id=t and basis.kind=k and basis.source_id=ev.id and basis.account_id::text=snapshot.body->>'payable_account_id')));
 result:=jsonb_build_object('summary',jsonb_build_object(`;
builder = builder.replace(beforeResult, countUnsupported);
const coverageAnchor = `'item_count',jsonb_array_length(items),'difference_count',jsonb_array_length(differences)),`;
const coverage = `'item_count',jsonb_array_length(items),'difference_count',jsonb_array_length(differences),
 'basis_coverage',jsonb_build_object('registry_accounts',(
  select count(distinct account_id) from finance.control_account_basis
  where tenant_id=t and legal_entity_id=e and kind=k and observed_at<(d+1)::timestamptz),
  'source_accounts',(
   select count(distinct x->>'evidence_key') from jsonb_array_elements(items)x),
  'unsupported_legacy_audit_snapshots',unsupported)),`;
if (!builder.includes(coverageAnchor)) throw new Error('Coverage anchor changed');
builder = builder.replace(coverageAnchor, coverage);
const sourceHash = createHash('sha256').update(source).digest('hex');
const grniPath = 'supabase/migrations/20260926007000_wave3_grni_control_reconciliation.sql';
const grniSource = readFileSync(grniPath, 'utf8');
const grniStart = grniSource.indexOf('create function finance.build_control_report(');
const grniEnd = grniSource.indexOf('revoke all on function finance.build_control_report(', grniStart);
if (grniStart < 0 || grniEnd < 0) throw new Error('GRNI wrapper source missing');
let grni = grniSource.slice(grniStart, grniEnd)
  .replace('create function finance.build_control_report(', 'create or replace function finance.build_control_report(');
const grniDeclaration = ` ids uuid[];sv numeric;gv numeric;begin`;
if (!grni.includes(grniDeclaration)) throw new Error('GRNI declaration anchor changed');
grni = grni.replace(grniDeclaration, ` ids uuid[];sv numeric;gv numeric;receipt_count integer;begin`);
const grniRead = ` select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into receipts from (`;
if (!grni.includes(grniRead)) throw new Error('GRNI receipt anchor changed');
grni = grni.replace(grniRead, ` select count(*) into receipt_count from (
  select id from procurement.goods_receipts where tenant_id=t and legal_entity_id=e
   and branch_id=b and document_date<=d limit 10001) bounded;
 if receipt_count>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
${grniRead}`);
const grniHash = createHash('sha256').update(grniSource).digest('hex');
const sql = `-- UNAPPLIED additive historical AR/AP control coverage. Source builder SHA-256 ${sourceHash}.
-- GRNI wrapper source SHA-256 ${grniHash}; only bounded preflight is added.
-- No arbitrary same-type GL account is inferred as an AR/AP control.
create table finance.control_account_basis(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null,legal_entity_id uuid not null,
 kind text not null check(kind in('AR','AP')),account_id uuid not null,
 source_type text not null check(source_type in('current_mapping','audit_before','audit_after','future_mapping_old','future_mapping_new')),
 source_id uuid not null,source_version bigint not null default 0,observed_at timestamptz not null,
 actor_id uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,kind,source_type,source_id,source_version,account_id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
alter table finance.control_account_basis enable row level security;
alter table finance.control_account_basis force row level security;
revoke all on finance.control_account_basis from public,anon,authenticated;
create index control_account_basis_scope on finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,observed_at);
create index control_account_basis_actor on finance.control_account_basis(actor_id);
create trigger immutable before update or delete on finance.control_account_basis
 for each row execute function workflow.reject_history_mutation();

-- Only audited, attributable before/after snapshots enter the historical set.
insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
select pm.tenant_id,pm.legal_entity_id,'AR',pm.account_id,'current_mapping',pm.id,pm.version,pm.updated_at,pm.updated_by
from finance.posting_mappings pm join finance.accounts a on a.tenant_id=pm.tenant_id and a.legal_entity_id=pm.legal_entity_id
 and a.id=pm.account_id and a.account_type='asset' where pm.purpose='receivable_control';
insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
select c.tenant_id,c.legal_entity_id,'AP',c.payable_account_id,'current_mapping',c.legal_entity_id,c.version,c.updated_at,c.updated_by
from procurement.supplier_bill_controls c join finance.accounts a on a.tenant_id=c.tenant_id and a.legal_entity_id=c.legal_entity_id
 and a.id=c.payable_account_id and a.account_type='liability';
with snapshots as (
 select ev.*,side.source_type,side.body from audit.events ev
 cross join lateral(values('audit_before'::text,ev.before_context),('audit_after'::text,ev.after_context))side(source_type,body)
 where ev.aggregate_type in('posting_mappings','supplier_bill_controls') and ev.legal_entity_id is not null
), candidates as (
 select s.tenant_id,s.legal_entity_id,case when s.aggregate_type='posting_mappings' then 'AR' else 'AP' end kind,
  case when s.aggregate_type='posting_mappings' then s.body->>'account_id' else s.body->>'payable_account_id' end account_text,
  s.source_type,s.id source_id,s.occurred_at,s.actor_id
 from snapshots s where s.body is not null and
  (s.aggregate_type='supplier_bill_controls' or s.body->>'purpose'='receivable_control')
)
insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
select c.tenant_id,c.legal_entity_id,c.kind,a.id,c.source_type,c.source_id,0,c.occurred_at,c.actor_id
from candidates c join finance.accounts a on a.tenant_id=c.tenant_id and a.legal_entity_id=c.legal_entity_id
 and a.id::text=c.account_text and a.account_type=case c.kind when 'AR' then 'asset' else 'liability' end
on conflict do nothing;

create function finance.record_control_mapping_basis() returns trigger
language plpgsql security definer set search_path='' as $$
declare k text;old_account uuid;new_account uuid;source uuid;v bigint;tenant uuid;entity uuid;actor uuid;typ text;begin
 if TG_TABLE_SCHEMA='finance' then
  if new.purpose<>'receivable_control' then return new;end if;
  k:='AR';new_account:=new.account_id;source:=new.id;v:=new.version;
  tenant:=new.tenant_id;entity:=new.legal_entity_id;actor:=new.updated_by;
  if TG_OP='UPDATE' then old_account:=old.account_id;end if;
 else
  k:='AP';new_account:=new.payable_account_id;source:=new.legal_entity_id;v:=new.version;
  tenant:=new.tenant_id;entity:=new.legal_entity_id;actor:=new.updated_by;
  if TG_OP='UPDATE' then old_account:=old.payable_account_id;end if;
 end if;
 typ:=case k when 'AR' then 'asset' else 'liability' end;
 if not exists(select 1 from finance.accounts a where a.tenant_id=tenant and a.legal_entity_id=entity
  and a.id=new_account and a.account_type=typ) then
  raise exception using errcode='22023',message='CONTROL_ACCOUNT_TYPE_INVALID';end if;
 if old_account is not null and old_account is distinct from new_account then
  insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
  values(tenant,entity,k,old_account,'future_mapping_old',source,v,statement_timestamp(),actor) on conflict do nothing;
 end if;
 insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
 values(tenant,entity,k,new_account,'future_mapping_new',source,v,statement_timestamp(),actor) on conflict do nothing;
 return new;
end $$;
revoke all on function finance.record_control_mapping_basis() from public,anon,authenticated;
create trigger control_mapping_basis after insert or update of account_id,status on finance.posting_mappings
 for each row execute function finance.record_control_mapping_basis();
create trigger supplier_mapping_basis after insert or update of payable_account_id on procurement.supplier_bill_controls
 for each row execute function finance.record_control_mapping_basis();

${builder}
revoke all on function finance.build_ar_ap_control_report_v1(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
${grni}
revoke all on function finance.build_control_report(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
`;
writeFileSync(targetPath, sql);
process.stdout.write(JSON.stringify({sourceHash, grniHash, targetBytes: Buffer.byteLength(sql)}));
