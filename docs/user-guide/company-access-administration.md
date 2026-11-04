# Company & access: administrator instructions

28 October 2026. This is the addendum for the new administration candidate.
The ten-page Word manual remains the earlier launch checkpoint. The new screen
and APIs require a reviewed backend rollout before they can be used in a hosted
company. Source implementation and automated tests do not establish installation.

## Open the administration workspace

Sign in with your individual administrator account and select the intended
business group. Open **Business setup → Company & access**. Use **Register** to
choose Companies, Branches, Staff, Roles or Invitations. The server requires
the relevant group-wide administration permission and recent MFA. A branch role
does not grant group administration. Use **Verify MFA again** if prompted.

An unavailable backend disables new changes. Reconnect and reload after the
reviewed installation; an empty screen is not confirmation that companies or
staff were removed. The screen clears private records when the account,
workspace, session or connection changes.

## Add companies and branches

1. In Companies, choose **Add company**. Enter the registered name, unique code,
   accounting currency, IANA timezone and applicable registration/tax details.
2. Check the currency and timezone with your finance administrator before saving.
   They and the company code are fixed after creation in this workflow. The
   subscription's company limit still applies.
3. In Branches, choose **Add branch**, select its company and enter its name,
   unique code and timezone. Confirm the selected parent company before saving.
4. Reopen the workspace selector and confirm the resulting company/branch.

**Edit company** changes its name and registered details. **Edit branch** changes
its name. Company removal, ownership transfer and accounting/timezone conversion
need their own controlled procedures; they are not included in these forms.

## Give staff the right access

1. Create a custom role in Roles when the standard roles do not match the job.
   Select only the needed permissions. Privileged permissions require MFA.
   You can delegate only authority you currently hold. System roles and roles
   assigned to your own account cannot be edited here.
2. In Invitations, choose **Invite staff**. Enter the person's account email,
   role and intended company/branch scope. Leaving the company empty grants the
   chosen role across the group; choose this only deliberately.
3. Ask the person to sign in using that verified email. Open **Company
   invitations** from the workspace selector, or the initial workspace screen,
   and accept the correct group, role and scope. This candidate does not send
   invitation email or expose invitation secrets.
4. Verify the person's available companies and allowed tasks using their own
   account. Test a denied task and independent approval before ordinary use.

In Staff, **Manage roles** adds or removes an exact group/company/branch
assignment. **Suspend access** temporarily closes the membership; **Revoke
access** closes it for the group. Both revoke pending invitations for the same
account email. **Restore access** is an explicit administrator decision that
rechecks retained roles and the seat limit. A new invitation cannot silently
restore a suspended or revoked person's old access. Owner and self membership
changes are protected in this workflow.

Membership revocation does not delete the person's authentication account,
business attribution, audit history or data in another business group.

## Handle an interrupted change

Changes are saved to encrypted, account-bound recovery before they are sent.
If the outcome is unknown, use **Retry saved request**. Keep the same request;
do not recreate it under a different identity. A confirmed response removes only
that request's recovery envelope. Reload after a version conflict and review the
latest record before making another change. If secure local recovery cannot be
saved, fix storage availability before sending the change.

## Pilot acceptance

Before inviting the wider company, record the exact release/backend versions
and test two company scopes, a restricted branch user, independent approvers,
MFA expiry, invitation expiry/revocation, suspension/restore, seat/company limits,
restart after an uncertain result and offline/account-switch privacy. Retain the
actual receipts and expected denials in the pilot record. Automated evidence and
the local-only database runner are described in the
[candidate runbook](../development/company-access-administration-candidate.md).
