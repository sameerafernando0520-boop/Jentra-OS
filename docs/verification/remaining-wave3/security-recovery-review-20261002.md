# Wave 3 security and recovery review — 2026-10-02

Reviewed against the approved Wave 3 specification and contracts 32, 35, 49,
51, 54, 55 and 56. This is source review and synthetic client verification.
Historical checkpoints are not evidence of the current checkout. Refreshed HEAD:
`f9cc342815e2446fb3f26204d5e65e03c1b2a140`; concurrent Wave 4/5 edits are preserved.

The adversarial review uses three perspectives: a revoked or changed actor/scope,
an interrupted encrypted local write, and an accountant protecting exact immutable
history. The resulting findings concern current access presentation and retry
recovery; they introduce no new valuation policy or accounting engine.

## SDK read normalization — corrected and verified

Manual journal register/picker/tax/detail reads and period/FX option/detail reads
now normalize only the approved read denial allowlist. Fixed typed guidance
replaces raw server message/hint/detail text. Read issuance and returned results
check the same authenticated actor. Command error precedence and the original
sealed command envelope remain unchanged.

The new 135-case [actual SDK transport regression](../../../packages/jentra_platform/test/security_review_finance_read_denial_test.dart)
first recorded **72 passes / 63 failures**. The corrected targeted run records
**382 / 382 passes**, including existing journal/period and report compatibility
checks. See the [RED log](../../../build/remaining-wave3/security-review-sdk-red-20261002.log),
[GREEN log](../../../build/remaining-wave3/security-review-sdk-20261002.log),
[branch-enabled coverage](../../../build/remaining-wave3/security-review-sdk-20261002.info)
and [pre-GREEN source fingerprints](security-sdk-sources-20261002.json).
The SDK uses a real Supabase client with synthetic HTTP responses and tokens;
these checks do not establish live sign-in, live RLS or authenticated native acceptance.
The fingerprint binds the code executed by that run. Subsequent contract prose
clarifications are separately included in the desktop source capture.

## Desktop findings under correction

- Period FX refresh cannot reauthorize after reconnect or read denial because its
  existing guard requires the verification state that disconnect/denial cleared.
- A late FX initialization can issue subsequent reads under a new connection
  epoch, and stale conflict review can clear durable conflict/version evidence.
- An existing FX command chooses a gateway from the caller action rather than
  its sealed payload action; a pending period command can reach the FX gateway.
- Late encrypted manual-journal initialization or reversal preparation can
  republish old forms after access/connection changes. Stale register recovery
  can issue an optional attachment read after its epoch becomes obsolete.
- Both optional post-confirmation catches flatten actionable local-storage
  guidance. Durable confirmation must survive while `LOCAL_STORAGE_FULL` remains
  visible and the acknowledged request remains cleared.

Contracts 32 and 35 were clarified before controller behavior changes. The new
[focused recovery regression](../../../apps/jentra_desktop/test/security_review_finance_recovery_test.dart)
uses encrypted in-memory SQLite, paused decrypt/read completion and local SQLite
write failure injection. RED/GREEN outcomes are pending the coordinated exclusive
desktop test window; this section must not be read as completed verification.

## Evidence boundary

No persistent migration, production, authentication, acceptance executable,
acceptance record, sequence or Credential Manager store was changed here.
Encrypted fixtures use synthetic keys. The review changes no exact arithmetic,
immutable open-item history, linked reversal basis or atomic journal engine.
Installation, native authentication/restart, genuine concurrent sessions,
representative load/p95, rendered visual acceptance and owner signoff remain
separate gates. Negative-stock-enabled accounting requires the outstanding owner
policy; no unapproved valuation provenance is supplied. Wave 3 is not fully complete.
