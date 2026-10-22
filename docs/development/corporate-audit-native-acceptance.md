# Corporate Audit & Assurance — authenticated native acceptance checklist

Prerequisites: installed candidate (approved), desktop Governance & Audit workspace (A5),
isolated Windows build, isolated development test accounts, and genuine TOTP.
On 21 October 2026 the owner authorized the agent to create test accounts and test
them. Create these only in development, in a dedicated synthetic tenant; do not
grant access to an existing business tenant. Provision confirmed accounts through
authenticated administration, without disabling email confirmation. Keep passwords,
tokens and TOTP seeds private; record only fixture IDs and outcomes.
Record each step with timestamp; no credentials or MFA codes in evidence.

Current handoff: the [development Windows package](../../build/assurance-release-20261021/Jentra-OS-Assurance-development-Windows.zip)
is built; the [screen gallery](../verification/assurance/screen-review-20261021.html)
contains widget-test references. Neither establishes this walkthrough. Test-account
creation is pending restoration of the Supabase administration connection: the
environment token is invalid, and the saved CLI login receives HTTP 403 for this
development project. The resumable [fixture script](../../tools/assurance/create_dev_test_account.ps1)
has retained its private prepared checkpoint; no account creation was confirmed.

- [ ] Sign in as engagement manager; create engagement; confirm version 1 and event 1.
- [ ] Add auditor, reviewer and external (≤ 90 days); attempt to add a control owner → denied.
- [ ] Map a control; request evidence; sign in as control owner; submit evidence (digest shown, path not editable).
- [ ] Reviewer rejects then accepts; rework count shows 1.
- [ ] Lead freezes with fresh MFA; repeat after 16 minutes without re-MFA → denied.
- [ ] Record exception; recorder cannot issue finding; second auditor issues with MFA.
- [ ] Owner responds and remediates; owner cannot retest; auditor fails then passes retest.
- [ ] External account: detail visible, no storage reference, every write control absent/denied; after expiry → denied.
- [ ] Lead cannot issue report; reviewer issues; reopen and reissue → versions 1 and 2 both visible.
- [ ] Keyboard-only pass through every screen; visible focus; 200% text; light and dark.
- [ ] Narrator or NVDA announces each screen heading, work item/status, member selector,
      date field and picker, digest, loading/error state and confirmation; labels remain
      understandable without colour. Record reader/version, Windows version, screen,
      action, expected announcement, actual announcement and pass/fail.
- [ ] Draft a response, kill the app, relaunch → encrypted draft restored; revoke permission → draft not submittable.
- [ ] Revoke a capability mid-session → next action denied, history intact.
- [ ] Owner reviews and signs off (separate record).
