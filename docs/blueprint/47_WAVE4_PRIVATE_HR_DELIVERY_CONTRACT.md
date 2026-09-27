# W4-02B private HR delivery contract

2026-09-27. Synthetic development only. Parent: contract 42. Candidate, storage
and worker deployment require their own reviewed owner approval. No existing role
or plan changes. Operational employee/calendar schemas remain immutable.

## Private classes and capability boundaries

`people_private` is an API-only forced-RLS schema. Contact profile fields are
personal email/phone/postal address and emergency contact name/relationship/phone;
all nullable bounded strings. No health, identity, bank, compensation or automatic
scoring fields. Immutable revisions retain private reasons and keyed digests.
Generic receipts/audit/outbox contain IDs, versions, class/status and keyed digests
only. Public error codes never include values or storage paths.

Private contact view/manage, documents view/manage, reviews view/manage, retention
manage, export, erasure, account-link manage and self view are independent explicit
permissions. Mutations require MFA. Current membership, People entitlement,
tenant/entity/branch and employee ancestry are checked before every read, command,
replay and trusted document request. HR subjects expose only IDs/code/display name
under one of these dedicated capabilities, without depending on directory grants.
Private history pages have a hard bound of 50.

## Retention, storage and trusted worker

One versioned entity policy names `synthetic-contact`, `synthetic-review` and
`synthetic-document`, their testing purpose, and an explicit test-cycle close.
Expiry is 30 days after that close. This is a development cleanup rule. A hold has
a private reason and review date; hold removal is separately attributable. A hold
blocks erasure. Once a purge lease starts, a new hold is rejected instead of
claiming that already-issued storage deletion can be recalled.

Content is not accepted until `w4-private-hr-v1` worker readiness exists. A trusted
secret-key Edge worker uploads, verifies and removes a synthetic storage probe
before registering its reviewed artifact digest. Readiness expires after 26 hours;
successful bounded runs refresh it. Deployment/scheduling and live probe proof
remain gates until separately approved and verified.

Bucket `jentra-hr-private` is private, capped at 10 MiB, and permits text/plain,
image/png, image/jpeg and application/pdf. A restrictive bucket guard prevents
broad authenticated Storage policies granting direct access. Service keys stay in
Edge Functions. Every request first obtains a user-scoped 30-second ticket, then
the trusted component consumes it once, rechecking the actual membership, scoped
roles and subscription. Paths are internal opaque IDs. Uploads never overwrite;
retries compare actual bytes/checksum before confirming. The trusted component
streams downloads without signed URLs and rechecks current user authorization
before returning bytes. Export needs its own capability and explicit local save.

SQL reservation, Storage upload and SQL confirmation are distinct stages. Exact
IDs/checksum/size/MIME permit safe retries after uncertainty; no claim of a single
cross-service transaction. Document bytes, paths and access URLs never enter drafts.
At most 50 documents per employee keep erasure bounded.

Worker jobs lease at most 50 employees, expire access before deleting content,
delete through the Storage API, then redact SQL payloads/paths. Failed leases retry
with the same job/path identities. Holds and jobs serialize with employee and
entity locks. System erasure has truthful `actor_kind=system` evidence; it does not
fabricate an Auth user to satisfy generic audit's non-null actor constraint.
Requested erasure records its real initiating actor. Minimal keyed digests and
attributable metadata survive; contact/review text and document objects do not.

## Reviews and exact account links

Reviews have at most 20 objectives of 1,000 characters each, 4,000-character text,
finite periods of at most 366 days, and immutable attributable revisions. Named
commands implement draft → submitted → reviewed → acknowledged → closed. Later
edits append a revision and reset to draft for resubmission. Reviewer must be a
different employed employee for the entire period, explicitly authorized, linked
to the actual authenticated reviewer, and independent of the revision author.
The subject can see shared submitted evidence with an active link and self view;
acknowledgement records receipt without agreement or pay effects.

HR with MFA selects an exact active membership/user UUID pair; no email matching,
invitation, account creation or role grant. Target accepts/rejects in its own
authenticated session within 24 hours. Pending/accepted uniqueness covers employee
and tenant user; expired proposals become minimal history. Revocation takes effect
on every self projection and replay. Self view remains a separate capability.

## Recovery, native use and verification

Private text drafts are encrypted under actor/tenant/entity/branch/employee/class,
have a fixed 24-hour local TTL (not extended by edits), and are removed before
decryption when expired. Current dedicated access is required before loading.
Uncertain requests retain their exact envelope; after local expiry only a minimal
own-command receipt query may resolve uncertainty. Documents keep metadata only.
Visible text/bytes clear on access/context loss and stale async responses are
discarded. No private values are interpolated into logs, errors or generic search.

Native workspaces expose independent contact/document/review/link/retention panes,
scoped named pickers, loading/empty/denied/unavailable states, revision comparison,
explicit sealed retry and explicit export. Tests cover security/PII redaction,
retention readiness/holds/erasure, link identity/expiry/revocation, independent
review decisions, exact recovery and late failure atomicity. Node tests exercise
injected trusted handlers; Deno compilation, deployed worker/storage, authenticated
native use, real OS-keystore restart and contention are separate evidence.
