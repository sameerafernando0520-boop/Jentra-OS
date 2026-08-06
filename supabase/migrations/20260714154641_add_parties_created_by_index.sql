begin;

create index parties_created_by_idx on public.parties(created_by);

commit;
