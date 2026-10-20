# Assurance A13 — Digest Domain Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The client can recompute the evidence cutoff digest (`freeze_evidence`) and the issued report digest (`issue_report`) exactly as the server does (FR-6809, FR-6818).

**Architecture:** `jentra_domain` has no dependencies, so it builds the exact UTF-8 texts the server hashes: the freeze text (`id:sha256:byte_size`, ordered by id, comma-joined) and the report text (`jsonb::text` of the digest document, with PostgreSQL's key order and string escaping). `jentra_platform` hashes them with SHA-256. Expected texts and digests come from the server's own SQL run on literal inputs (read-only).

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A13)

## Review Focus

1. Ordering: evidence by id and findings by id must follow PostgreSQL uuid order (canonical lowercase text order). Covered by reversed inputs.
2. Escaping: quotes, backslashes, tabs, newlines, control characters and non-ASCII text in titles and summaries. Covered by fixtures that contain each.
3. Key order: `jsonb` sorts keys by byte length, then bytes. Covered by the report fixture.
4. A freeze with no accepted evidence is refused, as the server refuses it.

### Task 1: Domain texts
**Files:** `packages/jentra_domain/lib/src/assurance_digest.dart` (export), `test/assurance_digest_test.dart`.
**Interface:** `assuranceFreezeDigestText(Iterable<FrozenEvidence>)`, `assuranceReportDigestText({engagementId, reportVersion, cutoff, periodStart, periodEnd, findings, summary})`, `assuranceJsonbText(Object?)`.
- [ ] Expected texts from the server SQL; RED (undefined), implement, GREEN, commit.

### Task 2: Platform digests
**Files:** `packages/jentra_platform/lib/src/assurance_digests.dart` (export), `test/assurance_digests_test.dart`.
**Interface:** `Future<String> assuranceFreezeDigest(...)`, `Future<String> assuranceReportDigest(...)`.
- [ ] Expected digests from the server SQL; RED, implement, GREEN, commit.

### Task 3: Docs and PR (status A13, verification JSON, push, PR against A12).
