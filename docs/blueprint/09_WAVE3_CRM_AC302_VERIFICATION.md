# Wave 3 CRM AC-302 review verification

Date: 2026-09-05. Scope: FR-313 through FR-318 / AC-302.
Approved synthetic development project: `xpdoufauvrbdmxgngetv`.
Production was not accessed or changed.

## Outcome

Added `20260905123934_harden_crm_pipeline_ac302.sql` and expanded
`supabase/tests/wave3_crm_pipeline_test.sql` from 50 to 88 assertions.
The correction is **applied to development only**. The unchanged candidate
first passed all 88 CRM assertions in an isolated transaction ending in
ROLLBACK. After application, the development ledger confirmed version
`20260905123934`, and all five SQL suites passed again with rollback-only
synthetic fixtures. No production deployment was performed.

The three existing CRM migrations are already in the development ledger.
They remain byte-for-byte unchanged. All other dirty/untracked Wave 3 client,
quotation, order, credit-control, and reservation work was preserved.

## Confirmed defects corrected

- Lead expected value, opportunity expected value/probability, and conversion
  probability now reject JSON numeric values before text coercion. PostgreSQL
  numeric and decimal-string API boundaries remain exact.
- Entity-specific qualification workflows now outrank the tenant fallback,
  including when the fallback has a higher revision.
- Conversion adds the initial opportunity stage event alongside the completed
  lead event, with the same authenticated actor and command attribution.
- Inactive qualified leads cannot convert, and the owner must still be an
  active tenant member.
- Opportunity edits cannot detach or replace the party/contact/source links
  belonging to a converted lead.
- Activity reads enforce the capability for their aggregate type; lead-only
  visibility does not expose opportunity activity content.
- Append-only, forced-RLS pipeline history records each lead, opportunity, and
  activity revision in the source transaction. Its API view is security invoker.
  Snapshot financial fields remain JSON strings; actor/request/command/
  correlation identifiers and source context are retained.
- Summary reads select the latest permitted version at the end of the selected
  UTC date. Later revisions cannot rewrite previous reports. Stage, forecast,
  conversion, win/loss, recency, and aging use the same historical boundary.
- Totals use unrestricted PostgreSQL numeric aggregation rather than narrowing
  sums to one row's numeric(20,6) limit. Currencies remain separately grouped.
- History has no client write grants, rejects UPDATE/DELETE even from a trusted
  caller, and the obsolete current-state summary helper is no longer callable
  by authenticated clients.

## Test-first evidence

The original CRM implementation failed added tests for numeric JSON coercion,
workflow precedence, missing opportunity telemetry, historical repricing,
large-value summary overflow, required legal entity, mutable conversion links,
activity capability leakage, and inactive-lead conversion. The additive
correction then passed the full suite.

All SQL suites passed both candidate validation and post-application regression
inside separate rollback-only development transactions. The verification runner
used strict `finish(true)` so failed assertions or plan mismatches raise an
error; it did not infer success merely from the last displayed TAP assertion.

| Suite | Passed |
|---|---:|
| Greenfield foundation | 30 |
| Wave 2 shared foundation | 99 |
| Wave 3 operational foundation | 50 |
| Wave 3 CRM pipeline | 88 |
| Wave 3 lead-to-cash foundation | 46 |
| Total SQL assertions | 313 |

The CRM suite specifically proves tenant/entity/branch denial, forced RLS,
MFA and revoked membership, identical-envelope replay, changed-envelope denial,
semantic conversion retry without duplicates, selected existing party/contact
reuse, optimistic conflicts, command attribution, and late-outbox-failure
rollback across aggregates, audit, telemetry, receipts, outbox, and history.

Exact large-value fixture:
two USD opportunities each `90071992547409.123456` at `33.33` percent,
plus one USD opportunity `20.100000` at `75.00` percent, produce:

- USD expected total: `180143985094838.346912`.
- USD weighted total: `60041990232117.996696`.
- Independent LKR expected total remains `1750.350000`.

