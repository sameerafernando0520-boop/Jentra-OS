# Google sign-in setup for Jentra OS Windows

## Update: 22 October 2026

The owner selected `xpdoufauvrbdmxgngetv` as the production app's connection
target on 22 October. The Windows package uses that explicit designation; this
does not change hosted provider settings or retroactively change the development
verification below. A fresh, read-only public Auth check on 22 October still
reports Google disabled, email enabled and email confirmation required.

To finish Google setup, open this exact project's
[Google provider settings](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/providers),
select Google, enable it, enter the existing **Web application** client ID and
secret privately, and save. In Google Cloud, that client must allow
`https://xpdoufauvrbdmxgngetv.supabase.co/auth/v1/callback`. In this project's
[URL Configuration](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/url-configuration),
append `http://127.0.0.1:56327/auth/callback/*` under Redirect URLs and save.
Preserve other URLs and do not set the literal wildcard as the default Site URL.
Keep Jentra open during the browser return. Real consent and the returned native
session still require acceptance after Google is enabled; never share the client
secret in chat or include it in a desktop build.

## Development verification recorded on 21 October

Prepared 21 October 2026 for development project `xpdoufauvrbdmxgngetv`.
This runbook does not establish that hosted Google sign-in is enabled or that a
real account has completed the browser return. Production configuration is separate.
The owner chose to reuse an existing Google OAuth Web client. The
[public provider check](../verification/auth/google-provider-20261021.json) at
09:42:27 UTC on 21 October 2026 (15:12:27 in Sri Lanka) still reported Google
disabled. Real Google browser-return acceptance remains unverified.

The Windows app opens the system browser, receives one authorization code through
a private loopback listener, and exchanges it through Supabase using PKCE. Keep
the app open throughout sign-in. These two redirects have different destinations:

| Configure in | Value | Purpose |
|---|---|---|
| Google OAuth client → Authorized redirect URIs | `https://xpdoufauvrbdmxgngetv.supabase.co/auth/v1/callback` | Google returns to hosted Supabase Auth |
| Supabase Auth → URL Configuration → Redirect URLs | `http://127.0.0.1:56327/auth/callback/*` | Supabase returns a code to this Windows process |

The final Windows path segment is random for each attempt. The app validates that
exact path and Host, accepts one GET/code, and rejects duplicate or token-bearing
queries. Do not substitute `localhost`, another port, or a broad host wildcard.

## Configure the Google client

1. Select the intended development Google Cloud project in
   [Google Auth Platform](https://console.cloud.google.com/auth/overview).
   Configure **Branding** with Jentra OS and the owner's support/contact details.
   Choose **External** for testers outside the Google Workspace organization;
   **Internal** restricts the audience to that organization. While using a testing
   audience, add the intended Google accounts under **Audience → Test users**.
   [Google consent-screen setup](https://developers.google.com/workspace/guides/configure-oauth-consent).
2. Under **Data Access**, use only `openid`,
   `https://www.googleapis.com/auth/userinfo.email`, and
   `https://www.googleapis.com/auth/userinfo.profile` for sign-in.
   [Supabase required scopes](https://supabase.com/docs/guides/auth/social-login/auth-google#setup-required-scopes).
3. Under **Clients**, select the existing **Web application** OAuth client chosen
   by the owner. Add the exact Google-to-Supabase callback from the
   table. Copy the client ID and secret privately into Supabase's provider settings.
   [Google web-client setup](https://developers.google.com/identity/protocols/oauth2/web-server#creatingcred).

The confidential client is hosted Supabase Auth; the Windows executable does not
contain a Google client secret. Keep secrets out of chat, source, logs, screenshots,
client build defines and delivery ZIPs. The Firebase admin key is unrelated to
Google OAuth client setup and must stay ignored.

## Configure hosted Supabase

4. Open [Authentication → Sign In / Providers](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/providers).
   Enable **Google**; enter the Web client ID and secret. Keep nonce checking
   enabled. Equivalent Management API fields are `external_google_enabled: true`,
   `external_google_client_id`, and `external_google_secret`.
   [Supabase Google setup](https://supabase.com/docs/guides/auth/social-login/auth-google#project-setup).
5. Open [Authentication → URL Configuration](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/url-configuration).
   Append the Windows redirect from the table, preserving the existing Site URL
   and other redirects. Its single `*` covers the random final segment.
   [Supabase redirect matching](https://supabase.com/docs/guides/auth/redirect-urls#use-wildcards-in-redirect-urls).

Editing `supabase/config.toml` configures the local stack; it does not update the
hosted project. For a local Supabase stack, use its own Google callback
`http://127.0.0.1:54321/auth/v1/callback`, enable `[auth.external.google]`, and supply
the secret through `env(SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET)`. This configures
Supabase only: the current Windows provider preflight requires HTTPS, so the local
HTTP Auth endpoint is not supported by that preflight. These local-stack settings
do not prove the Windows app can use HTTP localhost Auth. Never reuse the hosted
callback with a local backend.

## Verify on Windows

6. Start the connected development build. Confirm its project is
   `xpdoufauvrbdmxgngetv`; click **Continue with Google** once.
7. Select an authorized Google account in the browser. Complete Google's consent
   there; keep passwords and MFA codes private. Confirm the browser reports success
   and Jentra OS opens its signed-in route.
8. A new identity must still join an invited workspace or complete the existing
   first-workspace setup. Verify that sign-in alone does not assign business roles,
   entitlements or privileged access. Existing MFA requirements still apply.
9. Sign out and repeat; also test denied consent, closed browser, occupied callback
   port, offline connectivity and retry. A failed attempt must leave no signed-in
   session. Use the app's displayed recovery message rather than copying callback
   URLs or provider errors into evidence.
10. Record build/revision, Windows/browser versions, time, anonymized outcome and
    pass/fail. A public settings check or synthetic callback test is separate from
    this real Google sign-in acceptance.

If Google reports `redirect_uri_mismatch`, compare its callback character for
character. If Google succeeds but Windows never receives the return, check the
Supabase Windows allowlist and that the app is still running. If Google is disabled,
an administrator with access to this exact Supabase project must finish steps 4–5.
