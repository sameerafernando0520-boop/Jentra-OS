# Hosted free AI response and usage verified — 3 November 2026

The approved V12 repair is deployed and the genuine authenticated Synthetic
RT1 API test passed. The endpoint returned **HTTP 200**, its stored suggestion
matches the response, and **247 trusted tokens** were recorded exactly once
in the usage ledger. The quota shows **0 outstanding reserved units** and
**247 settled units**. All 18 reconciliation checks passed against an actual
hosted database read.

![Hosted token settlement](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/ai-integrations-test-20261103/publishable-repair-accounting.png>)

## Deployed repair and authenticated response

The repair separates public caller credentials from privileged worker
credentials. The caller transport accepts the hosted opaque publishable key
in `apikey` and preserves the requesting user's session token in
`Authorization`. Privileged credential validation remains byte-identical to
V11. No database schema, business permission, provider, paid fallback, receiver
or gateway-policy change was made by the code deployment.

- Runtime: **V12 ACTIVE**, all **17 executable modules** matched hosted
  readback. The receiver was unchanged.
- Approved manifest:
  `afd9d294ab0ac298f222d1aa16e00a61455583a75357bd02c7716b2396f6741e`.
- Verification before deployment: **319 worker tests** passed, plus normal and
  frozen-entrypoint Deno checks.
- Caller: the temporary profile, with a genuine password/MFA session verified
  by Auth. Target authorization passed and sibling RT2 authorization returned
  HTTP 403 / SQLSTATE 42501.
- The approved forecast ID/hash matched before and after the request. The
  source was not regenerated or changed.
- One V12 controlled attempt; **zero automatic retries**.

The response at `2026-11-03T06:05:34.370Z` (**11:35:34 AM, Asia/Colombo**) was:

```json
{
  "commandCode": "analytics.freeze_pipeline.v1",
  "sourceId": "38742ecf-91fe-4cd3-93c5-9d6f726a59e5",
  "sourceHash": "0e9255bd3871c3ee8130ec94af09d1e21c4ec73191d8ade81f23923f21ca1e47",
  "horizonStart": "2026-10-13",
  "horizonEnd": "2026-11-12"
}
```

This is a reviewed suggestion, not an executed business command. UI model
submission was not exercised: the test retained the approved three read
permissions and used the authenticated worker API.

## Hosted accounting

The database snapshot at `2026-11-03T06:08:56.230780Z` independently confirmed:

| Evidence | Actual hosted value |
| --- | --- |
| Invocation | `bf887435-88db-4a1f-9df9-2e9ec326f9b4` |
| Usage event | `287f1f6a-fe5d-4cfe-aec0-bbe710eb8e9d` |
| Outcome | `settled` |
| Trusted outcome tokens | `247` |
| Usage event quantity | `247` |
| Original maximum reservation | `2000` tokens |
| Current quota reservation | `0` |
| Current quota settlement | `247` |
| Model invocation count | `1` |

The stored suggestion equals the actual HTTP response. Invocation, reservation
and quota periods match the approved trial. The original invocation and usage
IDs were preserved; only period dates changed in the explicitly approved
successor intent. The two older failed endpoint attempts did not create ledger
records. No uncertain or pending outcome was retried automatically.

The response packet retains `persistedUsageVerified:false` as its capture-time
state; the later [hosted reconciliation](../verification/ai-integrations-test-20261103/publishable-repair-usage-reconciled.json)
records `persistedUsageVerified:true`. Earlier preparation and failure receipts
remain unchanged.

## Free plan, temporary access and handoff

Workers Free active and no payment method were verified immediately before
the request. No upgrade or paid fallback was added. The earlier direct
Cloudflare probe's 223 tokens remain separate from this **247-token Jentra
settlement**. Free usage is bounded by the provider's allowance and the
unchanged application caps.

The normal MFA/CAS subscription APIs renewed the same synthetic plan to
version 5, keeping **five seats**. Its trial runs from
`2026-11-03T06:03:38Z` to `06:33:38Z`: **11:33:38 AM–12:03:38 PM Sri Lanka
time**. Only the existing RT1 runtime scope was renewed, from
`06:04:17.758656Z` to `06:34:17.758656Z` (**12:04:17 PM** local expiry).
Schedule authority remained expired for this AI step. These windows expired
without automatic renewal; the read membership remains until revoked. The
later separately approved delivery recovery is recorded below.

The profile retains exactly `ai.proposals.view`, `analytics.view` and
`crm.opportunities.view`. No account, password, authenticator, provider token
or additional permission was created or changed in this V12 step.

Use the [protected test login and MFA handoff](../../build/temp-test-profile-20261102/TEST-LOGIN-PRIVATE.md)
for normal sign-in to [Jentra](https://jentra-os-desktop.web.app/). The file is
ignored by Git and restricted to the local owner, SYSTEM and Administrators;
do not copy its contents into source or public reports.

## External-delivery follow-up

At the AI result's capture time, original delivery
`091e0c08-5038-4169-8e28-ffde9e0d51c8` remained `retry`, attempt 1, with zero
receiver receipts. It was not resent under the AI approval.

The owner subsequently approved a bounded delivery recovery. The
[actual delivery result](ai-integrations-external-delivery-result-20261103.md)
confirms one signed HTTPS request returned HTTP 200, the original delivery is
acknowledged at attempt 2, one exact-payload receipt exists and one webhook
unit is settled with no outstanding reservation. The 247-token AI result is
unchanged. Scheduled dispatch, the full integration rollout and native desktop
acceptance remain separate gates.

All dated receipts are in the [verification index](../verification/ai-integrations-test-20261103/README.md).
No commit or push was performed, and unrelated workspace changes were preserved.
