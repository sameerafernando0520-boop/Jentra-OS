# Stock-opening approver setup verification

2026-09-11. Development only: `xpdoufauvrbdmxgngetv`.

## Refreshed baseline and native observations

The checkout was clean on `main` at `e307d159c97beeaa1e1dd89e7d876845a926a0db`,
ahead of the supplied `f394401` handoff. No Git mutation was performed. The
existing warehouse-build AOT SHA-256 matched `warehouse-verification.json`.
The app was reopened to sign-in; the owner subsequently completed authentication
manually. Fresh native observation confirmed Jentra Acceptance Lab and the
Business setup scope Jentra Acceptance Trading / Head Office.

The account editor opened, but Windows Computer Use text entry did not populate
the focused code field even after refocusing. Accessibility input also reported
`element ... is not available in cached app state for jentra_desktop.exe`.
No account was saved. This is an automation limitation, not evidence of a failed
server account command. A later window refresh found the native app closed.

## Governed access gap delivered

Only the owner role existed. There was no role-creation/invitation-creation UI.
The new Business setup action creates a scoped stock-opening invitation. Its
server command creates or validates an MFA-required role with exactly cost-view
and approval-decision permission. It requires both tenant-level role-management
and member-invitation authority plus AAL2. It excludes self-invitation, validates
active entity/branch scope and refuses to reactivate any existing membership.

A signed-in recipient sees their own pending invitations in the command centre,
including before joining a workspace. Acceptance checks their confirmed email,
expiry, role definition and active scope and creates the scoped membership.
No bearer token is exposed by these commands. No email sender was added.
The matrix still needs the resulting role UUID. Existing stock-opening
self-approval and independent approval rules remain unchanged.

## Verification

- Structural preflight reproduced both missing commands and the missing inbox.
- Candidate and installed suites: **40 rollback-only assertions** each, including
  calls under the authenticated database role, AAL1/AAL2, email isolation,
  role/scope rejection, replay, no posting authority, receipts, audit and outbox.
- Platform: **3 passing transport tests**, following the missing-class red test.
- Desktop: **159 tests passed in the full suite**, including six new invitation
  tests. Existing golden baselines were not updated. The new 200% text-scale form
  was rendered and visually reviewed; the full run verified it without updates.
- Full analyzer initially reported five brace-style infos in the new file.
  They were corrected; both the affected file and the final full analyzer report
  **No issues found** (`approver-analyzer-final.log`, 5.8 seconds).
- Compatibility checker exited 0, `fully_compatible`, zero breaking or
  potentially breaking changes, using fresh manifests of 131 tables/views.
- Applied migration: **20260911130900_stock_opening_approver_setup.sql**.
  SHA-256: `32c87cc96b796ae6da1bb5d9e5b0a9702ccc21f6dd2144d84b612cd13f5be1c3`.
  Ledger and local SQL match after trimming terminal whitespace (MD5
  `88c45d9c208281196fc5f591d3c974c0`). Existing invitation, permission and command
  helper definition MD5 values remain unchanged. Both prior applied stock-opening
  and warehouse migration hashes remain unchanged.
- Security advisors: only the existing leaked-password-protection warning;
  [remediation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

At 13:11 UTC the project has **34 migrations**, zero fixture users/tenants,
one owner role/membership, zero invitations, and zero warehouses, units, accounts,
products, periods, sequences, workflows, approval steps or openings. Tests did
not persist business prerequisites or grant approver membership.

Prepared CSVs for accounts, units and the September period are in
`prepared-imports/`. They are inputs for the authenticated Setup Centre import
preview and apply flow, not applied data. Product imports still require actual
saved unit/account UUIDs. No password, MFA code, token extraction, persistent SQL
fixture, impersonation, production change, staging, commit or push was used.

Native authenticated setup/save/submit/independent approval/post/retry and
reconciliation remain pending, along with opening-specific restart recovery,
multi-session contention/failure evidence and owner signoff.

## Updated Windows run

The development-configured release built successfully in **58.1 seconds** and
was launched. AOT SHA-256:
`20b167826f7fa954c8dbc3af8133e97ad513705eb1efceba16b080240f67b656`.
See `approver-build-artifacts.json` and `approver-windows-build.log`.
It restored the owner session, and native Business setup displays the correct
tenant/entity/branch plus the new Invite stock opening approver action.
This is session restoration, not stock-opening draft recovery acceptance.

The native account import picker opened successfully. Its cached accessibility
file-name entry fails with the same unavailable-element error; coordinate entry
also failed to establish reliable field focus. The user was asked to select the
prepared accounts CSV manually and leave the preview for agent inspection.
No file was applied or account created by this checkpoint.

Performance advisors reported 347 informational unused-index findings. No index
was removed. Nine affected Dart files pass formatting after normalizing the
platform export file; `git diff --check` passes. No existing work was discarded.
