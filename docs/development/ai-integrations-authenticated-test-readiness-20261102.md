# Authenticated AI test readiness — 2 November 2026

The [Cloudflare Free provider deployment](ai-integrations-free-activation-result-20261102.md)
is already verified. This continuation prepares the remaining genuine Jentra
request and usage-accounting test; it does not claim that test has passed.

The Jentra web tab controlled by this task still displays **Welcome back** at
`https://jentra-os-desktop.web.app/#/login?redirect=/dashboard`, with its sign-in
fields empty. Although the owner reported seeing a dashboard, that session is
not visible in this tab. A question asks whether the dashboard is in the
built-in browser, Chrome, or the installed Windows app. No password, user access
token, refresh token, MFA secret or authentication claim has been collected or
fabricated. No signed-in business caller has been verified.

## Existing sources verified

A fixed read-only hosted query at `2026-11-02T12:04:56.790802+00:00` confirmed
that the existing runtime branch belongs to an approved synthetic tenant and
has three existing pipeline forecasts. Only their IDs and source hashes were
returned; no business amounts, populations or private request bodies were
exported. The exact sources are recorded in
`docs/verification/ai-integrations-free-20261102/ai-runtime-readiness-20261102.json`.

## Bounded renewal prepared, not applied

The existing branch runtime scope expired on 14 October. A candidate renews
only that exact existing scope for **30 minutes from execution**, leaving its
tenant, legal entity and branch unchanged. It verifies and locks the exact
observed scope and edge-authority state before changing the scope timestamps.
Changed prior state, an unapproved synthetic tenant or an inactive branch
fails the transaction. It does not change the separate edge/schedule authority,
model budgets, user memberships, accounts, credentials or delivery rows.

The scope is the existing runtime branch scope, not a new model-only permission
type. Existing governed runtime actions still require their normal credentials
and permissions. Delivery schedules remain blocked by their separate expired
authority. The four-logical-model-invocation tenant cap and the 2,000-token
invocation ceiling are unchanged.

The commit candidate is:

`docs/verification/ai-integrations-free-20261102/runtime-scope-renewal-30m-candidate.sql`

SHA-256: `e4b8ccd7de5a3747af595f6fd52285ccaa4d2cca6b7dbced973e11b0c995f430`.

It has **not been applied** and still requires explicit action-time owner
approval before any committed access renewal.

## Verification of the renewal

Five isolated PGlite checks passed using the repository's scope predicate:
rollback restores the exact original state; a local committed window is exactly
1,800 seconds and preserves the edge authority; changed prior state is denied;
an unapproved synthetic tenant is denied; and an inactive branch causes the
attempted renewal to roll back. These are local tests, not authenticated hosted
acceptance.

The separate rollback-only trial then ran against the hosted database at
`2026-11-02T12:12:55.610051+00:00`. Its result confirmed all of:

- The target scope was allowed inside the private transaction.
- A different branch remained denied.
- The transaction rolled back and restored the exact original scope timestamps.
- The target scope was inactive after rollback.
- The separate schedule authority remained inactive.

The hosted test exercised an UPDATE inside a transaction ending in ROLLBACK;
it was not a read-only transaction. It committed no permission renewal and
exposed no renewed scope to other sessions. No model, external delivery,
invocation, reservation or usage settlement was attempted by the trial.

The trial SHA-256 is
`281f159a1c63c3f0075b3b0bf6c8fb774be60397f1c24685656ed4c1c328cd39`.
Its exact query, durable intent and result are retained under the same evidence
directory. `authenticated-test-readiness.json` indexes the current record.

## Next gates

Identify and reach the owner's actual Jentra app session. Confirm its current
workspace and source access through the ordinary app UI, completing real MFA
where required. Before applying a renewal, refresh the hosted deployment and
scope state, obtain explicit approval for the bounded access window, and
execute only the reviewed candidate if its unchanged-state guards still pass.
Then use the app's existing reviewed-model workspace with one existing source,
retain its invocation/usage identities, and reconcile its actual persisted
outcome and exact usage. Do not extract sessions from browser or desktop stores.

The existing external delivery remains unresolved under its original identity
and was not resent. Its authority and acceptance are separate gates.
