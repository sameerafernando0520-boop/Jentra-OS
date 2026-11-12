-- Backup receipts intentionally survive organization deletion. No tenant
-- business rows, credentials or plaintext archives are stored here.
create schema organization_lifecycle;
revoke all on schema organization_lifecycle from public, anon, authenticated;

create table organization_lifecycle.locks (
  tenant_id uuid primary key references core.tenants(id),
  lock_id uuid not null unique default gen_random_uuid(),
  previous_status text not null check (previous_status in ('active', 'trial')),
  locked_at timestamptz not null default clock_timestamp(),
  purge_backup_id uuid
);

create table organization_lifecycle.backups (
  id uuid primary key,
  tenant_id uuid not null,
  lock_id uuid not null,
  database_sha256 text not null check (database_sha256 ~ '^[0-9a-f]{64}$'),
  archive_sha256 text not null check (archive_sha256 ~ '^[0-9a-f]{64}$'),
  download_sha256 text not null check (download_sha256 ~ '^[0-9a-f]{64}$'),
  archive_bytes bigint not null check (archive_bytes between 29 and 41943040),
  files jsonb not null check (jsonb_typeof(files) = 'array'),
  created_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table organization_lifecycle.events (
  id uuid primary key default gen_random_uuid(),
  organization_ref uuid not null,
  actor_id uuid not null,
  action text not null check (action in ('lock', 'unlock', 'backup', 'purge_start', 'purge')),
  reason text,
  backup_id uuid,
  recorded_at timestamptz not null default clock_timestamp()
);
create table organization_lifecycle.identity_cleanup (
  backup_id uuid not null references organization_lifecycle.backups(id),
  user_id uuid not null,
  primary key (backup_id, user_id),
  unique (user_id)
);
revoke all on all tables in schema organization_lifecycle from public, anon, authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('jentra-organization-archives', 'jentra-organization-archives', false,
        41943040, array['application/octet-stream']);

-- Include every tenant-keyed table in application schemas. A related row
-- without an explicit scope key is refused by the foreign-key preflight.
create function organization_lifecycle.relations()
returns table (relid oid, qualified_name text, scope_column text)
language sql stable security definer set search_path = '' as $$
  select c.oid, format('%I.%I', n.nspname, c.relname),
         case when c.oid = 'core.tenants'::regclass then 'id' else 'tenant_id' end
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p') and not c.relispartition
    and n.nspname not in ('auth', 'storage', 'organization_lifecycle',
                         'extensions', 'realtime', 'vault', 'supabase_migrations')
    and n.nspname !~ '^(pg_|information_schema$)'
    and (c.oid = 'core.tenants'::regclass or exists (
      select 1 from pg_attribute a where a.attrelid = c.oid
        and a.attname = 'tenant_id' and a.atttypid = 'uuid'::regtype and not a.attisdropped
    ));
$$;

create function organization_lifecycle.enforce_write_lock(p_tenant_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if p_tenant_id is null then return; end if;
  -- FOR SHARE conflicts with the lock/unlock state update and holds until
  -- commit, so writes already in flight cannot cross the freeze.
  select status into v_status from core.tenants where id = p_tenant_id for share;
  if v_status is not null and v_status not in ('active', 'trial') then
    raise exception using errcode = '42501', message = 'ORGANIZATION_LOCKED';
  end if;
end;
$$;

create function organization_lifecycle.check_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_relid = 'core.memberships'::regclass and tg_op <> 'DELETE' then
    if exists (select 1 from organization_lifecycle.identity_cleanup
               where user_id = (to_jsonb(new)->>'user_id')::uuid) then
      raise exception using errcode = '42501', message = 'ORGANIZATION_IDENTITY_RETIRING';
    end if;
  end if;
  if tg_op <> 'INSERT' then
    perform organization_lifecycle.enforce_write_lock(old.tenant_id);
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.tenant_id is distinct from old.tenant_id) then
    perform organization_lifecycle.enforce_write_lock(new.tenant_id);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create function organization_lifecycle.check_storage_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    perform organization_lifecycle.enforce_write_lock(core.storage_object_tenant(old.name));
  end if;
  perform organization_lifecycle.enforce_write_lock(core.storage_object_tenant(new.name));
  return new;
end;
$$;

-- Do not remove Storage objects via SQL. This trigger only prevents new
-- uploads or overwrites during the freeze, including service-role writes.
create trigger organization_storage_write_lock before insert or update on storage.objects
  for each row execute function organization_lifecycle.check_storage_write();

create function organization_lifecycle.install_write_guards()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select * from organization_lifecycle.relations() where scope_column = 'tenant_id'
  loop
    if not exists (select 1 from pg_trigger where tgrelid = r.relid
                   and tgname = 'organization_write_lock') then
      execute format('create trigger organization_write_lock before insert or update or delete on %s '
                     'for each row execute function organization_lifecycle.check_write()', r.qualified_name);
    end if;
    if exists (select 1 from pg_class where oid = r.relid and relrowsecurity)
       and not exists (select 1 from pg_policy where polrelid = r.relid
                      and polname = 'organization_online_access') then
      execute format('create policy organization_online_access on %s as restrictive '
                     'to authenticated using (%I is null or core.organization_available(%I))',
                     r.qualified_name, r.scope_column, r.scope_column);
    end if;
  end loop;
end;
$$;
select organization_lifecycle.install_write_guards();

create function organization_lifecycle.assert_inventory()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (
    select 1 from organization_lifecycle.relations() r
    where r.scope_column = 'tenant_id' and not exists (
      select 1 from pg_trigger where tgrelid = r.relid and tgname = 'organization_write_lock'
        and tgfoid = 'organization_lifecycle.check_write()'::regprocedure and tgenabled in ('O', 'A')
    )
  ) then
    raise exception using errcode = '55000', message = 'ORGANIZATION_INVENTORY_NOT_READY';
  end if;
end;
$$;

create function api.platform_set_organization_lock(p_tenant_id uuid, p_locked boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_status text; v_lock organization_lifecycle.locks%rowtype;
begin
  perform intelligence_control.operator_required('organization');
  if p_locked is null or p_reason is null or length(btrim(p_reason)) not between 10 and 500 then
    raise exception using errcode = '22023', message = 'ORGANIZATION_LOCK_REASON_REQUIRED';
  end if;
  perform organization_lifecycle.assert_inventory();
  select status into v_status from core.tenants where id = p_tenant_id for update;
  if v_status is null then
    raise exception using errcode = '22023', message = 'ORGANIZATION_NOT_FOUND';
  end if;
  select * into v_lock from organization_lifecycle.locks where tenant_id = p_tenant_id;
  if v_lock.purge_backup_id is not null then
    raise exception using errcode = '55000', message = 'ORGANIZATION_PURGE_IN_PROGRESS';
  end if;
  if p_locked and v_status in ('active', 'trial') then
    insert into organization_lifecycle.locks(tenant_id, previous_status) values (p_tenant_id, v_status);
    update core.tenants set status = 'suspended' where id = p_tenant_id;
  elsif not p_locked and v_status = 'suspended' and v_lock.lock_id is not null then
    update core.tenants set status = v_lock.previous_status where id = p_tenant_id;
    delete from organization_lifecycle.locks where tenant_id = p_tenant_id;
  elsif v_lock.lock_id is not null and v_status = 'suspended' and p_locked
     or v_lock.lock_id is null and v_status in ('active', 'trial') and not p_locked then
    return jsonb_build_object('locked', p_locked);
  else
    raise exception using errcode = '55000', message = 'ORGANIZATION_LOCK_STATE_INVALID';
  end if;
  insert into organization_lifecycle.events(organization_ref, actor_id, action, reason)
  values (p_tenant_id, auth.uid(), case when p_locked then 'lock' else 'unlock' end, btrim(p_reason));
  return jsonb_build_object('locked', p_locked);
end;
$$;

create function api.platform_organization_lifecycle_authorize()
returns uuid language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return auth.uid();
end;
$$;

create function api.platform_organization_backups(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_data jsonb;
begin
  perform intelligence_control.operator_required('organization');
  select jsonb_build_object(
    'locked', exists (select 1 from organization_lifecycle.locks where tenant_id = p_tenant_id),
    'purge_backup_id', (select purge_backup_id from organization_lifecycle.locks
      where tenant_id = p_tenant_id),
    'backups', coalesce(jsonb_agg(to_jsonb(b) order by created_at desc), '[]'))
  into v_data from (
    select id as backup_id, download_sha256 as sha256, archive_bytes - 28 as bytes, created_at,
      deleted_at is not null as deleted,
      lock_id = (select l.lock_id from organization_lifecycle.locks l
        where l.tenant_id = p_tenant_id)
        and created_at >= statement_timestamp() - interval '24 hours' as current
    from organization_lifecycle.backups where tenant_id = p_tenant_id
    order by created_at desc limit 20
  ) b;
  return v_data;
end;
$$;

create function api.platform_organization_cleanup_pending()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return (select coalesce(jsonb_agg(to_jsonb(p) order by created_at desc), '[]')
    from (select b.tenant_id, b.id as backup_id, b.created_at
      from organization_lifecycle.backups b where exists (
        select 1 from organization_lifecycle.identity_cleanup j where j.backup_id = b.id
      ) order by b.created_at desc limit 20) p);
end;
$$;

create function api.platform_organization_archive_history()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return (select coalesce(jsonb_agg(to_jsonb(p) order by deleted_at desc, created_at desc), '[]')
    from (select tenant_id, id as backup_id, download_sha256 as sha256,
      archive_bytes - 28 as bytes, created_at, deleted_at
      from organization_lifecycle.backups where deleted_at is not null
      order by deleted_at desc, created_at desc limit 50) p);
end;
$$;

create function organization_lifecycle.storage_manifest(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' set timezone = 'UTC' as $$
declare v_files jsonb;
begin
  if exists (
    select 1 from storage.objects where core.storage_object_tenant(name) = p_tenant_id
      and bucket_id not in ('jentra-attachments', 'jentra-hr-private', 'jentra-project-expense-private')
  ) then
    raise exception using errcode = '55000', message = 'ORGANIZATION_STORAGE_BUCKET_UNCLASSIFIED';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'bucket', bucket_id, 'name', name, 'id', id, 'version', version,
    'updated_at', updated_at, 'size', metadata->>'size') order by bucket_id, name), '[]')
  into v_files from storage.objects where core.storage_object_tenant(name) = p_tenant_id;
  if jsonb_array_length(v_files) > 500 then
    raise exception using errcode = '54000', message = 'ORGANIZATION_ARCHIVE_TOO_LARGE';
  end if;
  return v_files;
end;
$$;

create function organization_lifecycle.database_snapshot(p_tenant_id uuid)
returns text language plpgsql stable security definer set search_path = '' set timezone = 'UTC' as $$
declare r record; v_rows jsonb; v_data jsonb := '{}'; v_bytes bigint := 0;
begin
  perform organization_lifecycle.assert_inventory();
  for r in select * from organization_lifecycle.relations() order by qualified_name
  loop
    execute format('select coalesce(jsonb_agg(v order by v::text collate "C"), ''[]'') '
      'from (select to_jsonb(d) v from %s d where %I = $1 limit 10001) scope',
      r.qualified_name, r.scope_column) into v_rows using p_tenant_id;
    if jsonb_array_length(v_rows) > 10000 then
      raise exception using errcode = '54000', message = 'ORGANIZATION_ARCHIVE_TOO_LARGE';
    end if;
    v_bytes := v_bytes + octet_length(v_rows::text);
    if v_bytes > 8388608 then
      raise exception using errcode = '54000', message = 'ORGANIZATION_ARCHIVE_TOO_LARGE';
    end if;
    v_data := v_data || jsonb_build_object(r.qualified_name, v_rows);
  end loop;
  return v_data::text;
end;
$$;

create function organization_lifecycle.require_locked(p_tenant_id uuid)
returns organization_lifecycle.locks
language plpgsql security definer set search_path = '' as $$
declare v_lock organization_lifecycle.locks%rowtype;
begin
  perform 1 from core.tenants where id = p_tenant_id and status = 'suspended' for update;
  if not found then
    raise exception using errcode = '55000', message = 'ORGANIZATION_LOCK_REQUIRED';
  end if;
  select * into v_lock from organization_lifecycle.locks where tenant_id = p_tenant_id for update;
  if v_lock.lock_id is null then
    raise exception using errcode = '55000', message = 'ORGANIZATION_LOCK_REQUIRED';
  end if;
  return v_lock;
end;
$$;

create function api.platform_organization_archive_snapshot(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_lock organization_lifecycle.locks%rowtype; v_db text;
begin
  v_lock := organization_lifecycle.require_locked(p_tenant_id);
  if v_lock.purge_backup_id is not null then
    raise exception using errcode = '55000', message = 'ORGANIZATION_PURGE_IN_PROGRESS';
  end if;
  perform organization_lifecycle.assert_purge_scope(p_tenant_id);
  v_db := organization_lifecycle.database_snapshot(p_tenant_id);
  return jsonb_build_object('lock_id', v_lock.lock_id, 'previous_status', v_lock.previous_status, 'database_json', v_db,
    'database_sha256', encode(sha256(convert_to(v_db, 'UTF8')), 'hex'),
    'files', organization_lifecycle.storage_manifest(p_tenant_id));
end;
$$;

create function api.platform_organization_backup_commit(
  p_tenant_id uuid, p_backup_id uuid, p_lock_id uuid, p_actor_id uuid,
  p_database_sha256 text, p_archive_sha256 text, p_download_sha256 text,
  p_archive_bytes bigint, p_files jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_lock organization_lifecycle.locks%rowtype; v_created_at timestamptz;
begin
  v_lock := organization_lifecycle.require_locked(p_tenant_id);
  perform organization_lifecycle.assert_purge_scope(p_tenant_id);
  if v_lock.lock_id is distinct from p_lock_id or v_lock.purge_backup_id is not null
     or p_files is distinct from organization_lifecycle.storage_manifest(p_tenant_id)
     or p_database_sha256 is distinct from encode(sha256(convert_to(
          organization_lifecycle.database_snapshot(p_tenant_id), 'UTF8')), 'hex') then
    raise exception using errcode = '55000', message = 'ORGANIZATION_ARCHIVE_STALE';
  end if;
  if not exists (select 1 from storage.objects
    where bucket_id = 'jentra-organization-archives' and name = p_backup_id::text || '.bin') then
    raise exception using errcode = '55000', message = 'ORGANIZATION_ARCHIVE_UNAVAILABLE';
  end if;
  insert into organization_lifecycle.backups(id, tenant_id, lock_id, database_sha256,
    archive_sha256, download_sha256, archive_bytes, files) values (p_backup_id, p_tenant_id, p_lock_id,
    p_database_sha256, p_archive_sha256, p_download_sha256, p_archive_bytes, p_files)
    returning created_at into v_created_at;
  insert into organization_lifecycle.events(organization_ref, actor_id, action, backup_id)
    values (p_tenant_id, p_actor_id, 'backup', p_backup_id);
  return jsonb_build_object('backup_id', p_backup_id, 'sha256', p_download_sha256,
                            'created_at', v_created_at, 'bytes', p_archive_bytes - 28);
end;
$$;

create function api.platform_organization_backup_lookup(p_tenant_id uuid, p_backup_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_backup organization_lifecycle.backups%rowtype;
begin
  select * into v_backup from organization_lifecycle.backups
    where id = p_backup_id and tenant_id = p_tenant_id;
  if not found then
    raise exception using errcode = '22023', message = 'ORGANIZATION_ARCHIVE_NOT_FOUND';
  end if;
  return jsonb_build_object('archive_sha256', v_backup.archive_sha256, 'sha256', v_backup.download_sha256,
    'bytes', v_backup.archive_bytes,
    'created_at', v_backup.created_at, 'deleted', v_backup.deleted_at is not null);
end;
$$;

-- Refuse any inbound reference from outside the exact deletion set, even
-- if the FK declares CASCADE or SET NULL. These rows belong to a different
-- tenant or have not been explicitly classified as tenant data.
create function organization_lifecycle.assert_purge_scope(p_tenant_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r record; v_conflict boolean;
begin
  perform organization_lifecycle.assert_inventory();
  for r in
    select con.conrelid::regclass as child, parent.qualified_name as parent,
      parent.scope_column as parent_scope, child.scope_column as child_scope,
      string_agg(format('c.%I = p.%I', src.attname, dst.attname), ' and ' order by k.ord) as match_columns
    from pg_constraint con
    join organization_lifecycle.relations() parent on parent.relid = con.confrelid
    left join organization_lifecycle.relations() child on child.relid = con.conrelid
    cross join lateral unnest(con.conkey, con.confkey) with ordinality k(src, dst, ord)
    join pg_attribute src on src.attrelid = con.conrelid and src.attnum = k.src
    join pg_attribute dst on dst.attrelid = con.confrelid and dst.attnum = k.dst
    where con.contype = 'f' and con.conrelid <> 'organization_lifecycle.locks'::regclass
    group by con.oid, con.conrelid, parent.qualified_name, parent.scope_column, child.scope_column
  loop
    execute format('select exists (select 1 from %s c join %s p on %s where p.%I = $1%s)',
      r.child, r.parent, r.match_columns, r.parent_scope,
      case when r.child_scope is null then '' else format(' and c.%I is distinct from $1', r.child_scope) end)
      into v_conflict using p_tenant_id;
    if v_conflict then
      raise exception using errcode = '55000', message = 'ORGANIZATION_PURGE_SCOPE_CONFLICT';
    end if;
  end loop;
end;
$$;

create function api.platform_organization_purge_begin(
  p_tenant_id uuid, p_backup_id uuid, p_actor_id uuid, p_confirmation_slug text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_lock organization_lifecycle.locks%rowtype;
  v_backup organization_lifecycle.backups%rowtype; v_files jsonb;
begin
  v_lock := organization_lifecycle.require_locked(p_tenant_id);
  if not exists (select 1 from core.tenants where id = p_tenant_id and slug = p_confirmation_slug) then
    raise exception using errcode = '22023', message = 'ORGANIZATION_CONFIRMATION_MISMATCH';
  end if;
  select * into v_backup from organization_lifecycle.backups
    where id = p_backup_id and tenant_id = p_tenant_id and lock_id = v_lock.lock_id;
  if not found or (v_lock.purge_backup_id is null and
      v_backup.created_at < clock_timestamp() - interval '24 hours') then
    raise exception using errcode = '55000', message = 'ORGANIZATION_CURRENT_BACKUP_REQUIRED';
  end if;
  if v_lock.purge_backup_id is not null and v_lock.purge_backup_id <> p_backup_id then
    raise exception using errcode = '55000', message = 'ORGANIZATION_PURGE_IN_PROGRESS';
  end if;
  v_files := organization_lifecycle.storage_manifest(p_tenant_id);
  if v_backup.database_sha256 is distinct from encode(sha256(convert_to(
          organization_lifecycle.database_snapshot(p_tenant_id), 'UTF8')), 'hex')
     or (v_lock.purge_backup_id is null and v_files <> v_backup.files)
     or not v_files <@ v_backup.files then
    raise exception using errcode = '55000', message = 'ORGANIZATION_ARCHIVE_STALE';
  end if;
  perform organization_lifecycle.assert_purge_scope(p_tenant_id);
  if v_lock.purge_backup_id is null then
    update organization_lifecycle.locks set purge_backup_id = p_backup_id where tenant_id = p_tenant_id;
    insert into organization_lifecycle.events(organization_ref, actor_id, action, backup_id)
      values (p_tenant_id, p_actor_id, 'purge_start', p_backup_id);
  end if;
  return jsonb_build_object('files', v_files);
end;
$$;

create function api.platform_organization_purge_finish(p_tenant_id uuid, p_backup_id uuid, p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '3s' as $$
declare r record; v_lock organization_lifecycle.locks%rowtype;
  v_commands text[] := '{}'; v_restore text[] := '{}'; v_sql text;
  v_users uuid[];
begin
  v_lock := organization_lifecycle.require_locked(p_tenant_id);
  if v_lock.purge_backup_id is distinct from p_backup_id
     or organization_lifecycle.storage_manifest(p_tenant_id) <> '[]'::jsonb then
    raise exception using errcode = '55000', message = 'ORGANIZATION_PURGE_NOT_READY';
  end if;
  -- Prevent new inbound references while preflighting and deleting. A busy
  -- database times out and leaves the locked, backed-up operation retryable.
  for r in
    select qualified_name from organization_lifecycle.relations()
    union
    select conrelid::regclass::text from pg_constraint
      where contype = 'f' and confrelid in (select relid from organization_lifecycle.relations())
        and conrelid not in (select relid from organization_lifecycle.relations())
    order by 1
  loop
    execute format('lock table %s in share row exclusive mode', r.qualified_name);
  end loop;
  delete from organization_lifecycle.locks where tenant_id = p_tenant_id;
  perform organization_lifecycle.assert_purge_scope(p_tenant_id);
  if not exists (select 1 from organization_lifecycle.backups b
      where b.id = p_backup_id and b.tenant_id = p_tenant_id and b.lock_id = v_lock.lock_id
        and b.database_sha256 = encode(sha256(convert_to(
          organization_lifecycle.database_snapshot(p_tenant_id), 'UTF8')), 'hex')) then
    raise exception using errcode = '55000', message = 'ORGANIZATION_ARCHIVE_STALE';
  end if;
  select array_agg(a.user_id) into v_users from core.organization_administrator_logins a
  where a.tenant_id = p_tenant_id and not exists (
    select 1 from core.memberships m where m.user_id = a.user_id and m.tenant_id <> p_tenant_id
  );

  -- Audit and posted-document triggers prevent normal deletes. Disable only
  -- user DELETE triggers on tables with rows in this exact deletion set,
  -- under transaction-held table locks. Internal foreign keys stay enabled.
  for r in select * from organization_lifecycle.relations() order by qualified_name
  loop
    declare v_has_rows boolean; v_trigger record;
    begin
      execute format('select exists(select 1 from %s where %I = $1)', r.qualified_name, r.scope_column)
        into v_has_rows using p_tenant_id;
      if not v_has_rows then continue; end if;
      for v_trigger in select tgname, tgenabled from pg_trigger where tgrelid = r.relid
        and not tgisinternal and (tgtype & 8) = 8 and tgenabled <> 'D'
      loop
        execute format('alter table %s disable trigger %I', r.qualified_name, v_trigger.tgname);
        v_restore := array_append(v_restore, format('alter table %s enable %s trigger %I',
          r.qualified_name, case v_trigger.tgenabled when 'A' then 'always'
            when 'R' then 'replica' else '' end, v_trigger.tgname));
      end loop;
      v_commands := array_append(v_commands, format('d%s as (delete from %s where %I = $1)',
        cardinality(v_commands), r.qualified_name, r.scope_column));
    end;
  end loop;
  -- One statement allows cyclic NO ACTION references within the deletion set.
  set constraints all immediate;
  execute 'with ' || array_to_string(v_commands, ',') || ' select 1' using p_tenant_id;
  foreach v_sql in array v_restore loop execute v_sql; end loop;
  insert into organization_lifecycle.identity_cleanup(backup_id, user_id)
    select p_backup_id, u from unnest(v_users) u;
  update organization_lifecycle.backups set files = '[]', deleted_at = clock_timestamp()
    where tenant_id = p_tenant_id;
  insert into organization_lifecycle.events(organization_ref, actor_id, action, backup_id)
    values (p_tenant_id, p_actor_id, 'purge', p_backup_id);
  update organization_lifecycle.events set reason = null where organization_ref = p_tenant_id;
  return jsonb_build_object('deleted', true);
end;
$$;

-- Only identities created for this organization are candidates. Existing
-- users, shared memberships and accounts with other live business references
-- remain. No auth schema rows are changed directly by the lifecycle SQL.
create function api.platform_organization_purge_identity_queue(p_tenant_id uuid, p_backup_id uuid)
returns uuid[] language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_result uuid[] := '{}'; r record; v_shared boolean;
begin
  if not exists (select 1 from organization_lifecycle.backups
    where tenant_id = p_tenant_id and id = p_backup_id and deleted_at is not null) then
    raise exception using errcode = '55000', message = 'ORGANIZATION_PURGE_NOT_READY';
  end if;
  for v_user in select user_id from organization_lifecycle.identity_cleanup where backup_id = p_backup_id
  loop
    v_shared := exists (select 1 from storage.objects where owner_id = v_user::text);
    for r in
      select con.conrelid::regclass as relation, a.attname as field
      from pg_constraint con
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
      join pg_attribute target on target.attrelid = con.confrelid and target.attnum = con.confkey[1]
      where con.contype = 'f' and con.confrelid = 'auth.users'::regclass
        and cardinality(con.conkey) = 1 and target.attname = 'id'
        and n.nspname <> 'auth'
        and not (con.confdeltype = 'c' and con.conrelid in (
          'core.organization_account_recovery'::regclass,
          'core.organization_identity_challenges'::regclass
        ))
    loop
      exit when v_shared;
      execute format('select exists(select 1 from %s where %I = $1)', r.relation, r.field)
        into v_shared using v_user;
    end loop;
    if v_shared or not exists (select 1 from auth.users where id = v_user) then
      delete from organization_lifecycle.identity_cleanup where backup_id = p_backup_id and user_id = v_user;
    else
      v_result := array_append(v_result, v_user);
    end if;
  end loop;
  return v_result;
end;
$$;

create function api.platform_organization_purge_identity_done(p_backup_id uuid, p_user_id uuid)
returns void language sql security definer set search_path = '' as $$
  delete from organization_lifecycle.identity_cleanup where backup_id = p_backup_id and user_id = p_user_id;
$$;

revoke all on all functions in schema organization_lifecycle from public, anon, authenticated;
revoke all on function api.platform_set_organization_lock(uuid, boolean, text),
  api.platform_organization_lifecycle_authorize(),
  api.platform_organization_backups(uuid),
  api.platform_organization_cleanup_pending(),
  api.platform_organization_archive_history(),
  api.platform_organization_archive_snapshot(uuid),
  api.platform_organization_backup_commit(uuid,uuid,uuid,uuid,text,text,text,bigint,jsonb),
  api.platform_organization_backup_lookup(uuid,uuid),
  api.platform_organization_purge_begin(uuid,uuid,uuid,text),
  api.platform_organization_purge_finish(uuid,uuid,uuid),
  api.platform_organization_purge_identity_queue(uuid,uuid),
  api.platform_organization_purge_identity_done(uuid,uuid) from public, anon, authenticated;
grant execute on function api.platform_set_organization_lock(uuid, boolean, text),
  api.platform_organization_lifecycle_authorize(), api.platform_organization_backups(uuid),
  api.platform_organization_cleanup_pending(), api.platform_organization_archive_history() to authenticated;
grant execute on function api.platform_organization_archive_snapshot(uuid),
  api.platform_organization_backup_commit(uuid,uuid,uuid,uuid,text,text,text,bigint,jsonb),
  api.platform_organization_backup_lookup(uuid,uuid),
  api.platform_organization_purge_begin(uuid,uuid,uuid,text),
  api.platform_organization_purge_finish(uuid,uuid,uuid),
  api.platform_organization_purge_identity_queue(uuid,uuid),
  api.platform_organization_purge_identity_done(uuid,uuid) to service_role;
