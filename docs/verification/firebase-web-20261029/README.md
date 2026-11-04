# Firebase web release — 29 October 2026

**Published:** https://jentra-os-desktop.web.app

Client **0.3.1+2303 Development**, Firebase project `jentra-os`, separate Hosting
site `jentra-os-desktop`, finalized Firebase version `96336e1a1ad6619c`.
The existing employee site/configuration were preserved. Supabase remains the
account and business-data backend in project `xpdoufauvrbdmxgngetv`.

## Changes

Password and confirmation fields now have independent, accessible eye buttons.
Backgrounding hides revealed passwords. Switching account mode hides and clears
the inputs. New-account form validation requires at least 12 Unicode code
points, letters, decimal digits and punctuation/symbols. Unicode letters are
accepted; whitespace alone does not satisfy the symbol requirement. Existing
password sign-in is unchanged.

Firebase Hosting uses an explicit desktop target, same-origin executable assets,
the exact Supabase network origin, no-store, nosniff, frame denial, no-referrer,
and explicit WASM MIME headers. Static/private missing files remain 404. Only
reviewed public assets were staged; administrator keys and environment files
were neither opened nor shipped. The complete matching artifact is available
in `dist/Jentra-OS-Web-0.3.1-2303-Development` with checksums and instructions.

## Observed verification

- **39** focused authentication/widget tests passed, including the four new
  visibility, backgrounding, complexity and legacy sign-in regressions.
- Static analysis of the modified auth source/tests found no issues.
- The release web build compiled successfully from a frozen source snapshot.
- Preview and live each served **58** exact staged files: every size and
  SHA-256 matched. WASM, CSP, cache policy, five missing/private-file 404 cases
  and SPA deep-link behavior passed.
- Fresh Chrome contexts rendered the actual sign-in screen, exercised both eye
  controls and entered synthetic values using real keyboard events. A valid
  email survived focus changes, and a password lacking numbers was rejected
  before any backend write. The signup screen was checked at 676 by 668.
  Both runs had zero console/runtime errors, failed requests or backend writes.
- The exact finalized preview version was promoted using
  `jentra-os-desktop@96336e1a1ad6619c`, then reverified on the stable live URL.

The first preview automation attempt selected both Flutter's visible error and
its accessibility announcement, so it failed a selector uniqueness check. The
selector was scoped to the rendered field error. Visual inspection then showed
that programmatic email filling had not reached Flutter's editing controller;
the final check uses keyboard input and explicitly verifies retained email.
Earlier diagnostics were retained; the linked final reports contain the stronger
passing checks. No application validation assertion was removed.

See [verification.json](verification.json), [preview-verification.json](preview-verification.json),
[live-verification.json](live-verification.json), and the sign-in/signup PNGs.
Source SHA-256:
`bdde547047e57fc1241e33279692577fe77f543b4cebc284d5d6a7fb7945d9bd`.
Public artifact tree SHA-256:
`82135c2c1d6aab25c5fa35997501aa86f897be23c3af6a1dca939133be0e0f23`.

## Scope and remaining gates

This is public HTTPS hosting of a **Development client**. No real account was
registered or signed in by the verifier; no confirmation email was sent. The
authoritative Supabase password-strength settings and Google/email callback
acceptance remain separate hosted Auth checks. The new password rule is form
validation; it is not a claim that direct Auth API enforcement was changed.

No migrations were installed, senders activated, company records deleted,
Firebase Auth domains changed, or source committed/pushed. The employee push
candidate remains SHA-256
`d0a92d80c7baa2e0012230716a2237feff31a4d0fc90e5da80f5d18c8f9a1d31`.
Other company-launch gates remain in the
[feature completeness record](../../user-guide/feature-completeness.md).

Use the [Firebase runbook](../../../tools/desktop-web/README.md) for exact staging,
preview, promotion and recovery commands. The initial live site had no previous
application release. Keep the current version identity before future promotion;
frontend rollback does not roll back schema or pending browser data. The original
Windows installer remains build 2302; this task updated and hosted the web client.
