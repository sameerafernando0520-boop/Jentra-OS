-- Copy into the approved operator SQL client. Fill the single input row.
-- Use nonnegative counts of planned entries not already posted at the target.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '30s';
set local lock_timeout = '2s';

with inputs as (
  select
    null::uuid as tenant_id,
    null::uuid as legal_entity_id,
    null::date as cutoff,
    null::date as first_close,
    null::integer as opening_ar_ap_items,
    null::integer as other_opening_journal_lines,
    null::integer as post_cutoff_journal_lines,
    null::integer as new_posting_accounts
), scope as (
  select i.* from inputs i
  join core.legal_entities e on e.tenant_id = i.tenant_id and e.id = i.legal_entity_id
  where i.cutoff <= i.first_close
    and i.opening_ar_ap_items >= 0
    and i.other_opening_journal_lines >= 0
    and i.post_cutoff_journal_lines >= 0
    and (i.cutoff < i.first_close or i.post_cutoff_journal_lines = 0)
    and i.new_posting_accounts >= 0
), journal_counts as (
  select
    count(*) filter (where j.posting_date <= s.cutoff) as cutoff_lines,
    count(*) as first_close_lines
  from scope s
  join finance.journal_lines l on l.tenant_id = s.tenant_id and l.legal_entity_id = s.legal_entity_id
  join finance.journal_entries j on j.tenant_id = l.tenant_id and j.id = l.journal_entry_id
  where j.status = 'posted' and j.posting_date <= s.first_close
), posting_accounts as (
  select count(*) as account_count from scope s
  join finance.accounts a on a.tenant_id = s.tenant_id and a.legal_entity_id = s.legal_entity_id
  where a.is_posting
), as_of_dates as (
  select cutoff as as_of from scope
  union
  select first_close from scope
), fx_residuals as materialized (
  select d.as_of, o.branch_id, o.currency_code,
    finance.flow_residual(o.tenant_id, o.id, d.as_of) as residual
  from scope s cross join as_of_dates d
  join finance.open_items o on o.tenant_id = s.tenant_id and o.legal_entity_id = s.legal_entity_id
  where o.posting_date <= d.as_of and o.currency_code <> o.base_currency_code
), fx_counts as (
  select as_of, branch_id, currency_code, count(*) as open_items
  from fx_residuals
  where (residual->>'amount')::numeric <> 0 or (residual->>'base_amount')::numeric <> 0
  group by as_of, branch_id, currency_code
), forecast as (
  select s.*,
    j.cutoff_lines as observed_cutoff_journal_lines,
    j.first_close_lines as observed_first_close_journal_lines,
    a.account_count as observed_posting_accounts,
    j.cutoff_lines + 2::bigint * s.opening_ar_ap_items + s.other_opening_journal_lines
      as projected_cutoff_journal_lines,
    j.first_close_lines + 2::bigint * s.opening_ar_ap_items + s.other_opening_journal_lines
      + s.post_cutoff_journal_lines as projected_first_close_journal_lines,
    a.account_count + s.new_posting_accounts as projected_posting_accounts
  from scope s cross join journal_counts j cross join posting_accounts a
)
select coalesce((
  select to_jsonb(f) || jsonb_build_object(
    'statement_line_limit', 10000,
    'statement_posting_account_limit', 5000,
    'statement_snapshot_byte_limit', 16777216,
    'statement_journal_line_headroom', 10000 - f.projected_first_close_journal_lines,
    'statement_count_check', case
      when f.projected_first_close_journal_lines > 10000 or f.projected_posting_accounts > 5000
        then 'exceeds_count_limit' else 'within_count_limits' end,
    'fx_item_limit_per_branch_currency_date', 1000,
    'observed_fx_groups', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.as_of, x.branch_id, x.currency_code) from fx_counts x
    ), '[]'::jsonb)
  ) from forecast f
), jsonb_build_object('statement_count_check', 'invalid_or_inaccessible_scope_or_inputs')) as capacity_preflight;

rollback;
