# Temporary Jentra test profile — 2 November 2026

The owner requested a temporary email and password for system testing. One
real Mail.tm inbox and one genuine Supabase Auth account were created for
project `xpdoufauvrbdmxgngetv`.

- Display name: **Jentra Temporary Tester**.
- Email: `jentra-test-4dd40f8b1f69@fldubai.com`.
- Auth user: `89f63c7a-dc28-4f33-859e-eae277193522`.
- Mailbox creation returned HTTP 201; password authentication and `/me`
  independently verified that exact inbox.
- Normal Jentra signup returned HTTP 500 / `unexpected_failure`. A filtered
  Auth Admin lookup then confirmed no account existed for the exact email.
- Auth Admin created that one test user with email confirmation enabled for
  this controlled profile. This does not establish confirmation-mail delivery.
  Global email-confirmation settings were unchanged.
- A real password grant and an independent Auth `/user` readback verified the
  exact new identity at `2026-11-02T13:00:01.696Z`. No session was fabricated.
- The web app was signed in through its ordinary password form and reached
  `/#/dashboard`. The installed owner's native app session was preserved.

The two separate generated passwords are saved only under the ignored local
directory `build/temp-test-profile-20261102/`. The owner-facing file is
`TEST-LOGIN-PRIVATE.md`. It must not be committed, pasted into logs, or used
for a permanent account. Both password files have protected Windows ACLs
granting access only to the owner's Windows account, SYSTEM and Administrators.
Mail.tm is a temporary mailbox provider:
<https://mail.tm> and <https://docs.mail.tm/>.

## Confirmed business-loading blocker

The new genuine account's `POST /rest/v1/rpc/list_my_tenants`, using the
application's `api` profile, returned:

```text
HTTP 406
PGRST106
Invalid schema: api
Only the following schemas are exposed: public, graphql_public
```

The app consequently displays **Could not load your businesses**. This
matches the installed app's previously observed HTTP 406 business-list calls.
The Supabase Data API Settings page independently shows two exposed schemas.
Repository `supabase/config.toml` specifies `api` as an intended exposed schema,
and the installed/current gateway explicitly uses `.schema('api')`.

The proposed repair adds only `api` to the current `public, graphql_public`
exposed-schema list. It leaves other configuration, object privileges, RLS,
authentication, business memberships and function definitions unchanged.
Because that makes the application API surface reachable, explicit
action-time approval was requested before changing the hosted setting. It
has **not been applied** in this record.

No business membership or role has yet been granted to the temporary account.
It has no authorized access to a real company. Scoped synthetic-workspace
access, runtime-scope renewal, a genuine governed model invocation, exact
persisted usage, and original external-delivery acceptance remain outstanding.

The account itself has no automatic expiry. Its mailbox is temporary; removal
of the test account and local credentials is a separate explicit cleanup step.
No payment method, paid plan, migration, existing-account update, model call,
delivery replay, commit or push was performed for this profile creation.
