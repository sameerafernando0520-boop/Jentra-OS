# Spec: Jentra OS Foundation and Desktop Shell

**Author:** Jentra OS Engineering  
**Date:** 2026-09-01  
**Status:** Approved  
**Reviewer:** Product owner (approval expressed by implementation request)  
**Related documents:** `01_ARCHITECTURE.md`, `03_DATA_SECURITY.md`, `04_DESIGN_SYSTEM.md`

## Context

Jentra OS is being rebuilt as a greenfield business operating system. The active worktree
contains no application source that should be reused, while the connected Supabase project
is a healthy, empty development project. Wave 1 must therefore establish a safe technical
and visual foundation before any commerce, finance, inventory, payroll, or AI workflow is
implemented.

The initial product is a Windows-first Flutter desktop application for growing Sri Lankan
SMEs. It must support business groups, multiple legal entities, branches, scoped user access,
offline-safe drafts, and future mobile reuse. The first milestone is valuable when a user can
authenticate, enter an organization context, navigate the complete module shell, control
theme and density, and retain a local draft without permitting an offline authoritative post.

## Functional Requirements

- FR-1: The product MUST be scaffolded as a Dart workspace with a Windows Flutter app,
  reusable design-system package, pure domain package, and platform-adapter package.
- FR-2: The app MUST provide a responsive desktop shell with sidebar navigation, command
  bar, tenant context, module routes, command palette, and content workspace.
- FR-3: The shell MUST expose placeholder routes for Dashboard, CRM, Sales, Procurement,
  Inventory, Finance, People, Projects, Service, Assets, Analytics, AI, and Settings.
- FR-4: A user MUST be able to select light, dark, or system theme and compact or comfortable
  density; the choices MUST persist locally.
- FR-5: The app MUST support Supabase email/password authentication when runtime
  configuration is present.
- FR-6: The app MUST provide a Google OAuth entry point and MUST keep Google provider
  configuration outside source control.
- FR-7: The backend MUST model tenant, legal entity, branch, membership, role, permission,
  plan entitlement, audit event, command receipt, and offline-draft synchronization metadata.
- FR-8: A user MUST be able to create a tenant and its first legal entity and branch through
  one idempotent server command.
- FR-9: A user MUST see only tenants to which they have an active membership.
- FR-10: The selected tenant, legal entity, and branch MUST be explicit application state and
  MUST be included in every tenant-scoped command.
- FR-11: The backend MUST enforce tenant membership and permission checks independently of
  UI visibility.
- FR-12: Critical server commands MUST be idempotent and MUST record actor, tenant, request,
  command type, result, and timestamp.
- FR-13: The platform MUST provide encrypted local draft storage and MUST restore drafts
  after application restart.
- FR-14: Offline mode MUST allow draft edits but MUST NOT allow inventory, payroll, approval,
  payment, or ledger posting.
- FR-15: Draft synchronization MUST use optimistic versions and MUST surface conflicts rather
  than silently overwrite server state.
- FR-16: The app MUST show an explicit configuration experience when Supabase runtime values
  are absent; it MUST NOT crash or embed credentials.
- FR-17: The design system MUST implement the approved semantic color, typography, spacing,
  radius, density, motion, focus, and status tokens.
- FR-18: The app MUST provide keyboard navigation and a `Ctrl+K` command palette.
- FR-19: Navigation visibility MUST respect the active membership's permissions and plan
  entitlements.
- FR-20: Authentication, tenant, permission, sync, and critical command failures MUST use a
  stable `DomainError` contract and a user-safe message.

## Non-Functional Requirements

- NFR-P1: Static shell interactions MUST remain within the 16 ms frame budget at 60 fps on
  a Windows reference device with 4 CPU cores, 8 GB RAM, and SSD storage.
- NFR-P2: Ordinary backend reads SHOULD complete below 500 ms p95 and foundation commands
  SHOULD complete below 1.5 seconds p95, excluding external identity providers.
- NFR-P3: Lists MUST use bounded pagination; the API maximum page size is 200.
- NFR-S1: Every tenant-bearing table MUST have RLS enabled and a tested cross-tenant denial.
- NFR-S2: Authorization MUST NOT rely on `user_metadata`, client route state, or a client
  supplied role.
- NFR-S3: Privileged database functions MUST set `search_path = ''`, fully qualify database
  objects, validate `auth.uid()`, and revoke default execution grants.
- NFR-S4: The desktop client MUST contain only a Supabase publishable key; service-role and
  model-provider secrets MUST remain server-side.
- NFR-S5: Sensitive local draft payloads MUST be encrypted at rest with an OS-protected key.
- NFR-A1: All interactive elements MUST be keyboard reachable and have a visible focus state.
- NFR-A2: Text and component contrast MUST meet WCAG 2.2 AA thresholds in light and dark
  themes.
