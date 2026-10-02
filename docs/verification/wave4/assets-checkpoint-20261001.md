# Fixed assets development checkpoint

2026-10-01 (Asia/Colombo). Active development, not installation approval.

The W4-07 contract is in `59_WAVE4_FIXED_ASSET_DELIVERY_CONTRACT.md`.
Thirteen exact domain tests pass. The schedule engine
preserves separate depreciation and impairment balances, cumulative half-even
allocation, explicit month conventions, prospective revisions and disposal gain/loss.

The eight-table candidate `20260930071000_wave4_fixed_assets.sql` uses the
installed journal and open-period provider. The refreshed suite passes 88 rollback
assertions. SQL SHA-256 is
`D76AB9FEF3720AEA51DE71288DEFB6FDAE8FA93D82FFFB83ECC49566FBBB5BF8`.
The pass includes opening source ownership,
independent digest-bound approval, prospective books, unique period effects,
impairment/revaluation/disposal and original-effect reversals, both-branch transfer
authority including revoked replay/receipt access, direct-table denial, exact
large-rational quotient regression, and late outbox failure restoring books,
effects, cost and document numbering. Explicit zero periods create no zero journals.

Procurement, stock capitalization and equipment links are explicitly unavailable
adapters. No text reference is presented as eligible procurement or stock evidence.
Governed synthetic opening references are uniquely owned and remain consumed after
capitalization reversal. Original journal source identity is the effect UUID;
effect rows retain asset/book/period and original source/component attribution.

Fresh ledger check: 37 migrations, latest `20260929224939`; `assets.register`
remains absent. No persistent database, plan, role, grant or subscription changes
were made. All role/source/account fixtures were in rollback transactions.

The typed gateway passes 20 checks, including twelve actual rollback API
projections across opening/active/impaired/disposed books, effects and proposals.
Opening API amounts are exact decimal strings. Named approval mappings are
scoped to the same tenant/entity. Native forms/register/history/schedules,
encrypted recovery, original-request retry and explicit version comparison now
exist at `/assets`. The final expanded native suite passes 20 checks, also passing
in `C:\jw4-assets-20261001-a`. Its Windows release build passed in 147.6 seconds;
see `assets-install-review-20261001.md` and the JSON source/build manifests.
All focused analyzers are clean. All eight readable preview images
were inspected with bundled Manrope fonts: light/dark, both densities, 1024x720
and 1920x1080, 200% text. Keyboard Enter submission was verified separately.

Installed checks, actual overlapping sessions,
measured load, authenticated native/restart evidence and owner acceptance remain
open. This checkpoint does not close W4-07 or Wave 4.
