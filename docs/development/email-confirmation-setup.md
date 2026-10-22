# Email confirmation for Jentra OS Windows

Prepared 21 October 2026 for development project `xpdoufauvrbdmxgngetv`.
The reported email arrives; this work diagnoses its confirmation destination.
SMTP, accounts and hosted Auth settings have not been changed.

The [public diagnostic](../verification/auth/email-confirmation-redirect-20261021.json)
used deliberately invalid tokens and never followed a redirect. At 10:17:35 UTC
(15:47:35 in Sri Lanka), email sign-in was enabled and email confirmation required.
The requested callback with a fresh random path was preserved. Without an explicit
redirect, the server returned the literal path `/auth/callback/*` on
`http://127.0.0.1:56327`.

That default destination is not a concrete callback route. It suggests a wildcard
was saved as the default Site URL, but private URL configuration and the deployed
template have not been read. The probe establishes error-redirect selection only;
it does not prove that a valid email can confirm or that a native session works.

## Correct the hosted URL and template

1. Open [Authentication → URL Configuration](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/url-configuration).
   Put this pattern under **Redirect URLs**, preserving the other valid entries:

   ```text
   http://127.0.0.1:56327/auth/callback/*
   ```

   Keep a legitimate existing **Site URL**. If that field currently contains the
   wildcard pattern, move the pattern into Redirect URLs and have the owner supply
   the intended concrete, reachable fallback page. Site URL is a default destination,
   not a redirect pattern. The desktop passes its exact callback for each attempt.
   [Supabase redirect configuration](https://supabase.com/docs/guides/auth/redirect-urls).
2. Open [Authentication → Email Templates](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/templates)
   and inspect **Confirm signup**. The confirmation button should use the full
   Supabase verification URL:

   ```html
   <a href="{{ .ConfirmationURL }}">Confirm your email</a>
   ```

   A manually assembled `{{ .SiteURL }}` link does not replace verification.
   `.ConfirmationURL` contains the verification token and the requested return URL.
   Keep email confirmation enabled. Editing local `supabase/config.toml` does not
   change this hosted project. [Supabase template variables](https://supabase.com/docs/guides/auth/auth-email-templates).

These are project-admin settings. A rejected management login cannot be repaired
with the client publishable key. No client secret, password or confirmation link
belongs in chat, source, screenshots or diagnostics.

## Finish confirmation in the updated app

The [packaged development build](../../build/jentra-email-confirmation-20261021/Jentra-OS-Windows-development.zip)
includes the updated flow. Extract all files into a new folder and run
`jentra_desktop.exe`. Its [verification record](../verification/auth/email-confirmation-windows-20261021.json)
records 1,227 platform tests, 31 login widget tests, clean scoped analysis, the
Windows release and archive hashes. These are automated checks, not real-email
or authenticated native acceptance.

The updated Windows flow starts a private PKCE listener before account
creation or resend and passes its exact per-attempt return URL. Keep Jentra OS open
while opening the email. A random path from an earlier attempt will not match a new
listener, so **Resend confirmation** creates a fresh return channel and link.

- If an older link opened a dead localhost page, return to Jentra OS and first try
  the email/password sign-in. Verification may already have happened before the
  browser failed to reach the final page; do not assume that it failed.
- If the account still requires confirmation, use the updated app's resend action,
  open the newest email on the same Windows computer, and keep that app instance
  open until it finishes. Avoid sharing or reusing the old link.
- If a mail client cannot return to the app, use the updated app's original-link
  fallback with the unmodified confirmation link from the newest email. Enter it
  only in the app. Do not paste a browser's final redirected localhost URL, since
  it may already have consumed the one-use verification link.

The native flow and original-link fallback require their new build. These
instructions do not claim that an older installed executable already has them.

## Verify the result

Run `powershell -File tools/auth/check_email_confirmation_redirect.ps1` for the
read-only diagnostic. It writes only selected public flags and sanitized redirect
origins/paths to the JSON record; it sends no email and uses no real token. Its
invalid-token method was checked against the current
[Supabase Auth verify handler](https://github.com/supabase/auth/blob/master/internal/api/verify.go).

Then perform real acceptance privately: create or resend only the intended test
account, open the newest email while the app is waiting, confirm a session appears,
sign out and sign back in, and check that invitations/workspace setup and MFA still
gate business access. Record time, build and pass/fail; omit the email link and all
credentials. Public probe success and automated callback tests are separate from
real email confirmation and authenticated Windows acceptance.