- NFR-A3: The shell MUST remain usable at 200% text scaling and from 1024x720 through 4K.
- NFR-R1: Duplicate commands with the same actor and idempotency key MUST return the original
  result and MUST NOT create a second mutation.
- NFR-R2: The local draft store MUST survive normal restart and recover safely from a failed
  synchronization attempt.
- NFR-SC1: Tenant and membership queries MUST be indexed for the target of 500 tenants,
  25,000 named users, and 2,000 concurrent sessions.
- NFR-Q1: `flutter analyze` MUST complete with no errors or warnings.
- NFR-Q2: Critical domain code MUST target at least 90% branch coverage; the workspace MUST
  target at least 80% overall coverage as feature implementation grows.

## Acceptance Criteria

### AC-1: Greenfield workspace boots (FR-1, FR-2, NFR-Q1)
Given a clean checkout of the greenfield branch with dependencies restored
When the Windows app is started
Then the Jentra OS desktop shell renders without any legacy UI
And static analysis reports no errors or warnings.

### AC-2: Complete module navigation (FR-2, FR-3)
Given the desktop shell is visible
When the user selects each enabled module in the sidebar
Then the matching route renders inside the persistent shell
And the active module is visibly identified.

### AC-3: Responsive shell (FR-2, NFR-A3)
Given the shell is rendered at 1024x720, 1440x900, and 1920x1080
When the viewport changes between those sizes
Then navigation collapses at the narrow layout
And content remains readable without horizontal page overflow.

### AC-4: Theme and density persistence (FR-4, FR-17)
Given the user changes theme and density
When the app is restarted
Then the previously selected values are restored
And every shell surface uses the matching semantic tokens.

### AC-5: Missing runtime configuration is safe (FR-16, NFR-S4)
Given no Supabase URL or publishable key is supplied
When the application starts
Then it renders a development configuration screen
And no secret, stack trace, or crash is shown.

### AC-6: Password authentication entry (FR-5, FR-20)
Given valid Supabase runtime configuration
When a user submits an email and password
Then the app delegates authentication to Supabase
And success enters tenant selection while failure produces a safe `DomainError`.

### AC-7: Tenant bootstrap (FR-7, FR-8, FR-10, FR-12, NFR-R1)
Given an authenticated user with no memberships
When they submit a valid tenant, legal entity, and branch with an idempotency key
Then one tenant hierarchy is created
And the user becomes its active owner
And repeating the request returns the same hierarchy without duplicates.

### AC-8: Cross-tenant isolation (FR-9, FR-11, NFR-S1, NFR-S2)
Given users A and B belong to different tenants
When user A queries or mutates user B's tenant identifier
Then the database returns no tenant data or a permission-denied result
And no mutation or audit event is created in user B's tenant.

### AC-9: Permission-aware navigation (FR-11, FR-19)
Given a membership lacks the `finance.read` permission or Finance entitlement
When the user enters the shell
Then Finance is absent from navigation
And direct navigation to the Finance route produces an access-denied state.

### AC-10: Local draft survives restart (FR-13, NFR-S5, NFR-R2)
Given the user saves a draft while offline
When the application process is restarted
Then the draft is restored from encrypted local storage
And its tenant context and local version are unchanged.

### AC-11: Authoritative posting is blocked offline (FR-14)
Given the app has no verified server connection
When the user attempts an inventory, payroll, approval, payment, or ledger post
Then the command is not placed in an automatic posting queue
And the UI explains that a live connection is required.

### AC-12: Draft conflict is explicit (FR-15, NFR-R2)
Given local and server drafts share version 5 and the server advances to version 6
When the local version 5 draft synchronizes
Then the server rejects the stale version
And the app presents the local and server versions for resolution.

### AC-13: Command palette keyboard access (FR-18, NFR-A1)
Given focus is anywhere inside the shell
When the user presses `Ctrl+K`
Then the command palette opens
And keyboard input can search and activate an enabled destination.

### AC-14: Accessible themes (FR-17, NFR-A1, NFR-A2)
Given light or dark theme and either density setting
When the component catalogue is tested
Then all controls are keyboard reachable with visible focus
And measured foreground/background pairs meet WCAG AA contrast.

### AC-15: Google OAuth entry is externally configured (FR-6, NFR-S4)
Given valid Supabase runtime configuration and Google provider configuration
When the user selects Continue with Google
Then the app starts the Supabase OAuth flow with the registered desktop callback
And cancellation returns safely to login
And no provider secret is present in the desktop binary or repository.

## Edge Cases and Error Scenarios

- EC-1: Supabase is unreachable at startup → retain the local session state, enter degraded
  mode, show connection status, and do not claim the user is newly authenticated.
