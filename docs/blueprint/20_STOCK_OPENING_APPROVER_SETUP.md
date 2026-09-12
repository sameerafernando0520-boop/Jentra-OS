# Stock-opening approver setup

2026-09-11. Approved synthetic development only, project `xpdoufauvrbdmxgngetv`.

The acceptance workspace has only an owner role. Native invitation creation and
role creation are absent. Add a narrow invitation command that creates or reuses
the `stock_opening_approver` role with exactly `inventory.cost.view` and
`workflow.approvals.decide`, requiring MFA. Require tenant-level role management,
member invitation authority and AAL2 to issue it. Require an active entity and
matching active branch. Reject self-invitations and existing memberships;
never reactivate suspended or revoked access. Reject a conflicting role definition.

The recipient accepts a pending, unexpired invitation from an authenticated
in-app inbox. Verify the signed-in, confirmed email on the server. No password,
MFA code or bearer invitation token is exposed in application logs, receipts or
the UI. Acceptance binds the role to the exact entity/branch. Joining at AAL1 is
allowed; approval remains unavailable until user-managed MFA reaches AAL2.
Approval matrices must explicitly reference the returned role ID. Existing
stock-opening creator/editor/submitter separation remains authoritative.

Both writes use immutable idempotency keys, request hashes, receipts, audit and
outbox events. Reads are bounded and return only the caller's invitations. Native
dialogs are invalidated on actor/scope changes and retain the identical request
for retry after uncertain failures. No email delivery is added by this slice.

Verification: structural missing-command probe, rollback-only authorization,
scope, role, acceptance and replay tests; API transport tests; native form/inbox
tests and rendered review; analyzer and development Windows build.

Migration phases and rollback: preflight is read-only; candidate DDL and fixtures
end with ROLLBACK. Run the compatibility checker before application. Application
is one additive transaction with no fixture inserts. If it fails, verify no
partial objects remain. After successful application preserve the migration and
access/audit history, disable use of a defective new command, and apply a tested
additive correction. Never rewrite an applied migration or delete history.
