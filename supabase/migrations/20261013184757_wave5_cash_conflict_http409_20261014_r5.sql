-- SOURCE CANDIDATE ONLY. Not an approved/installed migration.
-- Project xpdoufauvrbdmxgngetv. Requires separate exact-byte review/approval.
-- Five custom cash conflicts become PT409; genuine serialization errors and
-- all other routines remain untouched. Original reviewed migrations stay frozen.
-- Function bodies must match the reviewed source fingerprints before any DDL.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $cash_conflict_http409$
declare
 target record;
 function_oid oid;
 before_row pg_catalog.pg_proc%rowtype;
 after_row pg_catalog.pg_proc%rowtype;
 definition text;
 message_code text;
 old_clause text;
 new_clause text;
begin
 for target in
  select * from (values
   ('api.wave5_cash_date_command(uuid,uuid,uuid,uuid,uuid,timestamp with time zone,text,jsonb)',
    '509d9f2ef975ca30a355b6874603e1469564107eed911267454de54607e4a149',
    '9c87b6aaf874e0a5061b7710b9341240ba982fc26731fe1e99f00646039bf482',
    array['CASH_DATE_VERSION_CONFLICT','CASH_DATE_SOURCE_CHANGED','CASH_DATE_PROPOSAL_CHANGED']),
   ('api.wave5_cash_save_v2(uuid,uuid,uuid,uuid,text,jsonb)',
    'a9e13fb88a940206bb7fc9d804f5dafd591fea5dce138a688f251fb5be684c91',
    '98c96ad97956117996c8874d2ff8e1e7e69d827e72f71757c68034d1e5780564',
    array['SOURCE_BASIS_CHANGED'])
  ) as targets(signature,before_hash,after_hash,messages)
 loop
  function_oid:=pg_catalog.to_regprocedure(target.signature);
  if function_oid is null then
   raise exception using errcode='22023',message='CASH_CONFLICT_PATCH_FUNCTION_MISSING';
  end if;
  select * into strict before_row from pg_catalog.pg_proc where oid=function_oid;
  if before_row.prosecdef is distinct from true
   or before_row.proconfig is distinct from array['search_path=""']::text[]
   or pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
    pg_catalog.replace(before_row.prosrc,E'\r\n',E'\n'),'UTF8'),'sha256'),'hex')
    is distinct from target.before_hash then
   raise exception using errcode='22023',message='CASH_CONFLICT_PATCH_SOURCE_GUARD_FAILED';
  end if;

  -- pg_get_functiondef keeps the installed signature, attributes and body.
  -- CREATE OR REPLACE retains the existing object, owner and ACL; every other
  -- pg_proc field is additionally compared after the exact literal changes.
  definition:=pg_catalog.pg_get_functiondef(function_oid);
  foreach message_code in array target.messages loop
   old_clause:='errcode=''40001'',message='''||message_code||'''';
   new_clause:='errcode=''PT409'',message='''||message_code||'''';
   if pg_catalog.strpos(before_row.prosrc,old_clause)=0 then
    raise exception using errcode='22023',message='CASH_CONFLICT_PATCH_CLAUSE_MISSING';
   end if;
   definition:=pg_catalog.replace(definition,old_clause,new_clause);
  end loop;
  execute definition;

  select * into strict after_row from pg_catalog.pg_proc where oid=function_oid;
  if pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
    pg_catalog.replace(after_row.prosrc,E'\r\n',E'\n'),'UTF8'),'sha256'),'hex')
    is distinct from target.after_hash
   or (pg_catalog.to_jsonb(before_row)-'prosrc')
    is distinct from (pg_catalog.to_jsonb(after_row)-'prosrc') then
   raise exception using errcode='22023',message='CASH_CONFLICT_PATCH_POSTCHECK_FAILED';
  end if;
 end loop;
end
$cash_conflict_http409$;

commit;
