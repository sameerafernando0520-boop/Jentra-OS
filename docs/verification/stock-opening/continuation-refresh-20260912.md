# Synthetic stock-opening continuation refresh

Observed 2026-09-12, beginning 12:44 UTC. Development only:
`xpdoufauvrbdmxgngetv`. Solo session; no staging, commit, push, branch switch,
production action, persistent SQL fixture or applied migration modification.

## Refreshed baseline

- Clean main at `0ac613b1563f8edfeb8e5f75061f7ab79867af36`, which includes the
  prior approver implementation and evidence. Historical uncommitted-work
  wording in the handoff predates this commit.
- Project ACTIVE_HEALTHY; 34 applied migrations, latest `20260911130900`.
- Saved warehouse, unit, two accounts, period, two products and opening sequence
  match setup-targets.json, including scope, mappings, active states and IDs.
- Opening sequence remains version 1, next 1. Zero journal sequences, workflows,
  matrix steps, invitations, openings and independent-approver memberships.
- Existing development AOT SHA-256 matches prior build evidence:
  `20b167826f7fa954c8dbc3af8133e97ad513705eb1efceba16b080240f67b656`.

## Immutable database identity

Local migration SHA-256 values match the existing verification records. Local
and ledger SQL match after normalizing CRLF and trimming terminal whitespace:

| Version | Normalized MD5 |
| --- | --- |
| 20260910201410 | ee0d067676d97dd11ccb134e3488fbea |
| 20260911065744 | d606ed11858f1922c8647d845463ac3b |
| 20260911130900 | 88c45d9c208281196fc5f591d3c974c0 |

The three opening RPC definition MD5 values still match native-database-refresh.json:
upsert `c666adededec63c1d748d195b792342a`, transition
`9511bf6f8d13f6c1ab3cfc4e67dfa4d6`, post `01c4b792e340576343f38b53bfa88c11`.
Read current setup RPC wrappers and core.upsert_setup_record_impl. Retrieved
current invitation/acceptance/inbox and warehouse RPC identities as well.

Security advisor retains the existing
[leaked-password-protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Performance advisor reports only 347 informational
[unused indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
No configuration or index change was made.

## Native observation and manual dependency

Launched the existing development build through supported Computer Use APIs.
Owner session restored; dashboard and Business setup show the expected workspace
and JAT/HQ scope. Native numbering list shows the existing stock_opening sequence.
Opened a fresh New document sequence form. Document type was confirmed focused;
sky.type_text returned without an error but `journal` did not appear. This
reproduces the historical input limitation. No repeated input loop or save attempt.

Requested manual entry of `journal` and `ACPT-JRN-` and Save to server, retaining
blank suffix, padding 5, next 1, Never and Active. Verify the resulting record
before continuing. No authentication or MFA automation occurred.

## Independent setup-contract review

The workflow form already accepts a JSON lifecycle; _typedValue uses jsonDecode
without stripping extra keys. Domain validation requires canonical states and
valid transitions. The live server stores p_payload.lifecycle, so explicitly
include `requires_approval: true` in that object and select Active (new workflows
default to Draft). No new field is required for this setup.

The approval matrix form carries workflow and actual role UUIDs, step order,
currency, exact-string minimum/maximum and status. Live setup resolves entity
scope from the workflow and validates the role belongs to the tenant. Opening
submission snapshots applicable active steps by LKR currency and inclusive amount
bounds; absent steps fail closed. Verify persisted scope and the invitation's
branch-scoped role assignment before acceptance. No workflow/matrix was saved.

## Evidence limits

No source change, build, or automated suite rerun was needed for this read-only
refresh; existing test/build evidence remains historical. git diff --check passed.
Native draft restart recovery, submission, self-approval denial, independent MFA
approval, posting/replay, authoritative reconciliation, real multi-session
contention/failure recovery and final owner signoff are still unperformed.
