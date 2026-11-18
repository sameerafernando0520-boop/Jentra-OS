# Jentra OS subscription checkout rollout

The checkout migrations build on the organization control and identity
migrations. Apply and verify them together against an isolated staging project.
Reconcile the staging migration history before applying any pending migration.
Both checkout flags default to false.

Use a Supabase project whose reference differs from production. A development
label in the client configuration does not establish isolation. The
disconnected preview can open locally without Supabase settings.

## Stage checkout

1. Deploy the browser build with deep links routed to `index.html`. Use the
   staging project's publishable Supabase configuration for web and Windows.
2. Deploy `org-identity` and `subscription-handover` with the matching database
   migrations. Configure the verified sender and the durable handover scheduler
   using the [credential handover guide](subscription-handover.md).
   Use a controlled mailbox to test delivery and account recovery.
3. Assign the existing `organization_manage` capability and MFA to a designated
   staging operator. In Platform Control, save the approved LKR bank
   instructions. Publish the approved price, duration, features, HTTPS link
   to a browser-playable video file, and transcript for each plan. Published
   information affects new quotes.
4. Review every staging trial account that still needs direct workspace
   creation. Add only those Auth user IDs to
   `billing.subscription_trial_allowlist`. Enable checkout and enforcement
   together using the privileged database connection:

   ```sql
   update billing.subscription_checkout_settings
   set enabled = true, enforce_checkout = true
   where singleton;
   ```

## Rehearse and cut over

- Use synthetic bank references and record the observed LKR amount and timestamp
  in Platform Control. Verify matching, late and mismatched transfers, a free
  order, and a renewal before and after expiry. Exercise a duplicate approval in
  two operator sessions.
- Confirm the signup mailbox receives the generated username and temporary
  password. Test forced rotation, direct API denial, expiry, reissue, and
  recovery. Verify that the operator panel reports progress without credential
  values.
- Install the development admin build alongside the customer app on a clean
  Windows x64 machine. Verify browser and native MFA, denied customer access,
  state refresh, upgrade and rollback. Use signed artifacts and the approved
  sender, bank account and plan content for production.

For storefront maintenance, set `enabled = false` and keep
`enforce_checkout = true`. In-flight confirmations and handover jobs can still
be worked from the operator side. Existing order snapshots remain the basis for
payment reconciliation. Keep the previous browser bundle and signed Windows
installer available during cutover.
