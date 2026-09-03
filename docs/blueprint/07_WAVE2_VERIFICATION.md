# Wave 2 Verification Record

**Date:** 2026-09-03

**Branch:** `codex/jentra-greenfield`

**Development project:** `xpdoufauvrbdmxgngetv`

**Scope:** Wave 2 shared business foundation only

## Outcome

The Wave 2 functional implementation is complete in the greenfield desktop workspace and the
synthetic-data-only development database. It delivers the shared schema, versioned API boundary,
Business Setup Centre, exact decimal contracts, encrypted drafts and reference cache, bounded
CSV/XLSX processing, private attachments, workflows, numbering, notifications, saved reports,
and capability-aware desktop behavior described by `06_WAVE2_SHARED_FOUNDATION_SPEC.md`.

No production or staging project was created, no customer data was moved, no billing was enabled,
no installer was signed, and no branch was pushed.

Two verification exceptions remain recorded under [Residual verification gates](#residual-verification-gates).
They do not hide a known functional failure, but they prevent describing `NFR-213` and the final
advisor portion of `AC-220` as fully evidenced.

## Stage checks

| Stage | Evidence | Result |
|---|---|---|
| Specification | Contiguous, unique definitions for 44 `FR-*`, 15 `NFR-*`, 20 `AC-*`, 24 `EC-*`, and 9 `OS-*`; every requirement range appears in the trace matrix | Pass |
| Domain contracts | Exact decimal, lifecycle, attachment, validation, import preview, query, and resource metadata suites: 42 tests | Pass |
| Platform adapters | AES-256-GCM drafts/cache plus defensive CSV/XLSX codecs: 18 tests | Pass |
| Design system | Semantic status, density, and approved navy/green identity: 3 tests | Pass |
| Desktop integration | Routing, permissions, offline guards, validation, dirty forms, all 17 resources, every configurable form, 200% text, and golden baselines: 23 tests | Pass |
| PostgreSQL | 15 matched migrations in the development ledger, including 11 Wave 2 migrations; remote pgTAP plan `1..99` completed through `ok 99` | Pass |
| Static quality | Workspace `flutter analyze --no-pub --fatal-infos --fatal-warnings`: no issues in 63.7 seconds | Pass |
| Formatting and diff | 54 Dart files already formatted; `git diff --check` clean; no Wave 2 TODO/FIXME/UnimplementedError markers | Pass |
| Windows package | Release build completed in 87.9 seconds; 30 files, 36,207,500 bytes | Pass |
| Cold launch | Exact release executable stayed alive for 8 seconds; only the captured test PID was stopped | Pass |
| Visual review | 14 stable goldens; inspected minimum, standard, wide/dark, compact/comfortable, and 200% text baselines | Pass |

## Database evidence

The final development ledger contains the four Wave 1 migrations followed by these eleven Wave 2
migrations:

1. `20260901090317_create_wave2_shared_foundation_schema.sql`
2. `20260901090331_create_wave2_command_helpers.sql`
3. `20260901090354_create_wave2_setup_upsert_command.sql`
4. `20260901090406_create_wave2_special_commands.sql`
5. `20260901090420_expose_wave2_versioned_api.sql`
6. `20260901090642_cover_wave2_foreign_keys.sql`
7. `20260901091132_validate_wave2_attachment_aggregates.sql`
8. `20260903045702_enforce_wave2_fiscal_period_lifecycle.sql`
9. `20260903051423_enforce_wave2_workflow_lifecycle.sql`
10. `20260903110103_align_wave2_setup_contracts.sql`
11. `20260903110716_bound_wave2_report_rows.sql`

The connected-project audit observed:

- 17 Wave 2 tables and RLS enabled on all 17;
- 17 `security_invoker` API views;
- 18 named API commands and 13 seeded permissions;
- zero `PUBLIC` command-execution grants;
- a private attachment bucket;
- SAR present in the required currency catalogue;
- active, same-scope product reference enforcement;
- saved-report row limits constrained to 1–200; and
- all 99 pgTAP assertions passing after the final two migrations.

The database suite covers cross-tenant denial, base-table denial, grants, idempotency, optimistic
conflicts, exact numerics, lifecycle locks, primary contacts, product reference scope, document
number concurrency, workflow rules, storage boundaries, notification ownership, atomic imports,
report allowlists, audit immutability, outbox attribution, and command receipts.

## Performance evidence

The development database benchmark ran inside a transaction and rolled back its synthetic rows.

| Scenario | Samples | Result | Target |
|---|---:|---:|---:|
| Literal party search over 20,000 seeded rows | 100 | p95 43.070 ms; max 54.756 ms | p95 < 500 ms |
| Party upsert command | 50 | p95 1.622 ms; max 15.012 ms | p95 < 1.5 s |
| Atomic 500-row unit import | 3 | p95 489.043 ms; max 493.716 ms | p95 < 1.5 s |

Every benchmark request succeeded. Each import accepted exactly 500 rows and rejected zero. The
transaction rollback left no benchmark business rows in the project.

## Coverage evidence

Fresh LCOV line evidence is:

| Scope | Hit / found | Line coverage |
|---|---:|---:|
| Wave 2 critical domain files | 442 / 444 | 99.55% |
| Wave 2 deterministic platform core | 344 / 361 | 95.29% |
| Complete domain package | 494 / 601 | 82.20% |
| Complete platform package, including generated Drift and live adapters | 575 / 1,443 | 39.85% |
| Complete desktop app, including unconfigured later-gate screens | 1,299 / 2,521 | 51.53% |

The Windows Dart/Flutter coverage run accepted `--branch-coverage` but emitted no `BRF` or `BRH`
counters. The 99.55% and 95.29% values are therefore strong line proxies, not branch-coverage
claims. Raw complete-package line coverage also does not satisfy the dossier's project-wide 80%
target because generated Drift code, live Supabase adapters, platform file dialogs, and later-gate
screens are included. This is an explicit `NFR-213` evidence gap, not a waived requirement.

## Desktop and visual evidence

The Business Setup Centre exposes Finance, Parties, Catalogue, Governance, Files & Data, and
Reports from the shell and command palette. Tests exercised manage, view-only, unauthorized,
offline, and CRM-only roles; the controller selects the first permitted resource when Finance is
not available. All 17 resource workspaces and all configurable form definitions rendered without
framework exceptions.

The golden matrix covers light/dark themes, compact/comfortable density, 1024×720, 1440×900,
1920×1080, bundled IBM Plex/Noto fonts, and 200% text scaling. Manual inspection found no render
overflow indicators, clipped working controls, illegible contrast, or stale legacy visual language.

## Security and omission audit

- No Wave 2 TODO, FIXME, HACK, `UnimplementedError`, or stale UI enum values remain.
- No credential-shaped values were found in application, package, migration, test, workflow, or
  blueprint files; the only service-role matches are explanatory comments.
- Direct writes remain RPC-only; privileged functions use empty search paths, fully qualified
  objects, explicit permission checks, and revoked public execution.
- The last successful security advisor read reported zero findings. Performance advisor output was
  informational unused-index advice expected in an empty synthetic project.
- The two subsequent alignment migrations only added a seeded currency, a search-path-hardened
  trigger with revoked execution, and a validated row-limit constraint. The 99-test remote suite
  passed after both.

## Residual verification gates

1. **Branch and overall coverage (`NFR-213`).** Run coverage in CI with a Dart/Flutter environment
   that emits branch counters, define the generated-code exclusion policy explicitly, add adapter
   and desktop interaction tests until the changed-code/project threshold is at least 80%, and
   retain at least 90% for critical domain and codec logic.
2. **Final advisor reread (`AC-220`).** The Supabase connector disappeared from the resumed tool
   session and the local CLI token returned `Unauthorized`. Reconnect the development project and
   rerun security/performance advisors plus the structural count query. Do not reapply migrations;
   the ledger and 99-test suite were already matched after the final migrations.
3. **Local integration environment.** Docker and Podman were unavailable, so database integration
   used the connected development project. CI should still run the same migration stack and pgTAP
   suite against an isolated local Supabase instance.

Until the first two items are evidenced, Wave 2 is functionally implemented and package-verified,
but the dossier's complete release gate must be reported as **conditional**, not unqualified.
