# Project planning and common-time checkpoint

Updated 2026-10-01. Wave 4 remains incomplete.

The user now explicitly authorized more agents. Root owns project planning/time,
its native workspace and shared integration; service, project finance, and payroll
corrections have separate agent-owned additive migrations/client files. Preserve
all concurrent Wave 3 and acceptance work. No staging, commit, install or app launch
was performed for this project increment.

## Implementation and current evidence

- Contract: `docs/blueprint/60_WAVE4_PROJECTS_TIME_EXPENSES_CONTRACT.md`.
- Candidate: `supabase/migrations/20261001080000_wave4_projects_time.sql`;
  16 API-only forced-RLS tables, eight scoped APIs and eight permission definitions.
  It gives no existing role or plan new authority. The installed `projects`
  foundation schema was empty; use `create schema if not exists`.
- Published calendar/organization coverage, exact whole UTC seconds, common
  payable claim/allocation ownership, sorted employee locks, immutable decisions,
  separate private costing, exact whole commercial billing units and minimal
  nonfinancial receipts are implemented.
- `/projects` now uses its real typed repository, native controller and workspace.
  Full plan approval loads all original tasks/resources/private rates/budget with
  a bound and a consistent current project version. Saved unknown commands keep
  their original body/key/timestamp; confirmed cleanup can be retried independently.
  Conflict reads fetch the exact time target rather than relying on the first page.
- The candidate builder includes only required unapplied Wave 4 prerequisites and
  ends in `rollback;`. The last development run passed all **45 assertions** and
  returned nine actual API projections. SQL role fixtures are synthetic rollback
  proof, not signed-in native acceptance or real separate-session contention.
- The exact arithmetic/task/billing foundation passed **8 domain tests** earlier.
  The current typed repository/gateway/native tests are authored; current analysis,
  tests, rendered previews and isolated Windows build remain unverified.
- Automatic approval review rejected the analyzer/test launch before execution
  because the account reached its usage limit. The result explicitly says this is
  a review failure, not a determination that the action is unsafe. Do not bypass
  review. Resume the same checks once that execution gate is resolved.

## Review findings addressed

Project task completion is now plan-specific. Revised graphs cannot inherit old
completion. Approval requires a current original basis; independent rejection may
resolve an older pending basis with its exact digest and current project version.
The latter source change needs the next refreshed SQL run; the previous 45-assertion
run preceded that final stale-rejection refinement.

`projects.payroll_source(t,e,b,employee,claim)` is owner-only and returns original
approved direct time revision/version/paid seconds only when an active exact claim
owns it. Attendance-backed allocations cannot add project payroll eligibility.

`projects.finance_closure_guard(t,e,p)` is called before closure. While no finance
provider tables exist it has no financial effects to check; a partial provider
installation fails closed. The project finance additive candidate replaces the
guard with its real expense/obligation/billing checks before installation review.

## Remaining development and gates

Complete agent finance/service/correction interfaces and cross-module impact
corrections, then review the combined candidates/clients and refresh proofs. Do
not mark the full project slice complete while expenses, governed evidence,
reimbursement, billing or margin remain unfinished. Supplier AP and service part
providers are absent from the installed database; do not install Wave 3 candidates
or fabricate ownership to unblock them.

Installation approval, private-HR worker readiness, synthetic workspace identity,
authenticated native/MFA, Credential Manager restart, true contention/load,
rendered acceptance and owner signoff remain separate open gates.

## Database design tooling

See `projects-schema-review-20261001.md`, the actual rollback catalog JSON, tool
outputs, query-pattern file and generated Mermaid ERD. These are source/catalog
review artifacts, not migration installation or measured performance evidence.
