# Windows account creation and Google setup — October 9

The new Windows source implements account creation and Google browser-return sign-in. Use the latest package linked from the [development status](../../development/wave5-status.md). The older r5 package has no Create account action and its Google button has no Windows return handler.

## Create an account with email

Open the Connected app and choose **Create account**. Enter a real email address, a password and the matching confirmation. Complete the confirmation sent to that address, then return to the app and sign in. No account is created by Preview. The app does not grant a business role or activate Wave 5 providers during signup.

For a development account created administratively, use [Supabase Authentication → Users](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/users), choose **Add user → Create new user**, and enter the new email/password privately. Confirm only the intended development account. This is separate from the six proposed `jentra.invalid` runtime labels, which remain uncreated pending their reviewed setup. No password belongs in chat or a delivery artifact.

## Configure Google privately

The project's [public Auth settings](public-auth-settings-20261009.json) were refreshed on October 9 at 17:31 UTC: **Google disabled**, email enabled, new signup enabled and email confirmation required. This read does not disclose client secrets, existing users or sessions. Google provider configuration cannot be performed through the currently exposed connected SQL tools.

1. In [Google Auth Platform](https://console.cloud.google.com/auth/overview), configure the application and add your testing Google account to its audience while the consent screen is in testing.
2. Create a **Web application** OAuth client. Its authorized redirect URI must be exactly `https://xpdoufauvrbdmxgngetv.supabase.co/auth/v1/callback`. This is the Google-to-Supabase callback.
3. In [Supabase Authentication → Sign In / Providers](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/providers), enable Google and enter the client ID and client secret privately. Leave nonce validation enabled. The desktop contains no Google client secret.
4. In [Supabase Authentication → URL Configuration](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/url-configuration), append `http://127.0.0.1:56327/auth/callback/*` to the existing redirect allowlist. Preserve existing entries and Site URL. This separate return URL brings Supabase's PKCE code to the running Windows app; its last path segment is newly random on every attempt.
5. Open the new Connected app, choose **Continue with Google**, select your test Google account in the browser and return to Jentra OS after it reports success. Keep the app open while signing in. First Google sign-in creates an Auth identity when project signup policy allows it.

These configuration operations are prepared for an owner decision; the agent has not enabled Google, provisioned its secret, changed URLs or created an account. Enabling this provider is project-wide and does not grant tenant membership. It is distinct from the pending 71-migration/synthetic worker review. The owner's request authorizes implementation and preparation, while the earlier explicit requirement still calls for concrete review before secret provisioning.

The Windows callback listens only on IPv4 loopback with an exclusive port, a fresh 256-bit path and exact Host/GET/code checks. It accepts one exchange, rejects unexpected token-bearing/duplicate queries and closes on timeout/denial/launch failure. Its five-minute waiting deadline stops before a valid exchange begins; once exchange starts it waits for the SDK's outcome so a late installed session is not mislabeled cancelled. The exact PKCE token endpoint uses a dedicated abortable transport with a 45-second deadline covering connection/TLS, headers and the bounded response body; redirects are denied. It returns bytes to the SDK only after that request has settled. Ordinary API requests retain the existing client and Wave 3 observation path. Browser disconnection cannot change a successful SDK exchange. No callback codes, access/refresh tokens, passwords or provider error bodies enter diagnostics. Controlled callback and transport tests are separate from real Google sign-in and project allowlist verification.

## First workspace and access

After a successful sign-in without memberships, the existing **Create your first Jentra workspace** screen asks for business name/slug, legal entity/code and branch/code. Its authenticated bootstrap creates an owner membership and a 30-day Starter trial. The shell then requires authenticator enrollment and verification. Starter does not automatically activate Wave 5 module/provider entitlements. To join an existing workspace, its owner must invite the new identity and assign the appropriate scoped access.

An Auth identity, successful Google login, workspace access, enabled providers and completed Wave 5 acceptance are separate states. The [remaining-work record](complete-app-remaining-work-20261009.md) retains the additional install, synthetic runtime, real MFA/export/worker/contention/load and owner gates.

Sources: [Supabase Google configuration](https://supabase.com/docs/guides/auth/social-login/auth-google), [Supabase redirect allowlist](https://supabase.com/docs/guides/auth/redirect-urls). Application signup uses the installed SDK's `auth.signUp`; Google uses its `signInWithOAuth` and `exchangeCodeForSession` with the existing PKCE configuration.