A prior-date USD snapshot remains `10.100000` expected and `2.525000`
weighted after today's revision. Changing the connection timezone does not
change UTC as-of currency totals.

Fresh full Dart/Flutter regression passed: **133 tests** (61 domain, 24 platform,
10 design system, 38 desktop), including the nine CRM domain tests and existing
CRM widget/golden coverage. This includes the current, separately edited brand
and catalogue work without modifying its source or expected goldens.
Analysis passed with no issues. The non-mutating formatter check passed across
69 files with zero changes. No new UI implementation or live-user runtime
acceptance is claimed by this SQL correction.

The current Windows debug build passed after `flutter pub get --offline`,
then `flutter build windows --debug --no-pub` (44.6 seconds). This is build
evidence, not a fresh installed-app or authenticated-user acceptance run.

## Preservation and isolated-run checks

During pre-application validation, rollback left zero leads, opportunities,
and activities, no `crm.pipeline_history` table, and no corrective ledger entry.
After the approved development application, the history table and migration
ledger entry persist as intended. Post-application tests still leave zero
leads, opportunities, activities, and history rows. Synthetic fixtures do not
persist.

Fresh security advisors reported **zero findings**. Performance advisors
reported only **180 informational unused-index notices**, with no warning or
error findings. Indexes were retained: an empty development database does not
provide representative production usage evidence. See the
[unused-index advisory guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

Original CRM migration SHA-256 values:

- `20260904125910_create_wave3_crm_pipeline_schema.sql`:
  `C17A69BE1FDDEB8211C76C494537493F68281A3A552E6D1E487BF9B73D5C44A6`
- `20260904130000_create_wave3_crm_pipeline_commands.sql`:
  `98672CBDBD0DA37409B7A3DC53364E078E1C641E10E4523A89E318B39CA71255`
- `20260904135959_add_crm_pipeline_aging_summary.sql`:
  `95D25E6E9518FC01B0638FBADE75A2D000180C52408A182C5E46798ACD03A02F`

Whitespace/diff checks passed. A targeted heuristic secret-pattern scan of the
CRM/lead-to-cash source and tests, CRM migrations, and this report found no
matches; this is not a full security
audit. Git still tracks zero generated Windows Flutter/plugin artifacts.
Their ignore rules remain active, Windows source status is unchanged, and
nothing was staged, committed, or pushed.

## Remaining boundaries and next slice

### Development application runbook (2026-09-05 continuation)

- Re-query project identity and ledger; validate the unchanged candidate and all
  88 CRM assertions inside BEGIN/ROLLBACK before application.
- Compatibility: existing API signatures/response shapes and base-table columns
  remain intact. The explicitly requested stricter decimal, scope, attribution,
  and conversion invariants intentionally reject invalid legacy operations.
- Apply as one development-only migration transaction. A failure before commit
  rolls back the whole migration; do not retry blindly after an ambiguous result.
  Inspect the ledger and object definitions first.
- After commit, rerun strict SQL regression and advisors. On failure, stop the
  affected client writes and prepare an additive correction; never delete history,
  rewrite the ledger, or restore stale current-state reporting as a rollback.

- The corrective migration is applied to development and is now immutable.
  Do not reapply it, rewrite its contents, or change its ledger version.
- Historical data predating this migration can only be baselined at its last
  known persisted version; older revisions must not be invented. The verified
  development CRM tables are empty, so no existing rows need reconstruction.
- Concurrent-session stress/load benchmarks and the full Wave 3 release gate
  remain outstanding; rollback and repeat-call tests do not claim load proof.
- Next implementation slice: the versioned quotation desktop workspace bound
  to the preserved quotation RPC foundation (FR-319..FR-321 / AC-303), followed
  by quote-to-order credit/reservation interaction (FR-322..FR-325 / AC-304).
  First close quotation detail/line/revision/decision read contracts and durable,
  actor/entity/branch-scoped draft/retry handling; explicitly prove recall and
  expiry behavior before calling the complete quotation workspace finished.
