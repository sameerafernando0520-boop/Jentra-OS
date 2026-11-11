-- UNAPPLIED CANDIDATE. Requires the six Sales candidates in their reviewed order.
-- Existing legal-entity timezone and historical document dates are unchanged.
-- Only reviewed source bodies are replaced; no client/private EXECUTE expands.
-- A single statement keeps the helper and every replacement atomic on failure.
do $business_date$
declare canonical text; helper_oid oid; oid_value oid; source text; definition text; changed text; item record;
 original_acl aclitem[]; original_owner oid; original_config text[]; original_security boolean;
begin
 if to_regclass('field_sales.delivery_challenges') is null then
  raise exception using errcode='55000',message='BUSINESS_DATE_SALES_STACK_REQUIRED';end if;
 if not has_table_privilege(current_user,'core.legal_entities','SELECT') or row_security_active('core.legal_entities') then
  raise exception using errcode='55000',message='BUSINESS_DATE_HELPER_OWNER_UNREVIEWED';end if;
 create function core.legal_entity_business_date(t uuid,e uuid,instant timestamptz default statement_timestamp())
 returns date language plpgsql stable security definer set search_path='' as $helper$
 declare zone text;
 begin
  if instant is null then raise exception using errcode='22023',message='BUSINESS_INSTANT_REQUIRED';end if;
  select timezone into zone from core.legal_entities where tenant_id=t and id=e and status='active';
  if zone is null then raise exception using errcode='42501',message='BUSINESS_DATE_SCOPE_INVALID';end if;
  return (instant at time zone zone)::date;
 end $helper$;
 revoke all on function core.legal_entity_business_date(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
 comment on function core.legal_entity_business_date(uuid,uuid,timestamptz) is
  'Private tenant/entity-scoped business date. Production callers use the statement-stable default. Only trusted SQL can supply a diagnostic instant.';
 helper_oid:='core.legal_entity_business_date(uuid,uuid,timestamptz)'::regprocedure;
 if md5(replace((select prosrc from pg_proc where oid='sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure),E'\r\n',E'\n'))<>'8ddff3cb7321b897965fafb2484d190d' then
  raise exception using errcode='55000',message='BUSINESS_DATE_WRAPPER_UNREVIEWED';end if;
 -- The complete negative-stock baseline adds a private wrapper before the
 -- field-Sales wrapper. Patch the underlying original guard, not that wrapper.
 canonical:='sales.field_flow_post_canonical(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)';
 if to_regprocedure('sales.flow_post_without_negative_policy(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)') is not null then
  if md5(replace((select prosrc from pg_proc where oid=canonical::regprocedure),E'\r\n',E'\n'))<>'22f50ae67efb18d1e80b9e6abb7db0dc' then
   raise exception using errcode='55000',message='BUSINESS_DATE_WRAPPER_UNREVIEWED';end if;
  canonical:='sales.flow_post_without_negative_policy(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)';
 end if;
 for item in select * from (values
  (canonical,array['3b6106c29047573e9dd4d5eda836dc76'],
   '(clock_timestamp() at time zone ''UTC'')::date','core.legal_entity_business_date(p_tenant_id,p_legal_entity_id)',false),
  ('sales.flow_post_stock(text,jsonb,uuid,uuid)',array['91187f7132e052ea9c431fbf89612ba7','fd7fe803a1965f45ee765fac9a8e54a8'],
   '(clock_timestamp() at time zone ''UTC'')::date','core.legal_entity_business_date(v_t,v_e)',false),
  ('finance.flow_refresh_credit(jsonb)',array['c3a76a7509d0de928f44f0b6d28597d3'],
   '(clock_timestamp() at time zone ''UTC'')::date','(select core.legal_entity_business_date(v_t,v_e))',false),
  ('finance.flow_post_journal(jsonb,jsonb,text,uuid,uuid,uuid)',array['f8fe8c78748d3a2d0f38368de51892d8','ad660b7a6933afa631774346be657e8d'],
   'if jsonb_array_length(p_lines)=0 then return null;end if;',
   'if jsonb_array_length(p_lines)=0 then return null;end if;
 if v_date>core.legal_entity_business_date(v_t,v_e) then raise exception using errcode=''22023'',message=''FUTURE_POSTING_DATE'';end if;',true)
 ) reviewed(signature,hashes,old_fragment,new_fragment,public_execute_allowed)
 loop
  oid_value:=to_regprocedure(item.signature);
  if oid_value is null then raise exception using errcode='55000',message='BUSINESS_DATE_FUNCTION_REQUIRED';end if;
  select replace(prosrc,E'\r\n',E'\n'),proacl,proowner,proconfig,prosecdef
   into source,original_acl,original_owner,original_config,original_security from pg_proc where oid=oid_value;
  if not md5(source)=any(item.hashes) then
   raise exception using errcode='55000',message='BUSINESS_DATE_SOURCE_UNREVIEWED',detail=item.signature;end if;
  -- Journal's historical default PUBLIC function ACL is retained; its schema
  -- access remains unchanged. Every other target must have owner-only EXECUTE.
  if not original_security or original_config is distinct from array['search_path=""'] or exists(select 1 from aclexplode(coalesce(original_acl,acldefault('f',original_owner))) a
   where a.privilege_type='EXECUTE' and a.grantee<>original_owner
    and (not item.public_execute_allowed or a.grantee<>0)) then
   raise exception using errcode='55000',message='BUSINESS_DATE_ACL_UNREVIEWED',detail=item.signature;end if;
  if not has_schema_privilege(original_owner,'core','USAGE') or not has_function_privilege(original_owner,helper_oid,'EXECUTE') then
   raise exception using errcode='55000',message='BUSINESS_DATE_DEFINER_OWNER_UNREVIEWED',detail=item.signature;end if;
  if (length(source)-length(replace(source,item.old_fragment,'')))<>length(item.old_fragment) then
   raise exception using errcode='55000',message='BUSINESS_DATE_FRAGMENT_UNREVIEWED',detail=item.signature;end if;
  changed:=replace(source,item.old_fragment,item.new_fragment);
  definition:=replace(pg_get_functiondef(oid_value),E'\r\n',E'\n');
  if (length(definition)-length(replace(definition,source,'')))<>length(source) then
   raise exception using errcode='55000',message='BUSINESS_DATE_DEFINITION_UNREVIEWED';end if;
  execute replace(definition,source,changed);
  if exists(select 1 from pg_proc where oid=oid_value and
   (proacl is distinct from original_acl or proowner<>original_owner or proconfig is distinct from original_config or prosecdef<>original_security)) then
   raise exception using errcode='55000',message='BUSINESS_DATE_IDENTITY_CHANGED';end if;
 end loop;
end $business_date$;
