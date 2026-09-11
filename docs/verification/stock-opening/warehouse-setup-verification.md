# Warehouse setup verification

2026-09-11; development project `xpdoufauvrbdmxgngetv`.

## Delivered

Business setup → Catalogue now includes Warehouses. The form has a named branch
selector, defaults to the selected branch, and preserves branch/entity scope
when editing. View-only users cannot create records. Existing draft, offline and
version-conflict behavior is reused.

The new named `api.upsert_warehouse` command is installed by additive migration
`20260911065744_governed_warehouse_setup.sql`. Its private implementation enforces
scope, active branch/entity references, permission/MFA, field validation,
immutable scope, optimistic versions and idempotency; accepted commands create
receipt, audit and outbox records. No stock or journal is created by this command.

## Evidence

- The initial domain tests and database existence check reproduced the missing
  warehouse contract. Final domain suite: **83 passing tests**.
- The database suite passes **24 assertions**, using only temporary synthetic
  fixtures in a transaction that rolls back. A subsequent query confirms zero
  leftover fixture users/tenants and zero persistent warehouses.
- Desktop full run: **152 pass**, with only the new warehouse golden failing
  because it captured the label animation before settling. The test now waits
  for the settled form. Both affected tests pass after reviewing/regenerating
  that new golden and rerunning without updates: **153 unique tests verified**.
Existing golden baselines were not regenerated for this warehouse slice.
- Analyzer: **No issues found**. The settled warehouse form was visually reviewed.
- Applied migration SHA-256:
  `4058f7cfca8fb2ce3f77799448dfa726f5c4acfa6f892bd43c0ca42d42c5f09c`.
  Existing stock-opening migration SHA-256 is unchanged:
  `063f8a8b91c502730ed51e52f014faf080fbe8b497c611e55e0f8054de44a3d0`.

Logs: `warehouse-domain-red.log`, `warehouse-domain-full-tests.log`,
`warehouse-database-tests.json`, `warehouse-desktop-tests.log`,
`warehouse-widget-tests.log`, `warehouse-analyzer.log` and
`warehouse-windows-build.log`. Render: `../../../apps/jentra_desktop/test/goldens/warehouse_setup_form.png`.

The development-configured Windows release built in **108.9 seconds** and was
launched. Fresh native screenshot/accessibility observation shows the development
sign-in screen. Warehouse creation in the authenticated native session awaits
owner sign-in and MFA, which the user handles. Executable and Dart AOT hashes are
recorded in `warehouse-verification.json`. Six affected Dart files pass the
format check with zero changes; the repository's normal `git diff --check` passes.

## Remaining setup

The existing acceptance tenant/entity/branch are confirmed. The target records
are prepared in `setup-targets.json`; they have **not been created**. The user
selected `test@lh.com` as independent approver. That account exists but has no
workspace membership. Warehouse creation, unit/products, accounts/period,
numbering, workflow/approval matrix and scoped approver membership remain before
the native stock-opening transaction walkthrough. No invitation was sent.

The security advisor still reports the pre-existing leaked-password-protection
warning; no new database security finding appeared. Remediation:
[Supabase password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Performance advisor reports unused indexes in the low-traffic development database;
none were removed. No production operation, staging, commit or push occurred.
