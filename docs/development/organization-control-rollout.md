# Organization administrator and platform control

This draft keeps the organization lifecycle, checkout, operator identity, and
managed HR SQL under `supabase/candidates/`. The isolated lifecycle test lists
the required application order. A deployment requires a separate review of the
SQL, Edge Functions, operator assignments, mail configuration, and rollback plan.

The standalone J Panel build uses `tools/admin-release/build.ps1` with the
approved project's public client configuration. The operator must have a
platform assignment and complete MFA. The installer without public project
configuration opens a setup notice.

Desktop and Employee candidate screens are enabled in development builds by
`--dart-define=JENTRA_ORGANIZATION_CONTROL_CANDIDATE=true`. The flag defaults
to false. Enable it only after the matching candidate backend is available in
the approved development project.

The platform control panel is available from Jentra Desktop to a separately
assigned platform operator. It is independent of any organization role.
Organization administrators use their assigned username and password. The
platform control panel retains its separate verification step, as do existing
restricted business approval paths.

## Organization handover

1. Open **Platform control**, configure the package and its price, and register
   the organization with the email address it used to sign up.
2. If appropriate, select organizations and apply an offer to that selection.
   For a free package or offer, enter a zero price.
3. Review the effective price and choose **Confirm activation**. For a paid
   activation, record the reference of the payment actually received; for
   zero cost, no reference is required.
   Jentra's existing synthetic subscription scheduler does not process
   payments. This workflow does not take a card payment or confirm one online.
4. Assign the first administrator a username and temporary password in the
   activation dialog. Delivery goes to the signup address recorded on the
   activation. Use **Add Administrator** with a different
   username when the same organization needs another administrator. The panel
   records delivery and password change status without exposing credentials.
5. The recipient signs in and replaces the temporary password. **Forgot
   Password** asks for the login and sends a short-lived code to the registered
   recovery address. The signup address is the default. An account holder can
   verify a replacement address in **Account profile**; the old address stays
   active until verification succeeds. An organization administrator can change
   their own password there.

## Hosted setup and release checks

- Start with a non-production Supabase project whose installed migrations
  match the intended release branch. Compare existing company/staff identity
  and role gates before integrating these migrations onto another branch.
- Deploy `org-identity` and `platform-organization-lifecycle` along with their
  matching database migrations and desktop build. Set
  `JENTRA_IDENTITY_RESEND_API_KEY`, `JENTRA_IDENTITY_MAIL_FROM` and
  `JENTRA_IDENTITY_CODE_SECRET` in the function environment. Test the verified
  sender with a controlled
  recipient; don't use customer addresses for release checks.
- Add `organization_manage = true` to the intended active platform operator
  row in `intelligence_control.operators` using a privileged release process.
  Nothing grants this capability automatically, and a tenant owner cannot
  grant it. Verify that the operator has working second-step verification.
- Set `JENTRA_ORGANIZATION_ARCHIVE_KEY` to a dedicated, securely generated
  Base64 encoding of 32 random bytes. Protect and escrow the key separately
  from the archive bucket; existing encrypted exports need the original key.
  Define archive retention and maintain the key until those exports expire.
- Leave `JENTRA_ORGANIZATION_PURGE_ENABLED` unset in live environments until
  a non-production rehearsal has verified two isolated organizations,
  end-to-end delivery and password reset, real Storage permissions and
  attachment uploads, restoration of a test archive, and deletion of the test
  organization only. Enable purge for that rehearsal in the test project.
  Take the normal project recovery backup before deploying to a live project.

## Lock, backup and purge

Lock an organization before exporting it. The lock denies fresh reads and
writes for that organization and freezes new uploads; already downloaded data
and previously issued file links are outside its reach. Unlock returns the
organization to its previous active or trial state. The platform archive is
encrypted at rest; the operator download is a sensitive JSON file and must be
stored securely.

