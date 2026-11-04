# Publishable-key reader repair — 3 November 2026

The approved V11 deployment and empty-body check are complete. All 17
executable modules matched hosted readback; the receiver was unchanged. The
check returned HTTP 400 / `VALIDATION_ERROR`, before any forecast read,
invocation write or AI call.

The hosted diagnostic confirms that `SUPABASE_ANON_KEY` is an opaque
publishable key. The reader incorrectly sent this configuration through the
privileged worker credential parser, which rejects publishable keys before
HTTP. The new regression reproduces that failure. This identifies a concrete
initialization defect consistent with the earlier 503 responses and empty
ledger. Successful hosted AI output remains unverified.

![Hosted diagnostic](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/ai-integrations-test-20261103/v11-hosted-diagnostic.png>)

## Prepared repair

Only two runtime modules change relative to V11:

- [persistent_control.mjs](../../workers/wave5/persistent_control.mjs) adds a
  separate caller transport accepting legacy public keys and opaque publishable
  keys. It sends the public key in `apikey` and the caller's own session token
  in `Authorization`. The privileged worker transport is unchanged and still
  rejects publishable credentials.
- [model_reader.mjs](../../workers/wave5/model_reader.mjs) uses that caller
  transport for the same scoped forecast read and reauthorization.

The repair preserves backend JWT/MFA, tenant/branch and entitlement checks.
Opaque secret keys and malformed/header-injection inputs are rejected by the
caller transport. No secret key is substituted for the caller's identity.
The header separation follows Supabase's
[authorization-header contract](https://supabase.com/docs/guides/functions/auth-headers)
and [API key guidance](https://supabase.com/docs/guides/getting-started/api-keys).

All **319 worker tests pass**, including six new transport/security regressions.
The initial failing regression and corrected run are retained. Normal and
frozen-entrypoint Deno checks pass. The candidate retains the V11 diagnostics,
provider, free-only configuration, request/usage identities and limits.

The candidate reader was also exercised against the actual hosted API with
the existing public key and the test profile's genuine MFA session. Both key
formats reached the same HTTP 403 / SQLSTATE 42501 `ENTITLEMENT_REQUIRED` guard
because the synthetic trial had expired. The local Deno path likewise reached
that API denial. This proves key compatibility and preservation of the expired
trial guard; it does not prove a successful forecast read or hosted AI response.
The first positive-read attempt stopped on that expected denial. A separate
local Deno fixture was corrected to use the available legacy service credential;
neither fixture sent a hosted model/provider request or wrote an invocation.

## Frozen candidate and current hosted state

- Candidate: `build/wave5-publishable-reader-20261103/candidate/`
- Manifest SHA-256:
  `afd9d294ab0ac298f222d1aa16e00a61455583a75357bd02c7716b2396f6741e`
- Inputs: 18 files, including 17 executable modules.
- Current / proposed runtime: V11 / V12.
- [Candidate verification](../verification/ai-integrations-test-20261103/publishable-reader-repair-candidate.json)
- [Live read-only guard proof](../verification/ai-integrations-test-20261103/publishable-reader-live-expired-trial-denial.json)

At `2026-11-03T05:19:16.308095Z` (**10:49:16, Asia/Colombo**), the hosted ledger
still had no invocation, reservation, outcome or usage event for the preserved
IDs, model invocation count 0 and no quota periods. The plan remained
`w5_runtime_20261008`, five seats, subscription version 4. Both test execution
windows had expired. The profile retained exactly its three read permissions.

Workers Free active and no payment method were checked again before this
review. The repair adds no paid provider or fallback. The original delivery
remained `retry`, attempt 1, with zero receiver receipts; it was not resent.

## Next approval scope

The functional repair is **prepared, not deployed**. V11 approval covered
diagnostics and one empty-body check; it did not renew execution authority or
authorize another genuine model attempt.

The concrete [operation plan](../verification/ai-integrations-test-20261103/publishable-reader-operation-plan.json)
proposes:

1. Deploy this exact V12 snapshot and verify all 17 hosted executable modules,
   retaining the receiver and gateway settings.
2. Use the recovered synthetic billing actor's real MFA and normal CAS APIs to
   renew the existing five-seat plan for 30 minutes, version 4 to 5. Preserve
   plan, entitlements and all usage caps.
3. Renew only the existing Synthetic RT1 runtime scope for 30 minutes, using
   the prepared [compare-and-set SQL](../verification/ai-integrations-test-20261103/renew-publishable-repair-runtime.sql).
   Other branches and expired schedule authority stay unchanged.
4. After a fresh read confirms all four preserved ledger records are absent,
   make one genuine authenticated model attempt with invocation
   `bf887435-88db-4a1f-9df9-2e9ec326f9b4` and usage event
   `287f1f6a-fe5d-4cfe-aec0-bbe710eb8e9d`. Amend only the period dates to the
   newly approved trial; preserve the original failed intent. Any existing
   pending, unknown or other recorded outcome stops the operation.
5. Verify the response and actual persisted usage. Make no automatic retry,
   proposal execution, additional permission grant or delivery resend.

No new account, password, authenticator or provider token is required. The
[protected test login](../../build/temp-test-profile-20261102/TEST-LOGIN-PRIVATE.md)
remains the handoff for the temporary profile; its read membership remains
until revoked.
