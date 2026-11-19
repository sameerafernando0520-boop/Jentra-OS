-- Run on the frozen source and isolated restore before applying candidates.
-- Fill the three inputs identically on both targets. Use a backup operator role
-- with full read visibility into the listed relations.
-- Fingerprints cover all rows in this entity, including history after cutoff;
-- only the ledger and ageing aggregates are as of cutoff. This is accounting
-- evidence, not verification of Auth, audit logs or Storage object bytes.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '30s';
set local lock_timeout = '2s';
set local row_security = off;
set local timezone = 'UTC';
set local datestyle = 'ISO, YMD';

with inputs(tenant_id, legal_entity_id, cutoff) as (
  values (null::uuid, null::uuid, null::date)
), scope as (
  select i.*, e.currency_code
  from inputs i
  join core.legal_entities e on (e.tenant_id, e.id) = (i.tenant_id, i.legal_entity_id)
  where i.cutoff is not null and isfinite(i.cutoff)
), ledger as materialized (
  select l.tenant_id, l.branch_id, l.account_id, l.base_debit, l.base_credit
  from scope s
  join finance.journal_entries j on (j.tenant_id, j.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  join finance.journal_lines l on (l.tenant_id, l.journal_entry_id) = (j.tenant_id, j.id)
  where j.status = 'posted' and j.posting_date <= s.cutoff
), account_totals as (
  select branch_id, account_id, sum(base_debit)::text as base_debit, sum(base_credit)::text as base_credit
  from ledger group by branch_id, account_id
), residuals as materialized (
  select i.branch_id, i.kind, i.currency_code, i.due_date, s.cutoff,
    (r.value->>'amount')::numeric as amount,
    (r.value->>'base_amount')::numeric as base_amount
  from scope s
  join finance.open_items i on (i.tenant_id, i.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  cross join lateral (select finance.flow_residual(i.tenant_id, i.id, s.cutoff) as value) r
  where i.posting_date <= s.cutoff
), residual_totals as (
  select branch_id, kind, currency_code, count(*) as open_item_count,
    sum(amount)::text as amount, sum(base_amount)::text as base_amount,
    count(*) filter (where due_date < cutoff) as overdue_item_count,
    coalesce(sum(base_amount) filter (where due_date < cutoff), 0)::text as overdue_base_amount
  from residuals
  where amount <> 0 or base_amount <> 0
  group by branch_id, kind, currency_code
), datasets(name) as (
  values ('journal_entries'), ('journal_lines'), ('open_items'),
    ('open_item_allocations'), ('allocation_reversals'), ('stock_balances'), ('stock_valuations'),
    ('accounts'), ('fiscal_periods'), ('cash_bank_accounts'), ('bank_statements'),
    ('bank_statement_lines'), ('bank_matches'), ('bank_match_reversals'), ('bank_match_claims'),
    ('asset_register'), ('asset_opening_sources'), ('asset_books'), ('asset_schedules'), ('asset_effects')
), scoped_rows(dataset, payload) as (
  select 'journal_entries', to_jsonb(j) from scope s
  join finance.journal_entries j on (j.tenant_id, j.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'journal_lines', to_jsonb(l) from scope s
  join finance.journal_lines l on (l.tenant_id, l.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'open_items', to_jsonb(i) from scope s
  join finance.open_items i on (i.tenant_id, i.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'open_item_allocations', to_jsonb(a) from scope s
  join finance.open_item_allocations a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'allocation_reversals', to_jsonb(r) from scope s
  join finance.allocation_reversals r on (r.tenant_id, r.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'stock_balances', to_jsonb(b) from scope s
  join inventory.stock_balances b on (b.tenant_id, b.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'stock_valuations', to_jsonb(v) from scope s
  join inventory.stock_valuations v on (v.tenant_id, v.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'accounts', to_jsonb(a) from scope s
  join finance.accounts a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'fiscal_periods', to_jsonb(p) from scope s
  join finance.fiscal_periods p on (p.tenant_id, p.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'cash_bank_accounts', to_jsonb(b) from scope s
  join finance.cash_bank_accounts b on (b.tenant_id, b.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'bank_statements', to_jsonb(b) from scope s
  join finance.bank_statements b on (b.tenant_id, b.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'bank_statement_lines', to_jsonb(l) from scope s
  join finance.bank_statements b on (b.tenant_id, b.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  join finance.bank_statement_lines l on (l.tenant_id, l.statement_id) = (b.tenant_id, b.id)
  union all
  select 'bank_matches', to_jsonb(m) from scope s
  join finance.bank_matches m on (m.tenant_id, m.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'bank_match_reversals', to_jsonb(r) from scope s
  join finance.bank_matches m on (m.tenant_id, m.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  join finance.bank_match_reversals r on (r.tenant_id, r.match_id) = (m.tenant_id, m.id)
  union all
  select 'bank_match_claims', to_jsonb(c) from scope s
  join finance.bank_matches m on (m.tenant_id, m.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  join finance.bank_match_claims c on (c.tenant_id, c.match_id) = (m.tenant_id, m.id)
  union all
  select 'asset_register', to_jsonb(a) from scope s
  join assets.register a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'asset_opening_sources', to_jsonb(a) from scope s
  join assets.opening_sources a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'asset_books', to_jsonb(a) from scope s
  join assets.books a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'asset_schedules', to_jsonb(a) from scope s
  join assets.schedules a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
  union all
  select 'asset_effects', to_jsonb(a) from scope s
  join assets.effects a on (a.tenant_id, a.legal_entity_id) = (s.tenant_id, s.legal_entity_id)
), row_hashes as (
  select dataset, encode(sha256(convert_to(payload::text, 'UTF8')), 'hex') as digest
  from scoped_rows
), fingerprints as (
  select d.name, count(r.digest) as row_count,
    encode(sha256(convert_to(coalesce(string_agg(r.digest, '' order by r.digest collate "C"), ''), 'UTF8')), 'hex') as sha256
  from datasets d left join row_hashes r on r.dataset = d.name
  group by d.name
)
select coalesce((
  select jsonb_build_object(
    'status', case when exists (select 1 from residuals where amount is null or base_amount is null)
      then 'incomplete_residuals' else 'captured' end,
    'scope', to_jsonb(s),
    'read_only', current_setting('transaction_read_only') = 'on',
    'posted_ledger', (select jsonb_build_object('line_count', count(*),
      'base_debit', coalesce(sum(base_debit), 0)::text,
      'base_credit', coalesce(sum(base_credit), 0)::text,
      'base_difference', coalesce(sum(base_debit - base_credit), 0)::text) from ledger),
    'posted_accounts', (select coalesce(jsonb_agg(to_jsonb(a) order by a.branch_id, a.account_id), '[]') from account_totals a),
    'open_item_groups', (select coalesce(jsonb_agg(to_jsonb(r) order by r.branch_id, r.kind, r.currency_code), '[]') from residual_totals r),
    'fingerprints', (select jsonb_object_agg(f.name, to_jsonb(f) - 'name') from fingerprints f)
  ) from scope s
), jsonb_build_object('status', 'invalid_or_inaccessible_scope_or_cutoff')) as restore_evidence;

rollback;
