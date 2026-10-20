# Assurance A11 — Process Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every blueprint §9 process metric is measured on the server from immutable events and current state, and shown on an Audit metrics page that says "Not measured" instead of zero when there is no sample.

**Architecture:** One read-only candidate API computes the metrics over engagements whose period overlaps a date range in scope. Each metric is `{value, samples}` with `value = null` when `samples = 0`. Percentiles use nearest rank (`percentile_disc`), mirrored by the existing Dart `assurancePercentile`. A domain parser validates the shape; a desktop page renders grouped cards with plain definitions.

**Tech Stack:** PostgreSQL / Supabase, Dart 3, Flutter, Riverpod.

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A11)

## Global Constraints

- Authority: `assurance.evidence.view` in scope. Range: `from <= to`, at most 366 days; engagements whose `[period_start, period_end]` overlaps it.
- Durations in days with two decimals; rates in `[0, 1]` with four decimals; counts are integers.
- Metric keys (exact): `stage_planning_days`, `stage_fieldwork_days`, `stage_reporting_days` (each `{p50, p90, samples}`), `evidence_waiting_days`, `evidence_review_days` (`{p50, p90, samples}`), `evidence_first_time_right`, `test_completion`, `retest_pass_rate`, `control_coverage`, `recurrence` (`{value, samples}`), `request_ageing` (`{d0_7, d8_30, d31_plus, samples}`), `finding_ageing_days` (`{low, medium, high, critical}` each `{value, samples}` = mean age of open findings), `overdue_remediation`, `open_high_risk_findings` (`{value}` counts, always measured), `report_issuance_days` (`{p50, p90, samples}`), `workload` (list of `{label, open_requests, open_findings}`, top 10 by total, labels from `assurance.member_label`).
- A rate or duration with zero samples reports `null` value(s), never 0.
- Candidate `supabase/candidates/20261020180000_assurance_metrics.sql`; builder `-Slice A11` = A10 + this (needs A8's `assurance.member_label`).

## Review Focus

1. Engagement with no events after creation — expected: stage metrics unmeasured, no division by zero; test in Task 1.
2. A request rejected twice then accepted — expected: counts once in review time (first submission → acceptance) and is not first-time-right; test in Task 1.
3. Range with no engagements — expected: every rate/duration null with 0 samples; counts 0; test in Tasks 1 and 2.
4. Reopened finding — expected: recurrence counts reopen events over issued findings; test in Task 1.
5. Very long labels or many assignees — expected: workload capped at 10 rows, labels never e-mails; test in Task 1.

---

### Task 1: Candidate and rollback suite
**Files:** `supabase/candidates/20261020180000_assurance_metrics.sql`, `supabase/assurance_tests/assurance_metrics_test.sql`, builder A11, CI regenerated.
**Interface:** `api.assurance_metrics(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_from date, p_to date) returns jsonb` → `{from, to, engagements, metrics:{...keys above}}`.
- [ ] Fragment with direct fixture rows and events (engagement transitions on known timestamps, requests submitted/rejected/accepted, procedures designed/reviewed, findings with retests and a reopen): exact expected values for every key; empty range; authority (owner refused, outsider refused); invalid range `22023`.
- [ ] RED (function absent), implement, GREEN on the development project, commit.

### Task 2: Domain parser
**Files:** `packages/jentra_domain/lib/src/assurance_metrics.dart` (export), test.
**Interface:** `typedef Measured = ({double? value, int samples});` `typedef Spread = ({double? p50, double? p90, int samples});` `final class AssuranceMetrics { AssuranceMetrics.fromJson(Map); final DateTime from, to; final int engagements; final Map<String, Spread> stages /* planning, fieldwork, reporting */; final Spread evidenceWaiting, evidenceReview, reportIssuance; final Measured firstTimeRight, testCompletion, retestPassRate, controlCoverage, recurrence; final ({int d0to7, int d8to30, int d31plus, int samples}) requestAgeing; final Map<AssuranceSeverity, Measured> findingAgeing; final int overdueRemediation, openHighRisk; final List<({String label, int openRequests, int openFindings})> workload; }`
- [ ] Tests: full fixture parses; null with samples > 0 or a value with 0 samples is rejected; rates outside 0–1 rejected; p50 > p90 rejected; workload labels with `@` rejected. Implement, commit.

### Task 3: Platform gateway
`AssuranceMetricsGateway { Future<AssuranceMetrics> metrics(TenantContext scope, DateTime from, DateTime to); }`, `SupabaseAssuranceMetricsGateway`; tests for request shape, invalid response, denial mapping. Commit.

### Task 4: Desktop Audit metrics page
**Files:** `assurance_metrics_controller.dart`, `assurance_metrics_screen.dart`, route `/governance/audit/metrics`, nav "Audit metrics" (icon `Icons.insights_outlined`, `assurance.evidence.view`), `main.dart`.
- [ ] Controller: period presets (last 30 / 90 / 365 days, default 90), `load()`, access-denied handling, offline handling.
- [ ] Screen: header with period chips; sections "Engagement stages", "Evidence", "Testing", "Findings", "Workload"; each metric a card with value, unit and a one-line definition; null shows "Not measured" with "No samples in this period" helper; empty workload shows an empty state.
- [ ] Tests: renders values and "Not measured"; period change reloads with the right dates; navigation visibility; 200% light/dark goldens; keyboard reaches period chips. Full suite, analyzer. Commit.

### Task 5: Docs and PR (status A11, verification JSON, push, PR against A10).
