# 71 — Sri Lanka tax schedules (VAT, SSCL, WHT)

2026-11-21. Candidate contract. Part A (VAT return workpaper) is in
`supabase/candidates/20261121090000_lk_vat_workpaper.sql`, which is not installed
anywhere. Part B (SSCL) is in `20261121100000_lk_sscl_workpaper.sql` and Part C
(WHT) in `20261121110000_lk_wht_schedule.sql`. Every output is a **non-certified
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

## Part B — SSCL quarterly workpaper
- Candidate `supabase/candidates/20261121100000_lk_sscl_workpaper.sql` (requires part A).
- `finance.lk_sscl_settings` holds dated settings per entity:
  - the rate (2.5% at the 2026-11-21 check);
  - the liable portion of turnover for the entity's activity (for example a
    wholesale or retail portion);
  - whether exports and exempt sales count;
  - the activity and the sources (the SSCL Act No. 25 of 2022 as amended, and
    ird.gov.lk). The 1 July 2026 amendment's thresholds are recorded as reported, to
    be confirmed.

  Settings are proposed pending and approved by a second person with MFA
  (`finance.classifications.approve`). Approved settings may not overlap. Values are
  immutable.
- `api.lk_sscl_return(quarter_start)` covers a calendar quarter (January, April, July
  or October start). It needs `finance.view`, `finance.reports.export` and MFA.
  - Turnover is `taxable_amount × exchange rate` from **every** posted sales invoice
    and return line, including lines without a tax code. Approved VAT lines classify
    them.
  - The pure `finance.lk_sscl_compute` reports turnover by treatment and the turnover
    counted. Standard-rated sales, sales without a tax code and sales outside VAT always
    count. Exports and exempt sales count only if the settings say so.
  - Liable turnover = counted × portion. SSCL due = liable × rate, both rounded to two
    decimals.
- Blockers:
  - `SSCL_SETTINGS_REQUIRED`: no SSCL is computed.
  - `SSCL_VAT_MAPPING_REQUIRED` and `SSCL_VAT_MAPPING_DIRECTION_MISMATCH`: the line is
    not counted.
  - `SSCL_BASE_CURRENCY_LKR_REQUIRED`.
- Desktop: an **SSCL quarterly workpaper** card with the settings list (approve with an
  Act and IRD confirmation, withdraw or retire), the propose form, the quarter workpaper
  and Save SSCL CSV.
- Not yet: per-account portions for mixed-activity entities, and turnover from manual
  journals.

## Part C — WHT monthly schedule and certificates
Withholding can only be posted on manual journal tax lines (supplier bills accept
input, zero and exempt codes). Posting is unchanged.
- `finance.lk_wht_register` links one posted WHT journal line to:
  - a supplier (`crm.parties` of kind supplier or both);
  - an IRD payment type: service fees, rent, interest, dividends, royalties or other;
  - the gross amount paid, and a note.

  `api.lk_wht_register_record` and `api.lk_wht_register_retire` need
  `finance.journals.post` and MFA. One entry per line is active. Values are
  immutable: a correction retires the entry and records a new one. A reversal journal
  is never registered; it reuses the original line's entry with the amounts negated.
- `api.lk_wht_schedule(month)` covers one calendar month by posting date. It needs
  `finance.view`, `finance.reports.export` (supplier TINs) and MFA.
  - It reads the withholding lines of `finance.tax_posted_sources`. WHT deducted is
    the line's verified base-currency tax.
  - The pure `finance.lk_wht_compute` returns totals by payment type, the schedule,
    and certificate data per supplier (each payment, gross and WHT).
  - The result also lists the suppliers that can be chosen and the month's active
    register entries.
- Blockers:
  - `WHT_REGISTER_REQUIRED`: the line is left out. The blocker carries the journal
    and line ids and the taxable base, so the line can be registered from it.
  - `WHT_AMOUNT_MISMATCH`: gross × the code's rate, rounded to two decimals, differs
    from the WHT deducted. The line still counts.
  - `WHT_SUPPLIER_TIN_MISSING` and `WHT_JOURNAL_MISSING`: the line still counts.
  - `WHT_BASE_CURRENCY_LKR_REQUIRED`.
- Rates are the tax codes' own approved rates; nothing is hard-coded.
- Desktop: a **WHT monthly schedule** card with totals, unregistered lines with a
  Register form (supplier, payment type, gross prefilled from the taxable base, note),
  register entries with Retire entry, certificate totals and Save WHT CSV.
- Not yet: printable certificates and WHT on supplier bills.

## Verification
- `supabase/candidates/tests/lk_wht_schedule_test.sql` (run by
  `run-lk-wht-schedule-test.mjs`) covers:
  - a worked month: a Rs 200,000 service fee at 5%, Rs 150,000 rent at 10%, Rs 100,000
    interest with a wrong deduction, an unregistered line and a reversed Rs 20,000
    service fee give WHT of Rs 28,000 on Rs 430,000 gross;
  - every row blocker and the certificate totals;
  - the register rules (idempotent ids, one active entry, reversals, suppliers only,
    MFA, permission, immutability, retirement);
  - the schedule API: month rule, reversal in a later month, access, MFA and tenant
    checks.
- `supabase/candidates/tests/lk_sscl_workpaper_test.sql` (run by
  `run-lk-sscl-workpaper-test.mjs`) covers:
  - a worked quarter: Rs 3.6 million standard-rated after returns plus Rs 2 million
    untaxed gives Rs 140,000 at a full portion. With a 50% portion, exports and exempt
    sales, it gives Rs 88,750;
  - every blocker, the approval rules, the period, access and MFA.
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
