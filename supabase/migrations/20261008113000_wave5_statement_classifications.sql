-- UNAPPLIED. Requires the separately owned Wave 3 financial-statement provider.
-- No classifications, financial publications, entitlements or roles are seeded.
insert into core.permissions(code,module,description,privileged) values
 ('finance.classifications.approve','finance','Approve immutable statement account classifications',true)
 on conflict(code) do nothing;
create table analytics.statement_classifications(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 profit_loss_id uuid not null,balance_sheet_id uuid not null,labels jsonb not null,
 reason text not null check(length(trim(reason)) between 8 and 500),actor_id uuid not null references auth.users(id),
 profit_loss_hash text not null,balance_sheet_hash text not null,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),foreign key(tenant_id,profit_loss_id) references finance.financial_reports(tenant_id,id),
 foreign key(tenant_id,balance_sheet_id) references finance.financial_reports(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(jsonb_typeof(labels)='object' and octet_length(labels::text)<=1048576),
 check(profit_loss_hash ~ '^[a-f0-9]{64}$' and balance_sheet_hash ~ '^[a-f0-9]{64}$'));
alter table analytics.statement_classifications enable row level security;
alter table analytics.statement_classifications force row level security;
revoke all on analytics.statement_classifications from public,anon,authenticated;
create trigger immutable before update or delete on analytics.statement_classifications for each row execute function analytics.immutable_evidence();
create index statement_classification_scope on analytics.statement_classifications(tenant_id,legal_entity_id,branch_id,id);

create function analytics.statement_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or e is null or b is null then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 -- The Wave 3 statements are entity-wide, even when requested at a branch.
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
end $$;

