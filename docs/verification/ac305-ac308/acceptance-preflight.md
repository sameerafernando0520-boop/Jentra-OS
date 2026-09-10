# Signed-in Windows acceptance preflight

Date: 2026-09-10. Status: prepared; waiting for the first synthetic test account
and manual authentication. This is not completed end-to-end acceptance.

## Current evidence

- Development project `xpdoufauvrbdmxgngetv` is `ACTIVE_HEALTHY`.
- Ledger: 31 migrations, latest `20260910135507`.
- Read-only counts: zero auth users, active memberships, tenants, legal entities,
  branches, customers, products, fiscal periods and workflow definitions.
- Created ignored local `.env.acceptance.json` using this project's existing
  active public publishable key, verified with `git check-ignore`. It contains no
  service-role key, password, MFA secret or production configuration.
- Built the development-connected Windows release successfully in 64.5 seconds:
  from `apps/jentra_desktop`, run `flutter build windows --release --no-pub
  --dart-define-from-file=../../.env.acceptance.json`.
- Opened the resulting native executable. Fresh screenshot and accessibility
  inspection confirmed the sign-in screen, email/password controls, Google entry,
  MFA notice and synthetic-development label. No credentials were entered and no
  authentication action was automated.

The current release output is now the configured development build. Earlier
unconfigured startup results remain historical evidence for their dated builds;
they do not describe the current artifact's backend configuration.

## Manual handoff

Create a synthetic test user in this development project's Supabase Authentication
area, then sign in in the opened Jentra window. Keep the password and MFA codes
out of chat. Do not disable MFA or use a service-role credential in the client.
The Computer Use skill requires the user to handle authentication/MFA screens.

Once sign-in is complete, continue with the existing first-workspace onboarding,
complete the prompted MFA step manually, and configure governed synthetic business
prerequisites. Source inspection confirms those existing onboarding/MFA routes;
their authenticated runtime behavior is not yet verified.

No shared database fixtures, accounts, business records or application source were
changed in this preflight. Existing uncommitted AC-305–AC-308 work is preserved;
no staging, commit or push was performed. Native restart recovery and concurrent
posting tests remain pending after this authentication/setup gate.
