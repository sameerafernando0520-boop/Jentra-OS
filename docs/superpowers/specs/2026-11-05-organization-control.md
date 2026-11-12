# Organization access and platform control

Date: 2026-11-05. Implementation target: the checked-out Jentra OS workspace.

## Context

An organization buys or is granted a package, and receives its own administrator account. Jentra OS already separates tenant memberships from platform operators and has a subscription ledger. The synthetic subscription scheduler is not a payment provider or proof of payment.

## Requirements and acceptance

| ID | Requirement | Acceptance |
| --- | --- | --- |
| AC-1 | Organizations sign in without a separate authenticator prompt. Keep platform operator and sensitive transaction authority separate. | A password session can enter its organization, cannot enter the operator panel, and cannot bypass a separate approval policy. |
| AC-2 | After confirmed activation, deliver the assigned username and initial password once to the signup address, which becomes the default recovery address. A package priced at zero requires no payment. | Before activation no credentials are sent. After activation only the intended address receives them. Multiple administrators can be added to one organization without sharing an account. |
| AC-3 | Allow an administrator to replace their own password and set a verified recovery address. Forgot Password sends a short-lived, single-use code to the registered recovery address. | Unknown accounts get the same reset acknowledgement. Invalid, expired, reused, and over-limit codes fail. The operator sees password change status/timestamp and can issue a new temporary credential; no current password or password hash is displayed. |
| AC-4 | Platform operators can manage organizations, packages and their prices, and apply offers to selected organizations in a single operation. | A regular organization administrator cannot call the operator API. A bulk offer affects exactly the selection. Price or offer updates do not rewrite paid history. |
| AC-5 | Operators can lock and unlock an organization, with a reason. | An already signed-in member loses access to the locked tenant's online data and writes; access to other organizations is unchanged. Unlock restores the previous active or trial status. |
| AC-6 | An operator can create a tenant archive and explicitly purge a locked organization using that backup. | The private archive includes tenant rows and Storage bytes. Purge requires a verified current backup and exact slug confirmation, rejects unscoped references, can resume after an interrupted Storage removal, and preserves other tenants and shared accounts. |

## Constraints and data

- Use existing password hashing and session authority. Recovery/initial credentials must not be readable from the admin panel, retained in cleartext by application storage, or logged.
- Use a transactional delivery provider for signup and recovery email. Treat failed delivery as a failed/retryable step rather than a successful handover.
- The organization lock has a unique epoch and remembers prior status. Backup receipts record that epoch, a storage manifest and checksums. An explicit purge start is irreversible and prevents unlock. Files are removed via the Storage API; database deletion remains transactional with foreign keys enforced.
- Backups and purge requests are deliberately bounded and fail closed when data exceeds the supported export size or a new storage/data dependency is unclassified.
- The archive is a private export of tenant data. Authentication hashes, sessions, hosted provider logs, and platform-wide backups are outside its scope. Operator evidence may retain a minimal record that the purge occurred, without copied tenant business data.

## API surface

Use a dedicated platform control route, private operator-checked Data API functions, and server-side Edge Functions for mail, account provisioning and organization archives. User recovery and change-password flows use the login screen and account profile. Lifecycle API: lock/unlock with tenant ID and reason, create an archive for a locked tenant, download by backup ID, and purge using that backup ID and the tenant slug.

## Release boundary

Verify with synthetic organizations, an email capture or test mailbox, and an isolated database/storage target before hosted activation. Connect a real purchase confirmation only through a trusted provider integration; where none exists use operator-recorded confirmation for payments received outside Jentra. Never run a purge against a live organization as part of implementation testing.
