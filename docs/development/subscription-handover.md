# Subscription credential handover

Apply the checkout and handover migrations before deploying the updated
`org-identity` and new `subscription-handover` Edge functions. Keep checkout
disabled until the isolated environment passes the end-to-end checks.

Configure the existing Resend sender and identity code secret for both
purchase verification and organization recovery.

- `JENTRA_IDENTITY_RESEND_API_KEY` and `JENTRA_IDENTITY_MAIL_FROM` identify
  the verified transactional mail sender.
- `JENTRA_IDENTITY_CODE_SECRET` is the existing HMAC secret, at least 32 bytes.
- `JENTRA_SUBSCRIPTION_HANDOVER_KEY` is a separate Base64-encoded key with
  32 cryptographically random bytes. Keep the key available until the current
  generation’s pending retry payloads have been delivered or expired.
- `JENTRA_SUBSCRIPTION_HANDOVER_SECRET` is a separate random scheduler
  secret of 32 to 256 characters. Store the same value in Supabase Vault as
  `jentra_subscription_handover_secret`. Store the full project Edge URL
  ending in `/functions/v1/subscription-handover` as
  `jentra_subscription_handover_url`.

Install the scheduler through the approved environment setup, using the
privileged database owner. This is an environment operation after deployment.

```sql
select cron.schedule(
  'jentra-subscription-handover',
  '* * * * *',
  $job$
    select net.http_post(
      url := endpoint.decrypted_secret,
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'x-jentra-handover-secret', credential.decrypted_secret
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    )
    from vault.decrypted_secrets endpoint
    cross join vault.decrypted_secrets credential
    where endpoint.name = 'jentra_subscription_handover_url'
      and credential.name = 'jentra_subscription_handover_secret';
  $job$
);
```

The scheduler uses Supabase Cron, pg_net, and Vault. Each call claims at most
one due job. Enable the scheduler only for the intended project. Check
`cron.job_run_details` for scheduler failures and the order queue for handover
attempt counts and standardized failure codes. A sent status records Resend’s
acceptance. Verify inbox delivery with a controlled test address.

On retry the worker reuses the generation’s encrypted payload and mail
idempotency key. The ciphertext is deleted on acceptance, a terminal failure,
a successful password change, or expiry. A reissue creates a new generation
and the earlier temporary credential immediately stops granting setup.
The temporary credential expires 24 hours after issuance. Verified password
recovery remains available after expiry. The scheduler can continue processing
already paid orders when new checkout is disabled.

In an isolated project, confirm a verified test buyer can place an order and
receive the expected username after payment. Confirm forced password change
and stale-session denial against the hosted Auth endpoint. Repeat with an
expired credential, simulate a provider timeout, and verify a reissue rotates
the credential without creating a second membership. Keep real customer
addresses and production credentials out of the rehearsal.
