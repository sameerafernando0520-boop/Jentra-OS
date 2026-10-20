# Assurance A15 — Finish and Install (development project)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every assurance candidate from the version guard to A14 is installed on the development project `xpdoufauvrbdmxgngetv` in timestamp order, the two evidence edge functions are deployed there, the repository carries byte-identical migration copies, and CI proves the whole suite against the installed schema. Production is not touched.

**Authority:** the owner's decision in this session: install to the development project only, after each slice's rollback suite has passed; never production.

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A15)

## Global Constraints

- Order: `20261019090000` version guard → `20261019120000` evidence storage → `20261019130000` plan register → `20261020090000` access (A8) → `20261020120000` settings (A9) → `20261020150000` reminders (A10) → `20261020180000` metrics (A11) → `20261020210000` evidence download (A12) → `20261020230000` people (A14).
- Each is applied with `apply_migration` using the candidate text unchanged; the repository copy in `supabase/migrations/` is named with the version the ledger assigns and is byte-identical to the candidate.
- Prerequisite evidence: each slice's reduced rollback suite on the development project (records in `docs/verification/assurance/`) and the cumulative rollback suite in CI (PRs #9–#12 green).
- The installed CI variant (`build_assurance_candidate.ps1 -Installed`) strips every installed candidate's DDL from the suite and expects the final table count; fragments that assert migration-time behaviour (backfills that ran at install) are adjusted for the installed order.
- Edge functions `assurance-evidence-verify` and `assurance-evidence-download` are deployed with JWT verification on, and get `config.toml` entries.

## Tasks

### Task 1: Install on the development project
- [ ] Confirm the ledger ends at `20261018155041`; apply the nine candidates in order; after each, a structural check (functions exist, tables force RLS, no table grants).

### Task 2: Repository copies and the installed CI variant
- [ ] Copy each candidate to `supabase/migrations/<version>_<name>.sql`; strip all installed candidates in `-Installed`; final table count; adjust migration-time assertions; regenerate `assurance_installed_test.sql`; CI green.

### Task 3: Edge functions
- [ ] `config.toml` entries; deploy both functions to the development project; record their versions.

### Task 4: Post-install check and records
- [ ] Ledger, table/function/grant counts, seeded assurance roles; verification JSON; status doc and readiness matrix; PR.
