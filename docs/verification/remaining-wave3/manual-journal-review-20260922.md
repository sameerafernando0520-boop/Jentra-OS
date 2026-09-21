# Solo manual-journal review — 2026-09-22

Reviewed contract 32, the new manual aggregate and API commands, existing workflow,
period, account and journal primitives, the gateway, native editor, recovery and
navigation. No agents delegated. This is a slice review, not AC-326 or owner signoff.

## Findings corrected

- **P1 — Persist the same expected version in local storage and command creation.**
  New documents use version zero. The encrypted draft previously saved a null
  expected version, causing local conflict rejection before any command was sent.
  Save, submit and identical restart retry now exercise the real encrypted store.
- **P1 — Persist confirmed posting before optional source-detail reads.** A read
  failure after successful posting now retains the posted receipt across restart,
  instead of restoring the previous approved local document. Source evidence can
  be refreshed independently without resending the posting command.
- **P1 — Recheck attachment and reversal permissions before command replay.**
  Permission revocation cannot expose prior attachment metadata through an old
  success receipt. Detail reads enforce file permission; the native workspace hides
  retained values after explicit rejection and revalidates before redisplay.
- **P1 — Reject inconsistent success and source evidence.** The gateway validates
  exact transaction/base equations, identity, scope, version, request correspondence,
  source-line identifiers and actual posted line totals. Numeric financial values
  or a balanced response that changes requested amounts remain uncertain.
- **P2 — Keep approved documents readable.** Read-only text uses normal contrast;
  light/dark 200% renders were inspected again. Posting has an explicit confirmation
  and is reachable at the minimum desktop height.

The SQL tests also corrected initial synthetic account defaults/code and lifecycle
setup, plus an ambiguous local SQL alias. Those failing fixture runs are not counted
as passing evidence. Production and acceptance-owned setup were never touched.

## Evidence

- 348 combined procurement/valuation/manual-journal assertions, 105 inventory and
  126 reservation/delivery/AR assertions pass with all nineteen candidate migrations
  in an outer rollback transaction. Artifacts: `manual-journal-*-20260922.json`.
  The AR harness uses `finish(true)` to raise on failing assertions.
- Tests cover exact imbalance rejection, independent approval/MFA/posting, posted
  immutability, authoritative linked reversal, duplicate reversal rejection, changed
  FX and attachments, period locking, AR/AP source protection, private reads, scope,
  replay and late outbox failure with no orphan ledger or altered source status.
- Combined client run: 87 inventory/journal UI/recovery/golden checks and 77 gateway/
  shared-store checks passed. A subsequent final recovery correction passes all 13
  journal UI checks, including the added confirmed-post restart case. Journal gateway
  subset: 10 checks. Shared storage tests use synthetic keys and SQLite, not a real
  Credential Manager acceptance session.
- Light/dark approved journal views inspected at 200% text. The 1024×720 widget test
  reaches and cancels the posting dialog without sending a command. No native app
  launched. Current-source build timing and analyzer outcome are in the checkpoint.
- Fresh project ACTIVE_HEALTHY; 34 applied migrations through 20260911130900. No
  manual/valuation candidate tables installed. Security retains leaked-password
  protection warning and performance has 294 unused-index notices; settings unchanged.

## Remaining gates

Full automatic-source drill-through, attachment upload/open integration, larger
report/export work, configuration mutation races, real multi-session reversal
contention, 200/201-line boundary stress, load/p95 and native authentication recovery
remain unverified. Approval workflows and sequences must be supplied through governed
setup during coordinated installation/acceptance. No acceptance-owned configuration
was provisioned and no candidate was installed. Broader inventory, finance,
cross-cutting and final integration requirements remain in the status matrix.
