# 71 — Sri Lanka tax schedules (VAT, SSCL, WHT)

2026-11-21. Candidate contract. Part A (VAT return workpaper) is in
`supabase/candidates/20261121090000_lk_vat_workpaper.sql`, which is not installed
anywhere. Parts B (SSCL) and C (WHT) follow. Every output is a **non-certified
workpaper** that an accountant reviews before filing. It builds on the posted tax
evidence in [38_WAVE3_TAX_SUMMARY_CONTRACT.md](38_WAVE3_TAX_SUMMARY_CONTRACT.md).

## Why treatments are approved data
The rules moved in 2026: an SSCL amendment from 1 July 2026, financial services
VAT at 20.5%, and VAT on non-resident digital services. Secondary sources disagree
on thresholds. So no rate or treatment is hard-coded. Each tax code's return line
is proposed, and it counts only after a second person approves it with MFA, having
confirmed the treatment against IRD guidance. Registration thresholds are the
business's own decision and are not enforced.

## Part A — VAT return workpaper
- `finance.lk_vat_mappings` maps each tax definition to one IRD return line:
  `standard_rated_supply`, `zero_rated_supply`, `exempt_supply`, `input_claimable`,
  `input_not_claimable` or `outside_vat`. `finance.lk_vat_line_valid` rejects lines
  that don't suit the code:
  - standard-rated needs an output code with a positive rate;
  - zero-rated needs a 0% zero or output code;
  - exempt needs an exempt code;
  - input lines need input codes.
- Lifecycle:
  - **Propose** (`api.lk_vat_mapping_propose`): `finance.setup.manage` and MFA.
  - **Approve** (`api.lk_vat_mapping_decide`): `finance.classifications.approve`
    across the whole entity, MFA, and an approver who is not the proposer. Approving
    retires the code's previous approved mapping. At most one mapping per code is
    approved.
  - **Withdraw or retire**: a pending mapping can be withdrawn, and an approved one
    retired.

  Values are immutable and rows cannot be deleted.
- `api.lk_vat_return(from, to_exclusive)` covers one calendar month or quarter by
  posting date. It needs `finance.view`, `finance.reports.export` (the
  schedules carry counterparty TINs) and MFA.
  - It reads `finance.tax_posted_sources`, converts to LKR (`taxable × rate`, rounded
    to the entity scale, plus the verified base-currency tax), and makes returns
    negative.
  - It aggregates through the pure `finance.lk_vat_compute`. The result has line
    totals, output tax (standard-rated), claimable input tax, net payable (negative
    means refundable), output and input schedules, and blockers.
- Blockers, never silently counted:
  - `VAT_TAX_CODE_MISSING`, `VAT_MAPPING_REQUIRED` and `VAT_MAPPING_DIRECTION_MISMATCH`:
    the line is left out of the totals.
  - `VAT_RETURN_BASE_UNVERIFIED` and `VAT_JOURNAL_MISSING`: the line is counted but
    flagged.
  - `VAT_BASE_CURRENCY_LKR_REQUIRED`: no totals at all.
- Desktop: **Finance → Tax review → Sri Lanka VAT, SSCL and WHT** (`/finance/tax/lk`),
  shown only in development builds with `JENTRA_LK_TAX_CANDIDATE=true`. It has a
  mappings card (only suitable lines are offered; approval requires the "checked
  against IRD guidance" confirmation) and a workpaper card (month or quarter, totals,
  blockers, **Save CSV**). The CSV is UTF-8 with a byte order mark. Text that could
  run as a spreadsheet formula is neutralized, and negative amounts stay numeric.

## Verification
- `supabase/candidates/tests/lk_vat_workpaper_test.sql` (run by
  `run-lk-vat-workpaper-test.mjs` in CI, rollback only) covers:
  - a worked month: Rs 1,000,000 at 18% less a Rs 100,000 return gives output tax
    Rs 162,000. An export and an exempt supply land on their own lines. Claimable input
    is Rs 61,200 after returns, so net payable is Rs 100,800;
  - all four row blockers;
  - line validity;
  - the approval rules (proposer, MFA, replacement retires the earlier mapping,
    immutability);
  - the period rule, the access, MFA and tenant checks, and the entity TIN.
- `packages/jentra_domain/test/tax_lk_test.dart` and
  `apps/jentra_desktop/test/lk_tax_schedules_screen_test.dart`.
