create or replace function workflow.lifecycle_contract_valid(p_lifecycle jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_lifecycle) <> 'object'
      or jsonb_typeof(p_lifecycle->'states') <> 'array'
      or jsonb_typeof(p_lifecycle->'transitions') <> 'array'
    then false
    else
      (p_lifecycle->'states') @> '[
        "draft", "submitted", "approved", "rejected", "posted",
        "settled", "fulfilled", "closed", "cancelled", "reversed"
      ]'::jsonb
      and jsonb_array_length(p_lifecycle->'transitions') > 0
      and not exists (
        select 1
        from jsonb_array_elements(p_lifecycle->'transitions') as transition(value)
        where case
          when jsonb_typeof(transition.value) <> 'array' then true
          when jsonb_array_length(transition.value) <> 2 then true
          else transition.value not in (
              '["draft", "submitted"]'::jsonb,
              '["draft", "cancelled"]'::jsonb,
              '["submitted", "approved"]'::jsonb,
              '["submitted", "rejected"]'::jsonb,
              '["submitted", "cancelled"]'::jsonb,
              '["rejected", "draft"]'::jsonb,
              '["rejected", "cancelled"]'::jsonb,
              '["approved", "posted"]'::jsonb,
              '["approved", "cancelled"]'::jsonb,
              '["posted", "settled"]'::jsonb,
              '["posted", "fulfilled"]'::jsonb,
              '["posted", "closed"]'::jsonb,
              '["posted", "reversed"]'::jsonb,
              '["settled", "closed"]'::jsonb,
              '["fulfilled", "closed"]'::jsonb
            )
        end
      )
  end;
$$;

revoke all on function workflow.lifecycle_contract_valid(jsonb) from public, anon, authenticated;

create or replace function workflow.enforce_lifecycle_contract()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not workflow.lifecycle_contract_valid(new.lifecycle) then
    raise exception using
      errcode = '22023',
      message = 'Workflow lifecycle is invalid.';
  end if;
  return new;
end;
$$;

revoke all on function workflow.enforce_lifecycle_contract() from public, anon, authenticated;

drop trigger if exists workflow_definitions_lifecycle_contract
  on workflow.workflow_definitions;
create trigger workflow_definitions_lifecycle_contract
before insert or update of lifecycle on workflow.workflow_definitions
for each row execute function workflow.enforce_lifecycle_contract();

alter table workflow.workflow_definitions
  drop constraint if exists workflow_definitions_lifecycle_contract_check;
alter table workflow.workflow_definitions
  add constraint workflow_definitions_lifecycle_contract_check
  check (workflow.lifecycle_contract_valid(lifecycle)) not valid;
alter table workflow.workflow_definitions
  validate constraint workflow_definitions_lifecycle_contract_check;
