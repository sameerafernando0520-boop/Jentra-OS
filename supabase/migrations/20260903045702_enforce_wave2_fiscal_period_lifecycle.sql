-- Close the fiscal-period creation gap found during the Wave 2 omission audit.
-- All periods enter the lifecycle at `open`; later transitions remain guarded
-- by the command function and this table-level defense in depth.

create function finance.enforce_fiscal_period_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.state <> 'open' then
    raise exception using
      errcode = '55000',
      message = 'A new fiscal period must start open.';
  end if;

  if tg_op = 'UPDATE' then
    if old.state = 'hard_locked' and new.state <> 'hard_locked' then
      raise exception using
        errcode = '55000',
        message = 'A hard-locked fiscal period cannot be reopened.';
    end if;
    if old.state = 'open' and new.state = 'hard_locked' then
      raise exception using
        errcode = '55000',
        message = 'A fiscal period must be soft-locked before hard lock.';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function finance.enforce_fiscal_period_lifecycle()
  from public, anon, authenticated;

create trigger fiscal_periods_enforce_lifecycle
before insert or update of state on finance.fiscal_periods
for each row execute function finance.enforce_fiscal_period_lifecycle();
