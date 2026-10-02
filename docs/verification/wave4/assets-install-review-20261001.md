# W4-07 governed asset opening and book installation review

Development project: `xpdoufauvrbdmxgngetv`. Prepared 2026-10-01.
Candidate only; specific owner approval is required before installation.

## Exact scope

Install only `supabase/migrations/20260930071000_wave4_fixed_assets.sql`.
SHA-256: `D76AB9FEF3720AEA51DE71288DEFB6FDAE8FA93D82FFFB83ECC49566FBBB5BF8`.
The migration creates eight forced-RLS API-only tables in the `assets` schema,
seven scoped APIs and eight application permission definitions. Existing plans,
application role permissions, subscriptions, finance mappings and acceptance
data receive no grants or entitlement changes. No storage or Edge deployment is
included. No Wave 3 or other Wave 4 candidate is included.

The vertical supports uniquely owned governed synthetic opening evidence,
immutable cost components, independently approved digest-bound capitalization,
straight-line/reducing-balance books with exact half-even schedules, prospective
book revisions, separate impairment reserves, revaluation, disposal and gain/loss,
both-branch transfer authority, atomic journals and original-effect reversal.
Zero schedule charges record a period effect without creating a zero journal.
Capitalization reversal retains original source ownership. Later effects and
closed periods block original reversal. Reposting a reversed book period requires
a new independently approved book revision. All posting uses the installed journal
and period provider. Posting is not a bank payment.

Procurement/stock capitalization and equipment adapters remain unavailable. This
installation would not close those requirements or any acceptance gate. Native
source selectors say that explicitly. Assets remains inaccessible until a plan and
authorized roles are separately configured; this approval does not grant them.

## Verified evidence

- 88 rollback SQL assertions against the refreshed installed provider state;
  transaction ends in `rollback;`. Covers source uniqueness, exact arithmetic,
  scoped authorization and MFA before replay/receipt, independent approval,
  zero-period effects, stale/closed-period rejection, transfer revocation,
  original reversal and late outbox failure restoring all effects and numbering.
- 13 domain, 20 gateway and 20 native checks pass. Twelve gateway regressions use
  actual rollback API projections for opening/active/impaired/disposed books,
  effects and proposals. Opening amounts cross the API as exact decimal strings.
  Named approval mappings are scoped to the same tenant/entity.
- Focused domain, gateway, native and route/provider/navigation analysis is clean.
  Exact encrypted retry survives controller restart. Known confirmations remain
  known if optional reads fail; revoked access clears financial data. Stale forms
  require explicit comparison. A timed-out write stays uncertain with its original
  command identity, body, version, key and timestamp.
- Eight readable previews inspected with bundled Manrope fonts: light/dark,
  comfortable/compact, 1024x720 and 1920x1080, 200% text. Named chooser paging,
  scroll hit targets and keyboard Enter submission passed.
- Isolated source verification and all 20 native tests passed in
  `C:\jw4-assets-20261001-a`. Source manifest:
  `assets-source-hashes-20261001.json`; includes exports, pubspec/lock,
  scoped recovery, real projection fixture and route/provider bindings.
- Isolated Windows release build passed in 147.6 seconds. Built
  `2026-10-01T07:33:51.3413543Z`; EXE SHA-256
  `EB5DA05AC3099B7543E58AC994D2ACBF68AEA81B7A164C41C2BD940683EBE867`;
  AOT SHA-256
  `D7D86EB20A0B101C83C06B4D52F8515DC0D2AD587D2F2AB04BCA39FD496ACED1`.
  No installation or launch occurred. The first build invocation used a relative
  script path after changing directory; it did not start a build. The recorded
  successful build used the absolute script path and verified current source.

## Installation and remaining gates

After approval, refresh ledger/schema and verify this exact hash. If the `assets`
schema or its definitions appeared concurrently, stop and compare ownership
instead of replacing them. Apply the reviewed migration once. Confirm its ledger
identity and definitions, then run `build_assets_candidate.ps1 -Installed`;
that builder excludes candidate DDL and rolls back every fixture.

Rollback fixtures, previews and isolated tests/builds do not establish actual
overlapping-session contention, measured p95 load, authenticated native/MFA
acceptance, Windows Credential Manager process restart or owner signoff.
The separate synthetic tenant/bootstrap and plan/role authorization remain open.
Preserve the acceptance lab, all local stores and running binaries. If an installed
defect is found, use a reviewed additive fix; do not drop a schema containing data.
Wave 4 is not complete.
