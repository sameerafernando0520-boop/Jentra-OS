# Data, Security, RLS, and RPC Blueprint

## Schema ownership

| Schema | Ownership |
|---|---|
| `api` | Exposed versioned views and RPCs only |
| `core` | Tenants, legal entities, branches, memberships, RBAC, entitlements |
| `workflow` | Approvals, transitions, timers, comments, notifications, outbox |
| `audit` | Append-only business and AI audit, command receipts |
| `crm`, `sales`, `procurement`, `inventory` | Commercial and stock domains |
| `finance` | Ledger, periods, AR/AP, cash, tax, budgets, assets |
| `people`, `projects`, `service` | Workforce and delivery domains |
| `billing` | Jentra plans, subscriptions, usage, limits |
| `ai` | Proposals, approvals, tool audit, quotas; no provider secrets in tables exposed to clients |

`public` contains no business tables. The Supabase dashboard must expose only `api` for Data
API access. Base schemas still use RLS as defense in depth.

## Common columns

Tenant-bearing mutable records use:

- `id uuid primary key default gen_random_uuid()`
- `tenant_id uuid not null`
- `version bigint not null default 1`
- `created_at timestamptz not null default now()`
- `created_by uuid not null`
- `updated_at timestamptz not null default now()`
- `updated_by uuid not null`
- optional `archived_at`; never hard-delete transaction history

Financial and operational rows additionally carry the applicable `legal_entity_id`, branch,
warehouse, cost centre, project, currency, source document, and correlation identifiers.

## Permission model

Permissions are stable capability codes, including:

- `tenant.manage`, `membership.manage`, `settings.manage`
- `<module>.read`, `<module>.create`, `<module>.approve`, `<module>.post`
- `finance.period.close`, `finance.period.reopen`, `audit.read`
- `ai.use`, `ai.propose`, `ai.approve`

Roles bundle permissions. Membership-role assignments optionally scope a role to a legal
entity and branch. Plan entitlements are an independent upper boundary: a role cannot grant a
feature disabled by the tenant's plan.

Privileged roles include owner, tenant administrator, finance approver/poster, payroll
approver/poster, membership administrator, and AI action approver. The application must gate
privileged operations on an MFA assurance level accepted by the authentication policy.

## RLS matrix

| Resource | Select | Insert/update | Delete |
|---|---|---|---|
| Tenant | Active member | RPC only | Never from client |
| Legal entity / branch | Active scoped member | Tenant-management RPC | Archive RPC only |
| Membership | Self or membership manager | Invite/role RPC | Suspend RPC only |
| Role / assignment | Active member with permission | Membership-management RPC | Archive/revoke RPC |
| Plan entitlement | Active tenant member | Service/operator role only | Service/operator role only |
| Command receipt | Actor or authorized auditor | Command functions only | Never |
| Audit event | Authorized auditor | Trigger/function only | Never |
| Draft metadata | Owning actor in active tenant | Owning actor through sync RPC | Owning actor before posting |

Every policy combines `TO authenticated` with a tenant/membership predicate. `TO
authenticated` alone is forbidden. Update policies require both `USING` and `WITH CHECK`.

## Function rules

- Prefer `security invoker` for ordinary reads.
- Use `security definer` only for an atomic command that must cross protected tables.
- Put callable commands in `api`; revoke execute from `PUBLIC` and `anon`, then grant to
  `authenticated` explicitly.
- Set `search_path = ''` and fully qualify every reference.
- Validate `auth.uid()` before reading client context.
- Never accept actor ID or role as authoritative input.
- Validate membership, scope, permission, entitlement, state, version, and period.
- Claim the `(actor_id, idempotency_key)` command receipt before mutating.
- Return or persist the original result for a duplicate key.
- Write audit and outbox rows in the same transaction as the business mutation.

## Audit model

Audit events are immutable and include tenant, actor, request/correlation, event type, subject,
before/after hashes or redacted snapshots, source, client version, IP/user-agent when available,
and UTC time. Audit payloads must omit passwords, tokens, provider secrets, full payroll bank
details, and raw AI prompts containing PII.

## Local data security

- Drift stores cached references, local drafts, staged-attachment metadata, and sync conflicts.
- Draft payloads use authenticated encryption. A random master key is stored through Windows
  Credential Manager via secure storage and never logged.
- Tenant context is part of encrypted draft metadata; a user cannot open a draft after losing
  membership without a server revalidation.
- Signing out locks local content. A deliberate device-removal action deletes the local key and
  cache only after user confirmation.

## Threat controls

| Threat | Control |
|---|---|
| Cross-tenant ID substitution | RLS membership predicate and command scope validation |
| Client role tampering | Table-backed authorization; ignore user metadata/client claims |
| Duplicate financial mutation | Actor-scoped idempotency receipt and database transaction |
| Lost update | Optimistic version checks and explicit conflict result |
| Function privilege escalation | Empty search path, qualified names, revoked default grants |
| Offline unauthorized post | Client guard plus server connection/auth/version requirement |
| Secret extraction | Publishable key only in Flutter; secrets in server environment/Vault |
| Prompt injection / AI overreach | Permission-scoped tools, redaction, proposal/approval/execution split |
| Audit manipulation | Append-only grants; no client insert/update/delete on audit tables |
