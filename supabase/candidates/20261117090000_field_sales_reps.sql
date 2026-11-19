-- CANDIDATE ONLY. Not installed on any hosted database. Applies after
-- organization control (20261114100000_people_access_hardening.sql); see
-- docs/development/organization-control-rollout.md.
--
-- Sales rep to employee link. A rep is a field_sales.principals row. Its
-- employee is derived from the accepted People account link
-- (people_private.account_links), so HR stays the only place a user is tied to
-- an employee: linking, relinking or revoking there changes the label here.
-- Field Sales stores no second link. Labels are the employee's display name,
-- or "Unlinked member ····1234" (the last four characters of the user id).
-- They never carry an e-mail address.

create function field_sales.rep_label(p_tenant_id uuid, p_user_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select e.display_name from people_private.account_links as l
       join people.employees as e
         on (e.tenant_id, e.legal_entity_id, e.id) = (l.tenant_id, l.legal_entity_id, l.employee_id)
      where l.tenant_id = p_tenant_id and l.user_id = p_user_id and l.status = 'accepted'
      order by l.accepted_at desc nulls last, l.id
      limit 1),
    'Unlinked member ····' || right(p_user_id::text, 4));
$$;

-- Company read: each rep of the branch with its label and the order requests
-- it submitted in the period (company local dates, both ends included), by
-- their current state. The approved total adds the approved requests' reviewed
-- grand totals in the company's base currency and is an exact decimal string.
-- Reps are those with a customer assignment or an order request in the branch.
create function api.field_sales_reps(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_permission text;
  v_zone text;
  v_currency text;
  v_items jsonb;
begin
  v_permission := case
    when core.has_permission(p_tenant_id, 'sales.field.portfolios.manage', p_legal_entity_id, p_branch_id)
      then 'sales.field.portfolios.manage'
    else 'sales.field.discounts.decide' end;
  perform field_sales.require_company(p_tenant_id, p_legal_entity_id, p_branch_id, v_permission);
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 366 then
    raise exception using errcode = '22023', message = 'PERIOD_INVALID';
  end if;
  select le.timezone, le.currency_code into v_zone, v_currency
    from core.legal_entities as le where le.tenant_id = p_tenant_id and le.id = p_legal_entity_id;

  with reps as (
    select a.rep_id as user_id from field_sales.assignments as a
     where a.tenant_id = p_tenant_id and a.legal_entity_id = p_legal_entity_id and a.branch_id = p_branch_id
    union
    select r.rep_id from field_sales.order_requests as r
     where r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id and r.branch_id = p_branch_id
  ), requests as (
    select r.rep_id, r.state, r.preview from field_sales.order_requests as r
     where r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id and r.branch_id = p_branch_id
       and (r.created_at at time zone v_zone)::date between p_from and p_to
  ), rows as (
    select p.user_id, field_sales.rep_label(p_tenant_id, p.user_id) as label,
      exists (select 1 from people_private.account_links as l
               where l.tenant_id = p_tenant_id and l.user_id = p.user_id and l.status = 'accepted') as linked,
      (select count(*) from field_sales.assignments as a
        where a.tenant_id = p_tenant_id and a.legal_entity_id = p_legal_entity_id and a.branch_id = p_branch_id
          and a.rep_id = p.user_id
          and statement_timestamp() >= a.valid_from and statement_timestamp() < a.valid_until) as customers,
      (select count(*) from requests as q where q.rep_id = p.user_id) as submitted,
      (select count(*) from requests as q where q.rep_id = p.user_id and q.state = 'submitted') as pending,
      (select count(*) from requests as q where q.rep_id = p.user_id and q.state = 'approved') as approved,
      (select count(*) from requests as q where q.rep_id = p.user_id and q.state = 'rejected') as rejected,
      (select coalesce(sum((q.preview->'pricing'->>'grand_total')::numeric), 0)::numeric(20, 6)
         from requests as q where q.rep_id = p.user_id and q.state = 'approved'
          and q.preview->>'currency_code' = v_currency) as approved_total
    from field_sales.principals as p join reps on reps.user_id = p.user_id
    where p.tenant_id = p_tenant_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', x.user_id, 'label', x.label, 'linked', x.linked,
      'active_customer_count', x.customers::text,
      'submitted_count', x.submitted::text, 'pending_count', x.pending::text,
      'approved_count', x.approved::text, 'rejected_count', x.rejected::text,
      'approved_total', x.approved_total::text
    ) order by x.label, x.user_id), '[]'::jsonb)
    into v_items from rows as x;

  return jsonb_build_object('items', v_items, 'currency_code', v_currency,
    'from', p_from, 'to', p_to, 'as_of', statement_timestamp());
end;
$$;

revoke all on function field_sales.rep_label(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function api.field_sales_reps(uuid, uuid, uuid, date, date) from public, anon, authenticated, service_role;
grant execute on function api.field_sales_reps(uuid, uuid, uuid, date, date) to authenticated;
