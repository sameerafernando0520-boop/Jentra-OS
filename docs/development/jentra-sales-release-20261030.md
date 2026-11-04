# Jentra Sales initial release — 30 October 2026

Owner request: build the separate Jentra Sales app, provide proper phone UI with
particular attention to desktop browsers/tablets, create an APK and publish web
through the existing Firebase project. The owner subsequently invoked Supabase,
Engineering Advanced Skills, Marketing Skills, Deep Work, UXCritique and
DesignSystem to continue the same work.

## Implemented client scope

`apps/jentra_sales` is a separate Flutter workspace app. Phone uses bottom
navigation, tablet a captioned compact rail, and wide browsers an expanded
sidebar with customer list/detail composition. It reuses original Jentra
artwork, bundled fonts, semantic themes and exact decimal domain primitives.
Its implemented design rules are documented in the app's `DESIGN.md`.

The initial interactive preview includes Today, customers/search/detail,
catalogue/category search, new-order lines and exact fractional quantities,
customer reference/requested delivery date, reasoned discount requests,
review/subtotal, protected local draft save/reopen/remove, visits and
session-only outcomes, and independent customer/company/delivery state views.
Dirty editor dismissal requires a discard decision. Customer search cannot
leave the detail action on a filtered-out customer.

Preview fixtures are synthetic, selected explicitly and never used as an
authenticated live workspace. Sample prices are not governed company prices,
sample stock is advisory, and tax/final totals remain unavailable until online
authoritative review. A discount request does not reduce an approved price.
No order, approval, customer acceptance, stock, invoice or payment is posted.

Local drafts use Android secure storage or browser-origin AES-GCM with a
nonextractable key in IndexedDB. Web Locks prevent competing tab overwrites.
Draft schema, quantity precision, caps, immutable command identity and 24-hour
expiry are checked. Failed storage never acknowledges a save. This is browser
origin protection, not an Android keystore guarantee in the browser. Incomplete
unsaved forms do not have process-death recovery. Visits are session-only.

## Backend boundary and observation

Only public client configuration for the existing Supabase project is compiled.
Password credential verification uses an isolated memory-only client and clears
its session. The company rollout notice does not imply portfolio authorization.
No broad CRM, commerce or table API is used as a fallback.

The read-only October 30 public probe observed email Auth enabled (HTTP 200).
Anonymous OpenAPI discovery returned HTTP 401. This does not prove that
authenticated field-sales APIs are absent or installed, nor does it prove
legacy-path isolation. No project-management SQL tools were exposed in this chat.
The approved blueprint requires that server boundary before real field access.

Live portfolios, governed server price/tax/credit preview, canonical order and
quotation commands, independent company discount decisions, verified email
acceptance/delivery quantities, durable inbox and S1 legacy-path denial remain
unimplemented/unverified in this release. No migrations, customer sender,
Employee push worker or production job is installed or activated.

## Validation and packaging

The final reviewed client passes **19 tests**, covering exact arithmetic, draft
TTL/restore/parallel saves/failure behavior, unavailable company access, every
main page at 320/360/768/1024/1440 pixels, 200 percent phone text, dark tablet
layouts, phone/tablet order review/save, dirty editor protection and filtered
customer detail. The final analyzer reports no issues.

The first concurrent SDK jobs and universal APK attempt hit local memory/thread
limits; their diagnostics are preserved. Subsequent jobs are serialized, with
ARM64 APK packaging and two Java active processors. No other project's build or
process is stopped. Dependency versions remain locked; the existing pinned
Cupertino icon asset is included to satisfy shared Cupertino components.

The October 30 build was published and its verification record finalized on
**31 October 2026**. The [release evidence](../verification/jentra-sales-20261030/README.md)
includes the source/public manifests, build/test logs, APK signature and ZIP
identity checks, deployment records and final screenshots.

- Web: https://jentra-os-sales.web.app
- Android ZIP: https://jentra-os-sales.web.app/downloads/Jentra-Sales-0.1.0-1-Development-APK.zip
- Firebase version: `ff9d9bdb19326df5`, promoted from the verified preview.
- APK: 23,079,169 bytes, ARM64; the ZIP contains the identical signed APK.
- All 50 hosted public files match their staged SHA-256 and size. Security
  headers, WASM MIME, five static/private 404 paths and SPA routing pass.
- All 180 compiled source inputs remain unchanged across the build and final
  verification snapshots (`b182017fb028c64deae3b3933950a1a0d5e90e69598673adac6f9d6022dc2ff4`).

Final ordinary Chrome preview checks pass at desktop 1440×1000, tablet 1024×900
and phone 390×844. Full live browser flows pass at the same sizes with HTTP/3
disabled. The latest ordinary Chrome live run passed two of three sizes; desktop
timed out after reload. Startup/reload remains intermittent on this network,
with its exact cause unconfirmed. **Normal-browser live acceptance remains open.**
A preview-only `Alt-Svc: clear` experiment was not honored by Firebase and was
reverted to the original verified version; it was never promoted to live.

Browser automation now synchronizes Flutter input focus and asserts keyboard
values before checking the independent calculated subtotal. DOM-only fill did
not update Flutter's controller. Requests explicitly cancelled by the test's
reload/teardown are recorded separately; other failures remain test failures.
The review/save/reload flow proves the exact 1.125 × LKR 1,250 = LKR 1,406.25
subtotal, protected draft recovery and dirty-editor keep/discard behavior.

Earlier r5 browser evidence is historical for the source before the last UX
edits. The new Sales CI workflow is configured in source; it has not been pushed
or run in GitHub by this task.

## Distribution limits

The APK has the development identity `com.jentra.sales.dev` and a local development
signature. It targets ARM64 Android phones/tablets. It is not a production-signed
store release. English is the current interface; Sinhala/Tamil localization,
iOS, physical-device privacy/accessibility and real-company acceptance remain
open. S2 collections, custody and returns remain separate product work.

Firebase project `jentra-os` has a dedicated `jentra-os-sales` Hosting site.
The existing Employee and desktop sites are preserved. Hosting publishes only
the compiled client and allowlisted development downloads. The source checkout,
existing dirty work, applied migrations, production records and signing material
are preserved; this task does not commit or push them.

See the [independent UX/brand review](jentra-sales-ux-review-20261030.md), the
[app implementation notes](../../apps/jentra_sales/README.md) and the
[Hosting runbook](../../tools/sales-web/README.md).
