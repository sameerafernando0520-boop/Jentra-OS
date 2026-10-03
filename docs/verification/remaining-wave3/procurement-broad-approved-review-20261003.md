# Independent broad approved Wave 3 review — 2026-10-03

This read-only pass revisited approved specification 08 and the current 181-ID
requirements review, with special attention to cross-cutting behavior outside
the procurement security corrections. It reports source findings, not exhaustive
execution or installed acceptance.

The transaction editors are not the sole implementation of operational discovery
and detail. FR-389 literal search, status/date filters, stable bounded pagination,
saved view state and refresh are supplied by the shared operational document
workspace. Contract 49 and `api.wave3_document_page` bind literal filters and
scope, return deterministic 50-row current lists, and explicitly distinguish
current basis from historical truth. Encrypted saved filters contain no source
rows; reopening repeats server access checks. Generated reports freeze the exact
filter snapshot and metadata rather than substituting mutable current data for
requested historical evidence.

FR-384/391 source, command/audit lineage and files are also provided through the
shared operational detail path, `api.wave3_document_evidence`, scoped contextual
navigation and private append-only attachments. Requisition/order/bill editor
registers do not individually render every operational control, so their absence
alone does not establish a missing implementation. Source links restore only
permitted catalogue scope, then recheck aggregate/source/file access. Current
supplier-bill provider construction includes `procurement.bills.view`, retaining
read-only access while its manage/post flags govern mutations.

The reviewed inventory extension supplies bounded explicit maintenance for expired
or retired reservations; neither source presence nor the invocation UI claims
installed worker scheduling. The target verification generators and postflight
invariants are preparation artifacts with exact hashes, IDs and approval bindings.
Read-only SQL invariants supplement independently authenticated HTTP sessions and
cannot replace them. Historical rollback tests and candidate source hashes are
kept separate from persistent installation, current-data compatibility, native
authentication/recovery, populated contention/load, p95, visuals and signoff.

No further definite material implementation gap was confirmed in this broad pass.
FR-353/EC-323 negative-stock enabled-policy behavior remains the explicit recorded
owner-dependent gap. Generic continuation cannot select interim costing, deficit
coverage order, unknown/zero-basis treatment or variance classification/account.
The final whole-desktop run and conservative 189-file coverage still determine
their own current-source verification gates; this review does not declare them
passed.

Protected content and candidate integrity are separately recorded in
[procurement-protected-invariants-20261003.json](procurement-protected-invariants-20261003.json):
327 tracked golden baselines, 232 explicitly enumerated Wave 4 paths, 13 Wave 5
paths and 132 stock-opening/acceptance paths match HEAD and index; all 45 candidate
SHA-256 values and exact dependency order match the reviewed package/reuse record.
The database comparison uses the root's recorded read-only final refresh, dated
2026-10-03 12:07:15 +05:30, with 37 installed migrations, 85 APIs and four unchanged
finance helper MD5 values. No new query or installation was performed by this
reviewer. The full-suite completion audit will refresh these local invariants.
