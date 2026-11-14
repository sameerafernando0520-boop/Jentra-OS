// Shared local PGlite fixture for the candidate suites. Auth and Storage are
// minimal stand-ins. No hosted database, credentials or account is touched.
import { pathToFileURL } from "node:url";

const defaultRuntime = new URL("../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js", import.meta.url);

// Application order of the organization control candidates.
export const organizationCandidates = [
  "20261105100000_organization_availability.sql",
  "20261105101000_platform_organization_control.sql",
  "20261105102000_organization_identity.sql",
  "20261105103000_platform_organization_activity.sql",
  "20261105110000_organization_lifecycle.sql",
  "20261106090000_organization_department_accounts.sql",
  "20261106100000_subscription_checkout.sql",
  "20261106101000_subscription_handover.sql",
  "20261106102000_platform_operator_identity.sql",
  "20261106103000_system_provisioning.sql",
  "20261106104000_managed_hr_identity.sql",
  "20261106105000_system_username_cutover.sql",
  "20261106106000_managed_login_membership_bridge.sql",
];

export async function openIsolatedDatabase() {
  const runtime = process.env.JENTRA_PGLITE_MODULE ? pathToFileURL(process.env.JENTRA_PGLITE_MODULE) : defaultRuntime;
  const { PGlite } = await import(runtime.href);
  const { pgcrypto } = await import(new URL("contrib/pgcrypto.js", runtime).href);
  const { btree_gist } = await import(new URL("contrib/btree_gist.js", runtime).href);
  const db = new PGlite({ extensions: { pgcrypto, btree_gist } });
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create role authenticator;
    create schema extensions;
    create schema auth;
    create schema storage;
    create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text,
      updated_at timestamptz default now(), version text, owner_id text, metadata jsonb);
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated;
    grant select,insert,update on storage.objects to authenticated;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,
      raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',
      encrypted_password text, deleted_at timestamptz, banned_until timestamptz,
      is_sso_user boolean not null default false, created_at timestamptz default clock_timestamp());
    create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,
      not_after timestamptz,created_at timestamptz not null default clock_timestamp());
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
    $$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
    grant usage on schema auth,extensions to authenticated,anon,service_role;
  `);
  return db;
}

// Applies SQL files in order. Each entry is [file name, directory URL].
export async function applySqlFiles(db, entries) {
  const { readFile } = await import("node:fs/promises");
  for (const [name, directory] of entries) {
    try { await db.exec((await readFile(new URL(name, directory), "utf8")).replaceAll("\r\n", "\n")); }
    catch (error) {
      throw new Error("Migration " + name + ": " + error.message +
        (error.where ? " (" + error.where + ")" : ""), { cause: error });
    }
  }
}

// Tracked migrations and every uninstalled candidate, in timestamp order.
export async function pendingInstall() {
  const { readdir } = await import("node:fs/promises");
  const migrations = new URL("../migrations/", import.meta.url);
  const candidates = new URL("../candidates/", import.meta.url);
  const tracked = (await readdir(migrations)).filter(name => name.endsWith(".sql") &&
    // Scheduler installation needs pg_cron and pg_net.
    name !== "20261009123000_wave5_supabase_schedule.sql").sort();
  // 20261020 is the last tracked migration date. Later candidates are not installed anywhere yet.
  const pending = (await readdir(candidates)).filter(name => /^\d{14}_.+\.sql$/.test(name) && name > "20261020999999").sort();
  return { migrations, candidates, tracked, pending };
}