create function analytics.statement_bundle(t uuid,e uuid,b uuid,p uuid,q uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare pl finance.financial_reports%rowtype;bs finance.financial_reports%rowtype;k text;begin
 perform analytics.statement_access(t,e,b);
 select * into pl from finance.financial_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=p and kind='profit_loss';
 select * into bs from finance.financial_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=q and kind='balance_sheet';
 if pl.id is null or bs.id is null or pl.summary->>'status'<>'generated' or bs.summary->>'status'<>'generated'
  or pl.summary->>'version'<>'1' or bs.summary->>'version'<>'1' then
  raise exception using errcode='42501',message='STATEMENT_BUNDLE_REQUIRED';end if;
 foreach k in array array['tenant_id','legal_entity_id','branch_id','period_id','period_start','period_end','as_of','base_currency_code'] loop
  if pl.summary->k is distinct from bs.summary->k then raise exception using errcode='22023',message='STATEMENT_BUNDLE_MISMATCH';end if;
 end loop;
 if pl.evidence->'journals' is distinct from bs.evidence->'journals'
  or jsonb_array_length(pl.evidence->'accounts')<>jsonb_array_length(bs.evidence->'accounts')
  or exists(select 1 from jsonb_array_elements(pl.evidence->'accounts') a full join jsonb_array_elements(bs.evidence->'accounts') z
   on a->>'account_id'=z->>'account_id' where a is null or z is null or a->>'account_type' is distinct from z->>'account_type') then
  raise exception using errcode='22023',message='STATEMENT_SOURCE_MISMATCH';end if;
 return jsonb_build_object('profitLoss',pl.evidence,'balanceSheet',bs.evidence,
  'profitLossHash',encode(extensions.digest(pl.evidence::text,'sha256'),'hex'),
  'balanceSheetHash',encode(extensions.digest(bs.evidence::text,'sha256'),'hex'));
end $$;
revoke all on function analytics.statement_access(uuid,uuid,uuid),analytics.statement_bundle(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;

create function api.wave5_classification_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.statement_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'finance.classifications.approve',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 return auth.uid();end $$;

create function api.wave5_classification_publish(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_profit_loss_id uuid,p_balance_sheet_id uuid,p_labels jsonb,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare bundle jsonb;a jsonb;tag text;h text;receipt jsonb;payload jsonb;begin
 perform api.wave5_classification_authorize(p_tenant_id,p_legal_entity_id,p_branch_id);
 bundle:=analytics.statement_bundle(p_tenant_id,p_legal_entity_id,p_branch_id,p_profit_loss_id,p_balance_sheet_id);
 if p_id is null or jsonb_typeof(p_labels) is distinct from 'object' or octet_length(p_labels::text)>1048576
  or p_reason is null or length(trim(p_reason)) not between 8 and 500
  or (select count(*) from jsonb_object_keys(p_labels))<>jsonb_array_length(bundle#>'{profitLoss,accounts}') then
  raise exception using errcode='22023',message='CLASSIFICATION_COVERAGE_REQUIRED';end if;
 for a in select * from jsonb_array_elements(bundle#>'{profitLoss,accounts}') loop
  tag:=p_labels->>(a->>'account_id');
  if jsonb_typeof(p_labels->(a->>'account_id')) is distinct from 'string' or tag is null or
   not(case a->>'account_type' when 'asset' then tag in('current_asset','inventory','noncurrent_asset')
    when 'liability' then tag in('current_liability','noncurrent_liability') when 'revenue' then tag='revenue'
    when 'expense' then tag in('cost_of_sales','operating_expense') when 'equity' then tag='equity' else false end) then
   raise exception using errcode='22023',message='CLASSIFICATION_TYPE_MISMATCH';end if;
 end loop;
 payload:=jsonb_build_object('profitLossId',p_profit_loss_id,'balanceSheetId',p_balance_sheet_id,'labels',p_labels,'reason',p_reason,
  'profitLossHash',bundle->>'profitLossHash','balanceSheetHash',bundle->>'balanceSheetHash');
 h:=core.wave3_request_hash('analytics.classifications.publish',p_id,p_tenant_id,p_legal_entity_id,p_branch_id,payload,null);
 receipt:=core.wave3_replay(p_tenant_id,'analytics.classifications.publish',p_id,p_id,h);
 if receipt is not null then return receipt;end if;
 insert into analytics.statement_classifications values(p_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_profit_loss_id,p_balance_sheet_id,
  p_labels,p_reason,auth.uid(),bundle->>'profitLossHash',bundle->>'balanceSheetHash',statement_timestamp());
 return core.wave3_finish_command(p_tenant_id,'analytics.classifications.publish',p_id,'statement_classification',p_id,p_id,h,null,
  jsonb_build_object('id',p_id,'version','1','profitLossHash',bundle->>'profitLossHash','balanceSheetHash',bundle->>'balanceSheetHash'),p_legal_entity_id,p_branch_id);
end $$;

create function analytics.exact_named_ratio(n numeric,d numeric) returns jsonb
language sql immutable set search_path='' as $$select jsonb_build_object('numerator',n::text,'denominator',d::text,
 'exactValue',case when d>0 then round(n/d,6)::text else null end,
 'unavailableReason',case when d=0 then 'ZERO_DENOMINATOR' when d<0 then 'NEGATIVE_DENOMINATOR' end)$$;

create function api.wave5_financial_ratios(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_profit_loss_id uuid,p_balance_sheet_id uuid,p_classification_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare bundle jsonb;pl jsonb;bs jsonb;c analytics.statement_classifications%rowtype;ratios jsonb;result jsonb;
 revenue numeric;profit numeric;assets numeric;liabilities numeric;equity numeric;ca numeric;inventory numeric;cl numeric;cogs numeric;begin
 bundle:=analytics.statement_bundle(p_tenant_id,p_legal_entity_id,p_branch_id,p_profit_loss_id,p_balance_sheet_id);
 pl:=bundle#>'{profitLoss,summary}';bs:=bundle#>'{balanceSheet,summary}';
 revenue:=(pl->>'revenue')::numeric;profit:=(pl->>'net_profit')::numeric;
 assets:=(bs->>'assets')::numeric;liabilities:=(bs->>'liabilities')::numeric;equity:=(bs->>'equity')::numeric+(bs->>'current_earnings')::numeric;
 ratios:=jsonb_build_object('net_profit_margin',analytics.exact_named_ratio(profit,revenue),
  'liabilities_to_assets',analytics.exact_named_ratio(liabilities,assets),'assets_to_equity',analytics.exact_named_ratio(assets,equity));
 if p_classification_id is not null then
  select * into c from analytics.statement_classifications where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and id=p_classification_id and profit_loss_id=p_profit_loss_id and balance_sheet_id=p_balance_sheet_id;
  if not found or c.profit_loss_hash is distinct from bundle->>'profitLossHash' or c.balance_sheet_hash is distinct from bundle->>'balanceSheetHash' then
   raise exception using errcode='42501',message='CLASSIFICATION_PUBLICATION_REQUIRED';end if;
  select coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id') in('current_asset','inventory')),0),
   coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id')='inventory'),0),
   coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id')='current_liability'),0)
   into ca,inventory,cl from jsonb_array_elements(bundle#>'{balanceSheet,accounts}') a;
  select coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id')='cost_of_sales'),0)
   into cogs from jsonb_array_elements(bundle#>'{profitLoss,accounts}') a;
  ratios:=ratios||jsonb_build_object('current_ratio',analytics.exact_named_ratio(ca,cl),
   'quick_ratio',analytics.exact_named_ratio(ca-inventory,cl),'gross_profit_margin',analytics.exact_named_ratio(revenue-cogs,revenue));
 end if;
 result:=jsonb_build_object('contractRevision',1,'formulaVersion',1,'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'profitLossId',p_profit_loss_id,'balanceSheetId',p_balance_sheet_id,'classificationId',p_classification_id,
  'profitLossHash',bundle->>'profitLossHash','balanceSheetHash',bundle->>'balanceSheetHash',
  'currency',pl->>'base_currency_code','periodStart',pl->>'period_start','asOf',pl->>'as_of','ratios',ratios);
 return jsonb_build_object('canonicalText',result::text,'sourceHash',encode(extensions.digest(result::text,'sha256'),'hex'));
end $$;
revoke all on function analytics.exact_named_ratio(numeric,numeric),api.wave5_classification_authorize(uuid,uuid,uuid),
 api.wave5_classification_publish(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),api.wave5_financial_ratios(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_classification_authorize(uuid,uuid,uuid),api.wave5_classification_publish(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),
 api.wave5_financial_ratios(uuid,uuid,uuid,uuid,uuid,uuid) to authenticated;