The downloadable archive contains exact PostgreSQL JSON row data and each
included attachment's path, MIME type, SHA-256 and Base64 bytes. It does not
contain authentication passwords, hashes, sessions, or recovery challenges.
For restoration, use an isolated project with matching migrations and global
reference data. Validate the download checksum, reconstruct or map referenced
user identities, restore rows in foreign-key order with constraints enabled,
and upload verified attachment bytes to their original paths via Storage API.
Re-provision accounts with fresh credentials. The archive is an export format;
the panel does not provide automated restore.

Purge requires a completed backup from the current lock and the exact
organization slug. A new purge must start within 24 hours of the backup. Once
started, it cannot be unlocked; resume with the same backup if a Storage
request is interrupted. A database transaction deletes only the confirmed
tenant rows and refuses references from outside that scope. Dedicated Auth
accounts are removed afterward via Auth Admin; shared users are retained. The
panel can retry any pending Auth cleanup. The encrypted archive and minimal
operator evidence remain after deletion; download through **Retained
archives** in Platform control. Provider snapshots and logs follow their
separate retention policies. Object deletion uses the
[Supabase Storage API](https://supabase.com/docs/guides/storage/management/delete-objects)
to remove the stored file as well as its metadata.

The interactive export accepts at most 500 files, 20 MiB of attachment bytes,
10,000 rows per table, and 8 MiB of database row JSON. If the export refuses a
larger organization or an unclassified dependency, leave it locked and use a
reviewed offline archive and removal procedure. Reinstall the lifecycle write
guards in any migration that adds a new tenant-scoped table.

Local verification commands:

```powershell
node --test supabase/functions/tests/platform-organization-lifecycle.test.mjs
node supabase/tests/organization_identity.test.mjs
node supabase/tests/organization_lifecycle.test.mjs
node supabase/tests/combined_candidate_install.test.mjs
node supabase/tests/combined_field_sales_staged.test.mjs
node supabase/tests/combined_candidate_pgtap.test.mjs
```

The combined test applies every uninstalled candidate in timestamp order: the
company, Employee and Sales candidates first, then the organization control
candidates. Install them in that order. Organization control carries the Field
Sales permission restriction forward, and
`20261106106000_managed_login_membership_bridge.sql` lets managed sign-ins and
cutover rollback pass the company administration membership guard. Installing
Field Sales or company administration after organization control is not
supported.

## Organization creation and module control

`20261114090000_organization_creation_control.sql` installs last.

- **Who can create an organization.** Self-created organizations are refused
  with `SUBSCRIPTION_CHECKOUT_REQUIRED` by default. Organizations come from
  **Create New System** in the J Panel or from an approved checkout order.
  Accounts in `billing.subscription_trial_allowlist` are still exempt. An
  operator can change the rule in the J Panel with a reason; each change is
  recorded in `billing.platform_control_events`.
- **Module switches.** People, Assets, Projects, Service, Finance, Field Sales,
  Analytics and AI are switched per package under **Modules** on a package.
  Every module starts off. To give one organization a different set, create a
  package with that set and move the organization to it with **Change
  package**. The existing module checks read the organization's package, so a
  switch takes effect on the next request.
- **Field Sales.** Rep and company access to Field Sales needs
  `module.field_sales` on the organization's package; otherwise it is refused
  with `FIELD_SALES_ENTITLEMENT_REQUIRED`. Customer confirmation and delivery
  links for orders already in progress keep working.
- **Trials.** An organization registered as a trial gets a trial end from the
  package's trial days; an expired trial has no modules until it is activated.

## People access

- **Employee App logins.** A company-issued Employee App login carries the six
  Employee self-service permissions for its own entity and branch, so it can
  request leave and attendance, read its payslips, open HR cases and read
  published documents. Every other People permission is refused with
  `EMPLOYEE_SELF_SCOPE_DENIED`.
- **Payroll reads.** `20261114100000_people_access_hardening.sql` makes
  `people.payroll.view` need an MFA session, like payslips and payroll
  corrections. Without one the read is refused with `PAYROLL_MFA_REQUIRED`.
- **Own records.** A leave decision (`LEAVE_SELF_DECISION_DENIED`) or an
  attendance decision or cancellation (`ATTENDANCE_SELF_DECISION_DENIED`) is
  refused when an accepted account link ties the decider to the employee on
  the record. Withdrawing your own leave is unaffected.
- **Multi-day leave.** `20261114110000_people_leave_range.sql` installs after
  the People access candidate. A leave request still covers one work slot; a
  date range of up to 31 days becomes a batch of those requests, one per
  working day. `api.people_leave_request_range` creates the drafts, skipping
  days without a weekly slot and days a calendar override closes, and
  `api.people_leave_batch_command` submits, approves, rejects or cancels every
  day together through the existing leave command, so independence, MFA, the
  balance check and the self-decision rule apply to each day. Either call
  leaves nothing behind if any day fails. With Employee self-service
  installed, `api.employee_self_leave_range_submit` submits an employee's own
  range, and `api.employee_self_receipt` reconciles it like a single request;
  the candidate replaces that function and widens the two `rpc` checks on
  `employee_self.receipts` and `employee_self.abandoned_commands`.
  `supabase/tests/people_leave_range.test.mjs` runs its assertions alone.

## Field Sales reps

`20261117090000_field_sales_reps.sql` installs after the People access
candidate and needs Field Sales installed.

- **Rep to employee.** A rep's employee comes from the accepted People account
  link for its sign-in. Field Sales stores no second link, so linking or
  revoking in HR changes the rep's label on the next read. A rep without an
  accepted link shows as `Unlinked member ····1234`, the last four characters
  of its user id. Labels never show an e-mail address.
- **Rep list.** `api.field_sales_reps` gives a company and branch reviewer (MFA,
  `sales.field.portfolios.manage` or `sales.field.discounts.decide`) each rep
  with a customer assignment or an order request in the branch: its label, its
  current customer count, and the order requests it submitted in the period by
  current state, with the approved total in base currency as an exact decimal.
  The period uses the company's local dates and may be up to a year. A rep
  cannot read it. Targets and commission are not part of it.

## Field Sales visits

`20261117100000_field_sales_visits.sql` installs after the rep list and needs
Field Sales installed.

- **Visits.** `field_sales.visits` records a rep's visit to a customer it is
  currently assigned: the purpose, an optional planned date, check-in and
  completion times, the outcome and the next action. A visit is tied to the
  assignment it was planned under and is scoped by company and branch.
- **One command.** `api.field_sales_visit_command` plans, checks in, completes
  or cancels a visit (`sales.field.visits.record`). Like an order request it
  takes a command id, an idempotency key and, except when planning, the
  expected version; an exact retry returns the original receipt, and
  `api.field_sales_visit_receipt` recovers a command whose response was lost.
  The assignment is checked first, so a revoked portfolio cannot replay or
  recover a visit command.
- **Location.** Optional, and only given at check in or completion, as a
  latitude and longitude pair of decimal strings. Nothing tracks a rep between
  those actions.
- **Reads.** A rep reads only its own visits to customers it is still
  assigned (`api.field_sales_visits`). A company reviewer reads the branch's
  visits for a period with each rep's label
  (`api.field_sales_company_visits`), with the same readers as the rep list.
- **Field accounts.** `sales.field.visits.record` is on the field account
  permission list in both `20261031090000_field_sales_governance.sql` and
  `20261105102000_organization_identity.sql`, and the four visit commands are
  allowed past Field Sales' legacy receipt guard.

The older suites create their fixtures through self-service and predate the
Field Sales switch, so they switch enforcement off and Field Sales on after
`organization_creation_control.assertions.mjs` has checked the defaults.

The staged Field Sales test replays the six Field Sales exercises with
organization control installed. Each exercise needs the state right after its
own candidate, so that test applies organization control before the later
Field Sales candidates; it is a compatibility check, not the install order.

The pgTAP test runs the company access and Employee harnesses on the combined
install. It needs the official pgTAP 1.3.4 `pgtap.sql.in` at
`build/pgtap-1.3.4.sql.in`, or at the path in `JENTRA_PGTAP_SOURCE`, and
checks its SHA-256.

The SQL harness uses the existing local PGlite runtime in
`build/launch-validation-runtime`, or a compatible PGlite runtime set in
`JENTRA_PGLITE_MODULE`. Its Auth and Storage service tables are local fixtures.
