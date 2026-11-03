# Jentra Sales

Separate Flutter sales companion, version 0.1.0+1 Development. Uses the existing
Jentra artwork, Manrope and exact decimal domain primitives. Phone navigation is
Today, Customers, Orders and More. Tablet uses a compact rail; wide browsers use
an expanded sidebar and customer list/detail panels.

The initial release is an **interactive preview**, selected explicitly from the
sign-in screen. The sample catalogue, customers, orders and deliveries are
synthetic. Search, customer details, order entry, fractional quantities, discount
requests, review, protected local drafts, draft removal, visit planning and
session-only visit notes work in this preview. Light/dark appearance is available.
Drafts are separate from all Employee and desktop stores, expire after 24 hours
and are never submitted automatically. Browser storage needs HTTPS, IndexedDB,
Web Crypto and Web Locks. A competing tab cannot overwrite the active store.

Company sign-in uses only public Supabase client configuration and memory-only
password sessions. With the default candidate flag disabled, successful
credential verification clears the session and shows the pending company
rollout state. No broad CRM/customer/commerce API is used as a fallback. Enable the scoped
portfolio backend only after legacy-path access denial and governed commercial
commands have been verified under the approved mobile blueprint.

Not active in the default release: live customer portfolios, authoritative quotation/
order preview/submission, governed server prices, independent company discount
approval, verified customer email responses, quantity-bound delivery responses,
durable inbox, Sinhala/Tamil translations, iOS delivery, or S2 collections/returns.
Email, push, database migrations and stock/accounting posting are not activated.

The 31 October backend candidate adds dated portfolios with legacy-path denial,
governed order/discount requests, independent desktop company review and canonical
draft integration. Matching protected review/submission/recovery behavior is
available behind `FIELD_SALES_CANDIDATE_ENABLED=true` (default false). It uses only
the new scoped RPCs. This is candidate source; no migration installation, live
portfolio acceptance, sender activation or deployment is claimed. See the
[candidate contract and separate gates](../../docs/development/field-sales-governance-candidate-20261031.md).

The 2 November [order email-confirmation candidate](../../docs/development/field-order-email-confirmation-candidate-20261102.md)
prepares an explicit recipient link/code/review/response surface. It additionally
requires `FIELD_SALES_EMAIL_CONFIRMATION_ENABLED=true` (default false). Contact
authority, transport and receipt RPCs are candidate-only. The subsequent
[company workspace candidate](../../docs/development/field-company-confirmation-candidate-20261102.md)
prepares staff contact/issuance and protected recovery in the separate desktop
app. The [November 3 continuation](../../docs/development/field-sales-rollout-candidate-20261103.md)
adds a default-disabled organization-scoped Resend worker, explicit company order
progression and a separate posted-delivery quantity response flow. Delivery also
requires `FIELD_SALES_DELIVERY_CONFIRMATION_ENABLED=true` (default false).
The separately approved six-candidate full-schema hosted rehearsal passed and
rolled back completely. Sender domain/mailbox, installation, deployment,
genuine sessions/MFA, device checks and company acceptance remain separate gates.

From the workspace root, resolve the existing workspace and then:

```powershell
cd apps/jentra_sales
flutter test --no-pub --concurrency=1
flutter run -d chrome
```

Release tooling and Firebase policy are in `tools/sales-release` and
`tools/sales-web`. The Android development identity is `com.jentra.sales.dev`,
with a local development signature. Store signing and physical-device/company
acceptance remain separate release work.
