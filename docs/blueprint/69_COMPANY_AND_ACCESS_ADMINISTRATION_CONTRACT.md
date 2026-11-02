# Company and staff administration

Author: Codex. Date: 28 October 2026. Status: implementation contract for the
owner-requested administration completion; uninstalled candidate work.
Reviewers: company owner, security/engineering and pilot administrator.

## Context

Approved foundation FR-7 through FR-12, NFR-S1 through NFR-S5 and NFR-R1 require
a tenant hierarchy, scoped access, independent server authorization and replay-safe
commands. The current first-workspace wizard exists, but there is no general
company/branch, invitation, membership or role administration workspace.

This additive slice implements that requested administration surface over the
existing `core` records and command/audit helpers. Applied migrations, existing
function definitions, role grants, subscriptions and employee candidates are
preserved. Installation and live company acceptance are separate release steps.

## Functional requirements

- CA-01: A tenant-wide administrator MUST list companies, branches, memberships,
  roles, permissions and pending invitations in bounded pages. Every request
  MUST derive its actor from the authenticated session and recheck tenant-wide
  capability and MFA on the server. Scoped role managers MUST NOT gain global
  administration by selecting another branch in the client.
- CA-02: Company creation MUST respect the existing subscription and legal-entity
  plan limit under a subscription-row lock. Branch creation MUST bind an active
  company in the same tenant. Codes, currency and timezone MUST be validated.
- CA-03: Company/branch names and registered company details MAY be edited with
  an expected version. Identity, codes, currency and timezone MUST remain fixed
  after creation in this slice, preserving existing accounting/time bases.
- CA-04: Role managers MUST create/edit custom roles with an explicit permission
  set. They MUST NOT delegate permissions they do not currently hold tenant-wide.
  Privileged permissions MUST require MFA. Existing system roles MUST be immutable.
- CA-05: Administrators MUST grant/revoke an existing role at tenant, entity or
  branch scope. The target membership, role, company and branch MUST all belong
  to the tenant. The change MUST use the membership's expected version. Self
  grants/changes and owner-role changes MUST be refused by this general UI/API.
- CA-06: Administrators MUST suspend, revoke and restore other staff memberships
  with an expected version. Owner memberships MUST remain protected. Suspension
  and revocation MUST revoke outstanding invitations for the same verified email.
  Restore MUST recheck the plan seat limit and role delegation authority.
- CA-07: Invitation creation MUST reuse the existing `core` invitation authority,
  validate delegated role and scope, and return no raw invitation secret. A
  verified invitee MUST be able to list and accept their own pending invitation
  by ID. Acceptance MUST recheck scope, expiry, live inviter authority, seat limit
  and the invitee's verified canonical email. No email sending is implied.
- CA-08: Mutations MUST use stable command and idempotency identities, exact
  payload binding and the existing immutable command/audit/outbox pattern.
  Replays MUST recheck live authorization before returning the original result.
  Real errors MUST not be disguised as successful confirmation.
- CA-09: The desktop MUST expose Company & access with companies, branches,
  staff, roles and invitations. It MUST present clear MFA, unavailable, denied,
  conflict, empty and uncertain-result states. An uncertain command MUST retain
  its exact actor/tenant-bound encrypted recovery envelope for explicit retry.
- CA-10: Auth, tenant, session/MFA, connectivity and capability changes MUST
  invalidate private reads and dialogs. Late results MUST not populate a new
  context. The client MUST NOT contain a service key or write base tables.
- CA-11: Existing invitation token APIs MUST NOT bypass canonical verified
  email, live inviter/delegation, scope, seat or inactive-membership controls.
  Additive table guards MUST preserve original function definitions and grants.
  Valid first-workspace bootstrap and permitted legacy acceptance MUST continue.

## Non-functional requirements

- CA-N1: List pages default to 50 and cap at 200. Payloads cap at 16 KiB;
  permission arrays cap at 200. Text must reject control characters.
- CA-N2: New privileged functions use an empty search path and qualified names.
  Only named API entrypoints are executable by authenticated users; private
  helpers are revoked from public, anonymous, authenticated and service roles.
- CA-N3: The desktop supports keyboard use, 1024x720 and 200% text scale using
  the current design system. CI goldens are preserved unless separately reviewed.
- CA-N4: Subscription locks serialize new company/seat consumption; tenant locks
  serialize administration changes. Genuine independent contention/load and the
  foundation p95 targets require separate release evidence.

## Acceptance criteria

- CA-A1 (CA-01, CA-10): Given anonymous, foreign, scoped or non-MFA actors, reads
  and mutations fail before revealing private staff/company data.
