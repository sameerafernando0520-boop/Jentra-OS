# Assurance A12 — Reviewer Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reviewer can verify an uploaded evidence file and download it, and the desktop saves the file only when its bytes hash to the digest the server recorded.

**Architecture:** A user-session API mints a five-minute, one-use download ticket for a verified uploaded item. The `assurance-evidence-download` edge function redeems the ticket with the service key, where SQL re-checks that the stored object is still the verified version, and returns a 60-second signed URL with the recorded digest and size. The desktop fetches the bytes, hashes them on the device, and saves only on an exact match. The ticket table is the access log.

**Tech Stack:** PostgreSQL / Supabase, Deno edge function (Node-tested handler), Dart 3, Flutter, Riverpod.

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A12)

## Global Constraints

- Who may download: `assurance.evidence.view` in scope, or a current external team member with `assurance.external_review` (the A1 time-bound path). Authority is checked before existence.
- What may be downloaded: only items on the generated upload path whose stored object is still the `verified` version (`assurance.evidence_bytes_verified`), else `55000 ASSURANCE_EVIDENCE_UNVERIFIED`.
- Ticket: five minutes, one use, bound to the requesting user. Redemption re-checks expiry, use, membership and verification.
- Signed URL: 60 seconds. No path, key or raw error is reflected to the client.
- The client never trusts the URL alone: it hashes every byte (bounded by the recorded size) and refuses to save on any size or digest difference.
- Candidate `supabase/candidates/20261020210000_assurance_evidence_download.sql`; builder `-Slice A12` = A11 + this (needs the A7 evidence-storage candidate).

## Review Focus

1. External reviewer whose access expired: refused before the evidence is looked up. Covered in Task 1.
2. Ticket replay or another user's ticket: refused at redemption. Covered in Tasks 1 and 2.
3. Stored object replaced after verification: redemption refuses it as unverified. Covered in Task 1.
4. Downloaded bytes differ (tampered, truncated, longer): the desktop reports a mismatch and writes nothing. Covered in Tasks 3 and 4.
5. System-collected evidence (no upload path): no ticket is issued (`P0002`). Covered in Task 1.

---

### Task 1: Candidate and rollback suite
**Files:** candidate, `supabase/assurance_tests/assurance_evidence_download_test.sql`, builder A12, CI regenerated.
**Interface:** `api.assurance_evidence_download_ticket(p_tenant_id, p_legal_entity_id, p_branch_id, p_engagement_id, p_evidence_id) returns jsonb` → `{evidence_id, ticket_id, expires_at}`; `api.assurance_evidence_service_download(p_ticket_id uuid, p_user_id uuid) returns jsonb` (service only) → `{evidence_id, bucket, object_path, sha256, byte_size}`.
- [ ] Fragment: viewer gets a ticket for a verified item; outsider and owner-without-view refused; external within access allowed, expired external refused; unverified item refused; adapter evidence not found; service redemption returns the target once, then refuses replay; other user refused; authenticated cannot call the service function.
- [ ] RED (absent), implement, GREEN on the development project, commit.

### Task 2: Edge function
**Files:** `supabase/functions/assurance-evidence-download/{handler.mjs,index.ts,deno.json}`, `supabase/functions/tests/assurance_evidence_download.test.mjs`.
- [ ] Tests: happy path calls ticket → service download → signed URL (60 s) and returns only `{evidence_id, url, expires_in, sha256, byte_size}`; malformed bodies never reach the database; denial and not-found codes map to safe codes; a target for another path is refused; storage failure is `503`.
- [ ] Implement, `node --test`, commit.

### Task 3: Domain and platform
**Files:** `packages/jentra_domain/lib/src/assurance_evidence_download.dart` (export), `packages/jentra_platform/lib/src/supabase_assurance_evidence_download_gateway.dart` (export), tests.
**Interface:** `EvidenceDownloadTicket.fromJson(Map, {required String evidenceId})`; `AssuranceEvidenceDownloadGateway { Future<DownloadedEvidence> download(TenantContext, String engagementId, String evidenceId); }`; `DownloadedEvidence { Uint8List bytes; String sha256; }` returned only on an exact match, otherwise `DomainError('EVIDENCE_MISMATCH')`.
- [ ] Tests: request shape; non-https URL rejected; bytes hashed and matched; longer, shorter or altered bytes rejected; function errors mapped. Implement, commit.

### Task 4: Desktop
**Files:** `AuditorRequest` gains `evidenceId`, `uploaded` and `fileName`; workspace controller `verifyStoredEvidence`, `downloadEvidence`; engagement view buttons **Verify file** (owner or audit team) and **Download** (viewers); `main.dart`.
- [ ] Tests: verify calls the gateway and reports the outcome; download saves the file under its recorded name only on a match; a mismatch saves nothing and explains; external reviewers see Download but not Verify. Goldens unchanged except where rows gain buttons. Full suite, analyzer, commit.

### Task 5: Docs and PR (status A12, verification JSON, push, PR against A11).
