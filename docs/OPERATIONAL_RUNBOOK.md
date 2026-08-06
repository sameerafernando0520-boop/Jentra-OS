# Jentra OS — Operational Runbook

This operational runbook provides standard operating procedures for deploying, maintaining, and supporting Jentra OS in production.

---

## 1. Database Operations & Migration Policy

### Migration Verification Order
Always run migrations through standard local pipeline before hosted deployment:
```powershell
supabase start
supabase db reset
supabase test db
supabase db push --dry-run
```

### Safety Invariants
1. All tables must have Row-Level Security (`RLS`) enabled with `SELECT` policies for `company_id`.
2. Public RPC functions must use `SECURITY DEFINER` with explicit `search_path` and `private.is_company_member` checks on entry.
3. Revoke direct write permissions (`INSERT`, `UPDATE`, `DELETE`) from `authenticated` on core financial and inventory balance tables (`stock_balances`, `journal_entries`, `journal_lines`, `company_subscriptions`, `audit_logs`).

---

## 2. Secrets & Credential Safety

- Flutter client builds must **only** receive:
  - `SUPABASE_URL`
  - `SUPABASE_PUBLISHABLE_KEY` (or legacy anon key)
- AI provider keys, payment gateway secret keys, and database passwords MUST live exclusively in Edge Function secrets or environment variables.

---

## 3. Incident Response & Key Rotation

### Key Rotation Steps
If service-role or API credentials are compromised:
1. Revoke the existing key in Supabase Dashboard / Cloud Management.
2. Generate a new key and update Edge Function secrets via `supabase secrets set KEY=VALUE`.
3. Re-deploy Edge Functions: `supabase functions deploy`.

### Audit Log Inspection
To query audit log events for a company:
```sql
select *
from public.audit_logs
where company_id = 'TARGET_COMPANY_UUID'
order by created_at desc
limit 100;
```
