# Controls after MFA: development repair

Date: 2026-09-11. Project: `xpdoufauvrbdmxgngetv`.

## Confirmed causes

Capability loading watched the selected scope and actor ID. MFA completion and
token refresh can retain both, leaving old permissions cached. The old running
Windows dashboard showed Jentra Acceptance Lab but omitted Business setup,
CRM, Sales, Inventory and Fulfillment & receivables from the sidebar.

Quick create also contained six empty `onPressed` handlers. The dashboard's
metrics and activity are explicitly sample content; Procurement, Finance,
People, Projects, Service, Analytics and Control remain placeholder modules.

## Repair

- A non-sensitive auth event revision refreshes capability reads and the MFA
  gate after MFA verification, session refresh, sign-in and sign-out.
- Tenant membership reloads when the authenticated actor changes.
- Quick create offers only implemented Customer, Quotation and Invoice draft
  workspace links, gated by current view and manage permissions. Loading or
  failed access checks hide these actions; an error offers retry.
- Customer selects the Parties setup resource; Invoice selects the invoice
  register. Record creation remains explicit in the destination workspace.
  An existing receivable draft prevents a shortcut from changing its kind.

## Verification

Three regression tests first reproduced stale permissions after MFA, stale
permissions after token refresh and stale tenants after an account switch.
The fixed tests use the public Supabase auth methods with synthetic HTTP
responses. No real passwords, tokens or MFA secrets are captured.

The full desktop suite passes **151 tests**, including five Quick create tests,
two invoice shortcut tests and three auth regressions. Analyzer: **No issues
found**. The new Quick create golden was rendered and visually reviewed.

Evidence: `auth-controls-red.log`, `auth-controls-desktop-tests.log`,
`auth-controls-analyzer.log`, `auth-controls-windows-build.log` and
`../../../apps/jentra_desktop/test/goldens/quick_create_workspace_links.png`.
Intermediate failing test logs are retained separately from the final full run.

The development-configured Windows release built successfully in **65.3 seconds**.
The old idle dashboard was closed and the rebuilt executable launched. A fresh
native screenshot and accessibility tree show the development sign-in screen
with email/password fields and sign-in controls exposed to accessibility.
The prior session was not restored. The user must sign in and complete MFA before
the repaired sidebar and Quick create can be verified in this native session.
This is build/startup and widget-test proof, not completed authenticated UI proof.

Later user confirmation, 2026-09-11: the user signed in and confirmed that
Create → Customer and the Sales, Inventory and Fulfillment & receivables sidebar
destinations work. This closes the reported control check; it does not sign off
the remaining transaction walkthrough.

Formatting: nine affected Dart files checked, zero changed. `git diff --check`
passes with the repository's normal line-ending configuration. The installed
stock-opening migration file's SHA-256 remains
`063f8a8b91c502730ed51e52f014faf080fbe8b497c611e55e0f8054de44a3d0`.

## Development and acceptance boundary

Fresh read-only counts: two users, one verified MFA factor, one tenant, one
active membership, one role assignment, 87 role permission entries; 32
migrations, latest `20260910201410`. The user created the workspace and handled
MFA. No database mutation, staging, commit, push or production operation was
performed for this repair. Existing dirty source work is preserved.

Governed business masters, independent approver membership, authenticated
transaction walkthrough, opening-specific restart recovery and owner signoff
remain pending. Dashboard samples and placeholder modules are not live data.
