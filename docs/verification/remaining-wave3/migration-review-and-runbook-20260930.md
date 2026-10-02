# Wave 3 migration compatibility, installation and rollback review

This is a review procedure, not authorization to install. All 45 candidates remain
unapplied. Development project `xpdoufauvrbdmxgngetv` has 37 installed migrations,
latest `20260929224939_wave4_private_hr`. This work installed none. Refresh the
ledger, API catalogue, helper hashes, checkout and manifest immediately before any
approved installation. Stop on unexplained drift; preserve concurrent Wave 4.

The authoritative dependency order and body SHA-256 values are in
[migration-order-final-20260930-45.json](migration-order-final-20260930-45.json). Ordinal 36
(`20260928001000_wave3_posted_journal_evidence`) precedes ordinal 37
(`20260927200629_wave3_operational_evidence`); lexical timestamp order is not the
tested order. A global `db push` against the shared dirty migration directory is
unsuitable. Do not rewrite any installed migration or repair the ledger merely to
make it look current.

The migration-architect planner, compatibility checker and rollback generator were
run. The current concrete [eight-phase plan](migration-plan-reviewed-20260930-45.json)
and [phase rollback decisions](rollback-reviewed-20260930-45.json) use the exact
45 candidate hashes; the [checker](schema-compatibility-final-20260930.json) uses
the expanded current metadata. The older generic [plan](migration-plan-20260930.json)
and [generated rollback](generated-rollback-20260930.json) are historical only. Their model timings
are estimates. Generated placeholder contacts, destructive downgrade commands and
generic actions are not executable authorization. This reviewed runbook governs
the proposed work. No generated command has been executed.

## Compatibility findings

The rollback capture compares 73/147 tables, 187/403 functions and 64/76 API views.
The before capture now includes ten previously omitted installed CRM helpers;
that catalogue expansion is not ten additional candidate functions.
No existing function or view was removed; no existing return signature or function
grant changed. The eight intentionally modified bodies are listed in the manifest.
Matched private-HR/workforce/calendar/people functions retain their source MD5.
Outside rollback, all four installed shared finance helpers retain their opening
MD5 values. No acceptance executable, authentication or Credential Manager change
was made.

The checker reports `potentially_incompatible`: zero breaking changes and eight
potential warnings. It is not a green compatibility verdict. Manual review:

| Warning | Existing data / approved behavior | Residual compatibility decision |
|---|---|---|
| Stock line quantity/value sign guard | Original nonzero-quantity, same-sign rows satisfy the broadened rule; value-only landed corrections require zero quantity. EC-321 remains checked. | Review older consumers of value-only rows. |
| Stock line nonzero guard | Existing nonzero quantities remain valid; the new rule admits quantity OR value, never an empty movement. | Accept additive value-only movement semantics. |
| `count_previous_status` check | New nullable column accepts prior available/quarantine identity state. No invented historical backfill. | Accept new count recovery metadata. |
| Missing-count status equivalence | Existing rows have null new metadata and old status; the candidate DDL validates them. Count-missing rows must preserve their prior state. | Accept the new missing-count state. |
| Serial status vocabulary | Original four states remain valid; transit/count-missing states preserve one-location identity. Disposed identities cannot be reused. | Older clients must treat unknown states as unavailable. Current command pickers use explicit eligible states. |
| Stock movement kind vocabulary | Original three values remain valid; additive receipt/return/transfer/count/value/disposition kinds retain immutable source links. | Older reporting readers must not silently drop unfamiliar kinds. Current typed valuation/report checks reconcile all kinds. |
| Journal project FK | New nullable scoped dimension; old unassigned journal lines remain unassigned. Candidate DDL validates current rows. | Accept the new tenant/entity dimension reference. |
| Journal cost-centre FK | Same nullable, scoped, history-preserving treatment. Retirement keeps frozen attribution and linked reversal. | Accept the new tenant/entity dimension reference. |

Schema comparison and successful DDL validation prove current data validity, not
semantic compatibility with every older deployed desktop. The checker warnings
require explicit owner acceptance before installation, as required by the skill.
Current release builds and synthetic protocol checks are separate evidence.