- CA-A2 (CA-02): Given the last available company or seat, creation/acceptance
  succeeds once; a subsequent over-limit attempt leaves all rows unchanged.
- CA-A3 (CA-03, CA-08): Given a stale version, edits fail; repeating the identical
  confirmed request returns one receipt, one version change and one audit event.
- CA-A4 (CA-04, CA-05): Given a foreign role/scope, an unavailable permission,
  privileged role without MFA, system-role edit or self grant, no access changes.
- CA-A5 (CA-06): Given an owner or self membership, suspension is refused. Given
  another staff membership, suspension/revocation invalidates pending invitations
  and current permission checks immediately.
- CA-A6 (CA-07): Given an unverified email, another invitee, expired invitation,
  revoked inviter or exhausted seats, acceptance changes nothing. Given a valid
  verified invitee, duplicate acceptance does not duplicate membership/assignment.
- CA-A7 (CA-08, CA-09): Given an uncertain response, retry uses the saved envelope;
  an actor/context change clears the view and a late response is ignored.
- CA-A8 (CA-N2): Candidate creation changes no original function body/grant,
  permission, assignment, entitlement or migration-ledger row. The SQL suite
  rolls back all candidate definitions, fixtures, receipts and business effects.
- CA-A9 (CA-N3): The workspace renders and supports principal controls at narrow
  desktop size and 200% text without overflow; analyzer and focused suites pass.
- CA-A10 (CA-11): Given an old token and suspended membership, an unverified
  account, a revoked inviter or exhausted seats, legacy acceptance fails without
  changing membership/roles. A verified, current permitted legacy invitation
  still succeeds. Legacy issuance cannot delegate an owner or unavailable role.

## Edge cases

CA-E1: Losing permission/MFA during a read or retry clears private state.
CA-E2: An accepted, revoked or expired invitation cannot be accepted as new work.
CA-E3: Changing an idempotency key's payload/action/version is refused.
CA-E4: Branch IDs cannot be combined with a different company, even in one tenant.
CA-E5: Duplicate codes and pending emails produce a conflict without partial rows.
CA-E6: Failure to persist local recovery prevents a mutation from being sent.
CA-E7: Invitation secrets are neither returned by the new APIs nor cached/logged.
CA-E8: A missing candidate/backend returns unavailable, with no preview mutation.

## API contracts

`api.workspace_admin_list(tenant_id, resource, after?, limit=50)` returns
`{tenant_id, resource, items, next_cursor}`. Allowed resources: `entities`,
`branches`, `members`, `roles`, `permissions`, `invitations`.

`api.workspace_admin_command(tenant_id, command_id, idempotency_key,
client_timestamp, action, payload, expected_version?)` returns
`{request_id, entity, warnings}` using the existing command receipt shape.
Actions: create/update company, create/update branch, create/update custom role,
set assignment, set membership status, create/revoke invitation. Unknown fields
and actions fail. Payload identities and exact expected version form the request
hash. The response must bind the original action/scope/command and confirm the
expected new identity/version before local recovery is removed.

`api.workspace_my_invitations(after?)` returns a bounded verified-email-only page.
`api.workspace_accept_invitation(invitation_id, idempotency_key)` returns an
idempotent membership receipt after validating the canonical verified email and
current server authority. The Data API uses the caller's own JWT for every call.

## Data models

| Existing record | Authority and mutable fields in this slice |
| --- | --- |
| `core.legal_entities` | Tenant-bound company; versioned name/registration/tax edits |
| `core.branches` | Company-bound branch; versioned name edit |
| `core.roles` / `core.role_permissions` | Custom role catalogue; versioned name, MFA and permission set |
| `core.memberships` | Staff status and version for general assignment changes |
| `core.role_assignments` | Exact tenant/entity/branch assignment; no owner/self mutation |
| `core.invitations` | Existing email-bound pending/accepted/revoked state; no raw secret projection |
| `core.command_receipts`, `audit.events`, `core.outbox_events` | Existing transactional receipt, audit and outbox authority |
| `billing.tenant_subscriptions`, `billing.plan_entitlements` | Existing locked plan/seat/company limits; never edited here |

No persistent parallel identity, role, billing or employee model is introduced.
Two additive triggers guard invitation changes and membership activation on the
original core tables. Trusted SQL maintenance under the database administrator
role remains distinct from authenticated Data API requests. Removing the UI
does not require removing these guards.

## Out of scope

Company deletion/archive, accounting/timezone conversion, ownership transfer,
auth-account deletion, system/operator role editing and billing changes require
their own reviewed contracts. These are not safe substitutes for creating and
administering a pilot company group. Hosted installation, sending invitation
email/push, payroll certification and the company owner's acceptance are not
authorized by source implementation. Jentra Sales is a separate next vertical.
