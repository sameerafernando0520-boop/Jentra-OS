# Organization administrator and platform control

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
```

The SQL harness uses the existing local PGlite runtime in
`build/launch-validation-runtime`, or a compatible PGlite runtime set in
`JENTRA_PGLITE_MODULE`. Its Auth and Storage service tables are local fixtures.