The historical foundation grant assertion was investigated before adaptation.
Three authenticated read-only helpers support attachment/Storage RLS: a constant
source descriptor and two booleans that check live membership/source/cost scope.
They grant no mutation path, tenant payload or public/anonymous execution. Contract
49 documents that narrow exception; the assertion continues to reject every other
authenticated Wave 3 internal helper. Its original failure is retained in
[diagnostic evidence](foundation-failure-diagnostic-20260930.json).

## Concrete installation procedure pending approval

1. Select an owner-approved isolated development database for the first persistent
   installation and target-scale/session fixtures. Record project ID, PostgreSQL
   version, region, resource size, restore point and authorized fixture budget.
   It must exclude production and stock-opening acceptance data. This prompt
   does not authorize creating a persistent branch, allocating resources or
   installing into the shared development project.
2. Refresh the exact installed ledger and API/helpers against
   [refresh-report-final-20260930.json](refresh-report-final-20260930.json); review any new Wave 4
   installation. Validate every candidate body SHA against the manifest. Confirm
   the 181-ID matrix, compatibility warnings, source builds and required development
   verification are ready. Preserve installed ledger rows and existing records.
3. Obtain the database snapshot/restore confirmation and an installation window
   from the owner. Keep authoritative writes suspended in that isolated acceptance
   environment while installing; do not suspend or alter the shared acceptance app.
4. Use the Supabase migration capability to apply only the 45 manifest bodies in
   ordinal order. Record each actual returned migration-ledger version/name and
   body hash; do not assume the tool assigns the candidate filename timestamp.
   Re-query the ledger after each phase. Stop after any failure; do not silently
   skip a candidate or install an unrelated dirty Wave 4 file.
5. At phase boundaries run scoped API/grant/RLS/helper checks and repeat the strict
   synthetic fixtures with `finish(true)` and final rollback. Confirm no new grants,
   signatures, ledger differences or acceptance-owned record changes beyond the
   approved install. Record installed tests separately from candidate evidence.
6. Only then run genuine independently authenticated sessions, target-scale plans
   and measured p95 workloads described below. Native checks need their own explicit
   profile/actor/storage approval. Do not infer that database installation authorizes
   launching the acceptance-owned executable or editing its credential stores.

## Phase rollback plan

| Phase / ordinals | Installation checkpoint | Failure / rollback action |
|---|---|---|
| Baseline / 0 | Pinned ledger/catalogue, snapshot, fixture boundaries | Abort before writes on drift. No reset, clean, stash or ledger repair. |
| Procurement / 1–12 | Units, requisitions, sourcing, orders, receipt, AP and returns | A failed migration transaction rolls back itself. Stop further application; retain diagnostics. Restore only the approved isolated database snapshot if the prior successful phase must be removed. |
| Inventory / 13–18 | Transfer/count/reservation/provenance/landed/valuation | Same transaction rollback and stop. Never drop movements, provenance or serial history from a database containing accepted work. |
| Finance / 19–34 | Journals, controls, bank, periods, reports/tax/budgets/dimensions | Same rollback/stop. No destructive journal/open-item downgrade. Re-enable prior client only if its compatibility is verified; otherwise keep the isolated fixture environment unavailable pending restore or reviewed forward repair. |
| Integrated evidence / 35–40 | Plans, journals, operational reads/exports/history/notifications | Same rollback/stop. Preserve frozen reports, attachments and command receipts; do not erase ledger entries to mask a partial installation. |
| Inventory/dashboard/diagnostics / 41–45 | Multi-receipt corrections, partitions, disposition, dashboard and scoped outbox diagnostic read | Same rollback/stop. Restore isolated snapshot before accepted writes, or perform a separately reviewed additive forward repair. No historical data deletion. |
| Installed fixture/native checks | API checks, session races, synthetic load and fresh test profile | Failed assertions remain failures. Roll back ordinary fixture transactions; retain race evidence. Persistent fixture teardown or profile/credential deletion requires the approval that created that isolated environment. Never touch ACPT records/sequences. |

Once business writes exist, a rollback is a coordinated restore or additive repair,
not a generated `DROP ... CASCADE` script. Restore is outside this prompt and must
use the exact approved isolated target and restore point. Concurrent shared Wave 4
or acceptance work must never be discarded to roll back Wave 3.

## Independent-session and scale procedure

