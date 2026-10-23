# Employee Firebase integration and activation

The agreed architecture keeps all sign-in, employee identity and HR data in
Supabase project `xpdoufauvrbdmxgngetv`. Firebase project `jentra-os` supplies
Hosting for the employee browser app and Android Cloud Messaging transport.
This is not a migration of HR records or passwords into Firebase.

## Configured client identities

| Client | Package / site | Firebase app ID |
| --- | --- | --- |
| Android development | `com.jentra.employee.dev` | `1:775894665214:android:3f4c4f8d683ebba7a1e2af` |
| Android production identity | `com.jentra.employee` | `1:775894665214:android:06ddbc832d4bda0da1e2af` |
| Employee browser preview | Hosting site `jentra-os` | Uses Supabase sign-in; no Firebase Auth or web messaging SDK |

Android client configuration was fetched through the existing Firebase CLI login.
It contains public client identifiers for both packages. The ignored Firebase
admin-key file was neither opened nor packaged. Neither the production Android
app registration nor a compiled development APK establishes store signing or
device push acceptance.

The browser uses encrypted IndexedDB records and a nonextractable Web Crypto
key, with one Web Lock per origin/project to protect pending commands from
competing tabs. This protects stored records against casual plaintext inspection;
it does not protect against malicious JavaScript executing in that origin.
Browser data eviction removes local recovery. Unsupported capabilities fail
closed. Password sign-in uses the current tab. A future OAuth flow must also
respect the single-tab store owner; an independent popup cannot take its lock.

## Required before real Android notifications

1. Run the [isolated push database suite](employee-push-candidate.md), review
   concurrent registration/worker behavior, then obtain the owner's separate
   approval for installing its candidate SQL and deploying its sender. Nothing
   in the client build installs that SQL or starts a schedule.
2. Use a dedicated Google service account authorized to send FCM messages in
   `jentra-os`. The documented predefined role is **Firebase Cloud Messaging API
   Admin** (`roles/firebasecloudmessaging.admin`); a reviewed custom role with
   only the required send permission is also possible. Do not grant Owner or
   reuse a broad Firebase administrator key for this sender.
3. Enter the four server values from the candidate guide directly in the
   approved Supabase Edge Function secrets interface. They include the sender
   service account email/private key and a random scheduler secret. Do not
   paste them into chat, source, SQL, Flutter configuration or the hosted bundle.
4. Add an authoritative, recipient-scoped HR event producer. The candidate
   mirrors existing `people.*` workflow notifications; it does not manufacture
   absent leave/payroll/attendance events or complete their employee screens.
5. Test on an Android device with Google Play services using a permitted
   employee account: opt in, deny permission, background/foreground receipt,
   generic lock-screen content, sign-out, switch employee, expired session,
   revoke account link and retry interrupted requests. Real delivery remains
   unverified until these checks pass.

## Required before live browser promotion

Review the actual HTTPS preview, including sign-in, reload, background masking,
MFA, photo selection/cancel, keyboard/screen-reader access, and all three
languages at enlarged text. Confirm the served bundle hash and response headers
against the immutable staging manifest. Inspect the existing live origin for a
legacy Flutter service worker and prepare targeted cleanup if present.

Hosted Auth metadata currently has a Windows loopback Site URL and an empty
redirect allowlist. Prepare exact browser/live callbacks and retain the approved
Windows callback for desktop use; change these settings only with separate
production approval. Enabling Google requires the existing Google OAuth client
to be configured privately in that exact Supabase project. Browser password
sign-in does not by itself prove confirmation, recovery or OAuth redirects.

The QA workspace's Starter plan currently has `module.people=false`. Do not
enable People globally for all Starter tenants to bypass this. An approved,
properly scoped HR-enabled test workspace and employee link are required.

## Production distribution

The local `.dev` APK is for testing and retains the existing development signer.
Store distribution needs the owner's chosen application/store identity and
release signing configuration, supplied privately. No keystore, signing password,
Supabase management token, MFA code or server credential should be sent in chat.

References: [Firebase HTTP v1 authorization](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[FCM roles](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging),
[Firebase client API-key guidance](https://firebase.google.com/docs/projects/api-keys),
and [Hosting preview process](../../tools/employee-web/README.md).
