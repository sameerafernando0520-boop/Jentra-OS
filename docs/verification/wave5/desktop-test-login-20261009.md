# Separate desktop test login — October 9

Requested by the owner for trying the Windows app. **The account is prepared, not created.** The new Connected package is already signed out. No existing Auth user, password, tenant membership or acceptance store was removed or changed.

Proposed email: `desktop-test-20261009@jentra.invalid`. Create a new confirmed password identity through [this project's Auth Users page](https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/users): **Add user → Create new user**, then enter this label and choose a new strong test password privately. Confirm the new test email without sending mail. A collision requires a new label; do not replace an existing identity. The `.invalid` address cannot receive signup confirmation, so the public signup form alone cannot make this label usable while email confirmation is required.

The admin page currently requires owner sign-in. Connected tools expose SQL/Edge operations but no Auth Admin user-creation operation. Real Auth identity creation cannot be substituted with an inserted `auth.users` row. Browser credential-entry rules require the owner to enter the new password and submit the credential steps; passwords must not be placed in chat, source, build configuration, screenshots or delivery artifacts.

After creating the identity, open **Start Connected.cmd**, enter the proposed email and your privately chosen password, and sign in. It receives no tenant membership, roles, operator grant or Wave 5 entitlement automatically. The existing first-workspace flow or an owner invitation is a separate step. Genuine MFA remains required for privileged work.

This single app-trial identity is separate from the six pending Wave 5 runtime accounts. Their installation/bootstrap, private configuration, hosted workers and acceptance remain subject to the bound runtime review. Google is still disabled in the last public settings read and needs the [private configuration steps](windows-account-google-setup-20261009.md).

“Remove existing login” is awaiting clarification between signing out and permanently deleting a named Supabase identity. No destructive action will be inferred from that phrase. The previous acceptance-owned user and data remain preserved.