Two uncommitted candidate connections cannot see each other's new functions or
fixtures. A single management SQL call is not a concurrency test. The approved
installed isolated target must supply two independent PostgreSQL connections or
two independently authenticated RPC sessions using distinct synthetic actors.
This machine has no `psql`, PostgreSQL, Docker or Podman command available; no tool
was installed under this prompt.

For each race, create committed synthetic fixtures only in that isolated target,
start both commands at a barrier, and retain session IDs, actors, envelopes,
start/end UTC, SQLSTATE/domain conflict, row/source hashes and final invariants:

| Race | Required outcome |
|---|---|
| Number reservation / duplicate post / reversal | One permanent number, original idempotent receipt, at most one effect. |
| Credit confirmation / final-stock reservation or issue | Locked latest exposure; at most one final-stock consumer; no negative demand/availability. |
| Receipt / serial availability / tracked transfer | Exact quantity/value and one serial location; invalid losing command has no side effects. |
| AR/AP allocation and correction | Combined allocations never exceed immutable residuals; linked reversal remains exact. |
| Bank matching | One owner of each statement/ledger line; losing command returns `MATCH_CONFLICT`. |
| Hard close versus posting/adjustment/reversal | Post before close OR close then denial; no post inside a closed snapshot. |

Use the exact NFR-309 scale: at least 500 tenants, 10 entities per tenant,
25 warehouses per entity, 100,000 products per large tenant, 10 million stock
movements and 20 million journal lines. Record generator seed, fixture sizes,
distribution, hardware, region, connection count, warmup and cache conditions.
Use tenant-leading `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` for representative
foreign-key, queue, source, aging, stock/as-of, bank and journal/report reads.
Exercise denied/foreign scopes and confirm no unbounded high-volume cross-tenant
scan. Store raw samples and compute p95 over a stated sample count per operation:
ordinary reads <500 ms; save/transition <1.5 s; posting <3 s; ordinary specified
reports <2 s; bounded complex reports <=10 s with progress/cancellation.
Do not relabel the three 15–17 ms synthetic control reads as these benchmarks.

Prepared tools are [independent sessions](../../../tools/wave3/run-independent-sessions.mjs)
and [target load](../../../tools/wave3/run-target-load.mjs). Only their offline
validation/self-tests ran. They reject this shared development project, production,
opening/Wave 4 payloads, missing concrete approval and mismatched installed ledger
hashes. Session execution requires two existing authenticated actors with distinct
session IDs; neither tool creates or changes authentication. Raw response/envelope
hashes and failed/uncertain attempts are retained without tokens or payloads.
Client request overlap alone does not prove database lock overlap. Load measurement
requires recorded NFR-309 fixture counts and environment; report timing measures
generation rather than a cached report page. A concrete fixture config, installed
target and target-scale generator/count verification are still required before
execution. No races or load measurements have been performed by these tools.

Contract 54 provides accessible report progress and cancellation of presentation
waiting while preserving dispatched command receipts and exact retry identity.
This is client-tested behavior; installed and native cancellation/restart remain
acceptance steps.

## Native acceptance procedure pending approval

Use a fresh owner-approved Windows profile/test actor and an isolated compiled copy,
never the acceptance-owned executable. Record binary/source hashes, database ledger
and actor capabilities. Approval must identify permitted test tenant/entity/branch,
whether a new Credential Manager entry may be created, and allowed synthetic
records/sequences/Storage prefix. Existing authentication/stores remain untouched.

Cold-launch; review lead-to-cash, procure-to-pay, inventory correction/disposition/
partitions/reservations, AR/AP corrections, bank matching, reports/exports and period
close/reopen. Test view-only/cost-hidden/approver/poster/MFA/SoD and revoked access;
process restart with sealed retries; local storage failure; private file dialogs,
upload/checksum/ready reads/rejection; and configured notification navigation.
Inspect loading/error/empty/populated states, focus/tab order, keyboard-only commands,
unsaved navigation, screen-reader labels and reduced motion at 1024×720, 1440×900,
1920×1080 and 3840×2160, light/dark, compact/comfortable and 200% text. Retain actual
native screenshots and results separately from widget previews. Owner signoff
remains a final gate after all failures and external limitations are resolved.