- EC-2: OAuth browser flow is cancelled → return to the login screen without creating a
  membership or exposing provider details.
- EC-3: The authenticated user has no membership → show tenant onboarding, not an empty
  dashboard.
- EC-4: The selected membership is suspended → clear active context and show access revoked.
- EC-5: Tenant bootstrap receives an invalid time zone or currency → return
  `VALIDATION_ERROR`; create no hierarchy rows.
- EC-6: Two bootstrap requests use different keys but the same owner and slug concurrently →
  one succeeds and one returns `CONFLICT`.
- EC-7: Local secure-key access fails → do not read or write draft contents; show a recovery
  message and preserve the encrypted file.
- EC-8: Local storage is full → keep the in-memory draft, report `LOCAL_STORAGE_FULL`, and do
  not pretend persistence succeeded.
- EC-9: A route becomes disallowed after a membership refresh → redirect to Dashboard and
  show an access-change notice.
- EC-10: Text scaling or window width makes the inspector unsafe → replace the inspector with
  a drawer instead of overlapping primary content.

## API Contracts

```typescript
interface TenantContext {
  tenantId: string;
  legalEntityId?: string;
  branchId?: string;
  actorId: string;
  warehouseId?: string;
  projectId?: string;
}

interface CommandEnvelope<T> {
  commandId: string;
  idempotencyKey: string;
  context: TenantContext;
  expectedVersion?: number;
  clientOccurredAt: string;
  payload: T;
}

interface CommandResult<T> {
  requestId: string;
  data?: T;
  warnings: string[];
  error?: DomainError;
}

interface DomainError {
  code: string;
  message: string;
  fieldErrors?: Record<string, string>;
  retryable: boolean;
  correlationId: string;
  currentVersion?: number;
}

interface CursorPage<T> {
  items: T[];
  nextCursor?: string;
  limit: number;
}

interface BootstrapTenantPayload {
  tenantName: string;
  tenantSlug: string;
  legalName: string;
  legalEntityCode: string;
  branchName: string;
  branchCode: string;
  baseCurrency: string;
  timeZone: string;
}
```

Foundation RPCs:

- `POST /rest/v1/rpc/bootstrap_tenant` maps to
  `api.bootstrap_tenant(command_id, idempotency_key, payload) -> jsonb`
- `api.list_my_tenants() -> setof api.my_tenant`
- `api.get_my_capabilities(tenant_id) -> jsonb`
- `api.record_client_audit(tenant_id, event_type, subject_type, subject_id, metadata) -> uuid`

All RPC failures use `DomainError` fields in a JSON result or a documented PostgREST error
mapping. The desktop repository normalizes both forms.

## Data Models

| Entity | Key fields and constraints |
|---|---|
| Tenant | UUID PK; unique slug; name; status; plan; time zone; UTC timestamps; version |
| Legal entity | UUID PK; tenant FK; unique `(tenant_id, code)`; legal name; ISO currency; version |
| Branch | UUID PK; tenant and legal-entity FK; unique entity/code; status; version |
| Membership | UUID PK; tenant FK; auth user UUID; status; unique tenant/user; invitation metadata |
| Role | UUID PK; tenant nullable for system templates; stable code; name; privileged flag |
| Permission | Stable text PK such as `finance.read`; module and description |
| Role permission | Composite role/permission PK |
| Membership role | Membership/role plus optional legal-entity and branch scope |
| Plan | Stable text PK; name; status; trial metadata |
| Plan entitlement | Plan/feature PK; enabled flag; optional numeric limit |
| Command receipt | Actor/idempotency unique key; command ID/type; tenant; request/result JSON; status |
| Audit event | Append-only UUID; tenant; actor; request; event/subject; redacted JSON metadata; UTC time |
| Local draft | Local UUID; tenant context; type; encrypted payload; local/server version; sync state |

Indexes must cover membership user/status, every tenant foreign key, legal-entity and branch
scope, command idempotency, and audit tenant/time. Tenant records and audit/command receipts are
not hard-deleted.

## Out of Scope

- OS-1: Commerce, accounting, inventory, payroll, project, service, asset, and AI business
  transactions — delivered in Waves 2-5 after the foundation contract.
- OS-2: POS, manufacturing/MRP, and e-commerce — excluded from the first full-suite release.
- OS-3: Direct government filing, bank submission, and payment checkout — require separately
  reviewed integration specs and credentials.
- OS-4: Production project creation, deployment, billing activation, real customer data, and
  signed release distribution — Wave 6 and separate authorization.
- OS-5: Mobile layouts — domain and tokens remain reusable, but mobile implementation follows
  desktop product validation.
- OS-6: Autonomous AI mutations — all future AI actions require explicit human approval.
