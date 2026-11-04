# Free test activation review — 2 November 2026

The approved Data API repair is complete. Only `api` was added beside the
existing `public` and `graphql_public` exposed schemas. Reloaded settings
retained the change. The genuine temporary account's business-list request
changed from HTTP 406 / PGRST106 to HTTP 200 with an empty array. The web app
now shows **Create your first Jentra workspace**. No membership was granted by
that repair, and anonymous execution of `api.list_my_tenants()` remains denied.

The test identity is `jentra-test-4dd40f8b1f69@fldubai.com`, Auth ID
`89f63c7a-dc28-4f33-859e-eae277193522`. Its existing private login file remains
under ignored `build/temp-test-profile-20261102/` with protected Windows ACLs.

## Proposed scope requiring new approval

| Item | Exact proposed action |
| --- | --- |
| Workspace | Existing **Synthetic Wave 5 runtime**, tenant `babe6c86-a764-4d3a-80a3-952a7c096c2c` |
| Business scope | Entity `caa2bb06-219a-47e9-8132-66d1271b0ffd`, RT1 branch `3813692c-f0de-4c69-8e34-d56cf54695b1` |
| Reader role | Create `w5_temp_ai_reader_20261102`, ID `28d81f05-27c5-4673-85d5-eeb51a515f27`, with exactly `analytics.view`, `crm.opportunities.view`, `ai.proposals.view` |
| Membership | Invite the new test email to that role and exact entity/branch through the normal MFA-checked invitation API; accept using its genuine password session |
| Existing test administrator | Recover only `w5-billing-admin@jentra.invalid`, Auth ID `c6aa32c0-d91f-4555-8687-e77fdf878e0c`; rotate its password, remove its unavailable TOTP factor `d10fef03-d6e1-44fd-b15c-f4eff2d9210c`, then enroll and genuinely verify a new TOTP factor |
| Synthetic trial | Renew the existing `w5_runtime_20261008` trial for 30 minutes through the real MFA scheduling and audited activation APIs; retain the existing plan and five seats |
| Runtime scope | Renew only the existing RT1 runtime branch scope for 30 minutes using the guarded SQL already tested under rollback |
| Actual AI verification | One request through the ordinary signed-in app, using an existing synthetic forecast; retain its identities and reconcile its actual persisted usage |

The read membership and recovered test credentials remain until explicitly
revoked. The trial and runtime windows expire automatically. This is not a
claim that the account or membership automatically expires after 30 minutes.
The existing four-logical-invocation cumulative cap and 2,000-token invocation
ceiling remain in force, with Cloudflare Workers AI Free and no paid fallback.

The runtime renewal concerns the existing governed branch scope; it is not an
AI-only permission type. Separate edge/schedule authority remains expired. The
original external delivery retains its identity and is not resent by this plan.

## Why test-administrator recovery is necessary

The existing synthetic trial expired on **20 October 2026**. Its analytics and
AI entitlements are enabled, but the trial is inactive. Four active memberships
occupy the existing five seats, leaving one seat for the new reader.

Read-only Auth Admin inspection confirmed the exact existing billing test user
and its one verified TOTP factor. Presence checks across the known public
credential-store pointers found no corresponding runtime encryption seal,
account record or factor record. No credential payload was decrypted or read.
The older owner access windows are expired and were not reused.

Recovery changes only that existing synthetic administrator's credentials.
Removing its verified factor ends that test user's active sessions, as
documented by [Supabase's factor recovery API](https://supabase.com/docs/reference/javascript/auth-admin-deletefactor).
The password is changed through the official server-side
[Auth Admin API](https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid).
New values must remain in protected local storage. Real Auth enrollment,
challenge and verification must establish AAL2 before any invitation or trial
scheduling. No Auth rows, JWTs, assurance claims or billing revisions may be
fabricated to substitute for those steps.

## Prepared and verified

The reader-role candidate is
`docs/verification/ai-integrations-free-20261102/test-profile-reader-role-candidate.sql`,
SHA-256 `c585654d9db3c4941c2bf7e631f8fbaa0997616ab86e60d323b04432cde6cc93`.
It asserts the exact confirmed new profile has no membership, the tenant is
allowlisted synthetic, RT1 is active, the role does not exist, and all three
requested permissions exist and are nonprivileged. It creates an **unassigned**
role; assignment must use the normal invitation workflow.

Its hosted rollback trial completed at `2026-11-02T15:52:36.315666Z` and confirmed
the role and permissions were absent afterward and the new account still had
zero memberships. It did not commit access or authenticate as a business actor.
Trial SHA-256:
`8ebc998cf5999c8b67729481d6c79ea9cbc92303080c125701ad9ee2457746f8`.

The separate runtime-scope candidate remains
`runtime-scope-renewal-30m-candidate.sql`, SHA-256
`e4b8ccd7de5a3747af595f6fd52285ccaa4d2cca6b7dbced973e11b0c995f430`.
Its prior hosted rollback proof preserved the original scope and separate
schedule authority. Refresh their exact preimages before committing it.

All proposed mutations remain **not applied**. Before execution, record the
owner's new exact approval, refresh the actor/factor, subscription, role,
membership, runtime and worker-deployment state, and stop on unexpected drift.
Record each Auth or business mutation durably before sending it. Do not blindly
retry an uncertain password reset, factor deletion, invitation, trial revision,
activation, or model send. Preserve original invocation and delivery identities.

This plan changes no paid provider plan, external billing account, real-company
role, applied migration, posting, approval, executable deployment or schedule.
No new model request or delivery has been performed by this preparation.
