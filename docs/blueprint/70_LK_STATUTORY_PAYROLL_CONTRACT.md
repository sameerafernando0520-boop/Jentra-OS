# 70 — Sri Lanka statutory payroll (EPF, ETF, APIT Table 01)

2026-11-20. Candidate contract, part A of the statutory payroll slice.
Candidate: `supabase/candidates/20261120090000_lk_statutory_payroll.sql` (not installed
anywhere). Builds on the payroll engine in
[53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md](53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md).

## Scope
- EPF employee contribution (deduction), EPF employer contribution and ETF employer
  contribution (employer costs), and APIT under Table 01 (deduction, regular monthly
  profits from primary employment).
- Not in scope, and blocked explicitly: other APIT tables (lump sums, arrears,
  terminal benefits, secondary employment, employer-paid tax, foreign employers),
  Table 05 (joiners, leavers, low months after high year-to-date profits),
  nonresidents and EPF/ETF exemptions. Part B adds screens; part C adds the monthly
  EPF C-form, ETF and APIT schedules.

## Rules as approved data
Rates and bands are stored as dated rule sets per legal entity
(`people_payroll.statutory_rule_sets`), not in code.
`api.people_payroll_statutory_propose_lk` proposes the shipped values as **pending**:
- EPF 8% employee and 12% employer;
- ETF 3% employer;
- APIT Table 01 monthly bands: nil up to Rs 150,000, then 6% less 9,000 up to 233,333,
  18% less 37,000 up to 275,000, 24% less 53,500 up to 316,667, 30% less 72,500 up to
  358,333, and 36% less 94,000 above.

They may be proposed for periods from 2025-04-01 to before 2027-04-01. They were checked
on 2026-11-20: the IRD index applies the 2025 tables to later years unless other tables
are specified. Budget 2027 proposals change the bands, so 2027/28 needs a new set. Every
set records its official source URLs.

A set is used only after `api.people_payroll_statutory_decide(..., 'approve')`. That
requires `people.payroll.approve` across the whole entity, MFA (AAL2), and an approver who
is not the proposer. Two approved sets may not cover the same day. Values never change
after insert; the only state changes are pending → approved → retired.

## Calculation
- A company publishes rule versions with basis `statutory` for components coded
  `EPF_EE`, `APIT` (deductions), `EPF_ER` or `ETF_ER` (employer costs), in LKR, with
  amount 0 and no proration. A trigger rejects any other statutory rule. Rounding,
  precision, cap and accounts come from the rule version, so posting, obligations,
  payslips and settlement need no change.
- Each earning component is classified (`component_statutory`) as EPF liable, ETF
  liable and/or APIT regular profit. An unclassified earning blocks a statutory run.
- `people_payroll.freeze` adds a `statutory` object when the employee has a statutory
  rule. It holds the approved set covering the whole period, the employee facts, the
  component classifications and the year-to-date APIT regular profits from posted runs
  (year of assessment from 1 April). The NIC and EPF member number never enter run
  inputs; only `has_nic` and `has_epf_member_number` do.
- `people_payroll.calculate` keeps the original engine as `calculate_core`. Without
  statutory rules it returns the core result unchanged, so existing digests do not
  change. With them, it sums the liable bases from the core earning lines and adds the
  statutory lines:
  - EPF and ETF are `base × percent / 100`.
  - APIT finds the first band whose bound is at least the APIT base, then takes
    `base × rate / 100 − reduction`, never below zero.
  - All arithmetic is exact in micro-units through `people_payroll.round_ratio`.
- Blockers raise `PAYROLL_STATUTORY_BLOCKED` with the reason code in `DETAIL`, in this
  order:
  - `STATUTORY_LKR_REQUIRED`, `STATUTORY_INPUTS_MISSING`,
    `STATUTORY_APPROVED_RULE_SET_REQUIRED`, `STATUTORY_EMPLOYEE_DETAILS_REQUIRED`,
    `STATUTORY_NIC_REQUIRED`;
  - for EPF/ETF: `STATUTORY_COVERAGE_REVIEW_REQUIRED`,
    `STATUTORY_EPF_MEMBER_NUMBER_REQUIRED`;
  - for APIT: `STATUTORY_APIT_OTHER_TABLE_REQUIRED`,
    `STATUTORY_APIT_NONRESIDENT_REVIEW_REQUIRED`,
    `STATUTORY_APIT_PRIMARY_DECLARATION_REQUIRED`, `STATUTORY_APIT_TABLE_05_REQUIRED`,
    `STATUTORY_APIT_MONTHLY_PERIOD_REQUIRED`;
  - then `STATUTORY_EARNINGS_REQUIRED`, `STATUTORY_EARNINGS_UNCLASSIFIED`, and finally
    `STATUTORY_APIT_TABLE_05_REQUIRED` when monthly profits are under the first band but
    year-to-date profits exceed 12 times it.

  Negative net pay keeps `PAYROLL_NEGATIVE_NET`.
- Known limit: a sealed correction's change to the APIT base is not yet added to
  later year-to-date sums.

## Records and access
- `employee_statutory`: NIC (`^([0-9]{9}[VX]|[0-9]{12})$`), EPF member number,
  coverage, APIT case, resident or citizen, primary-employment declaration, and
  joined/left this year. It is versioned and immutable.
  - Writing needs `people.payroll.configure` with MFA, for an employee assigned to the
    branch.
  - Reading the identifiers needs `people.payroll.configure`.
- `employer_registrations`: EPF and ETF employer numbers, versioned. Writing needs
  configure with MFA; reading needs `people.payroll.view`.
- All four tables force RLS and are reachable only through the API functions.

## Verification
- `supabase/candidates/tests/lk_statutory_payroll_test.sql` (run by
  `run-lk-statutory-payroll-test.mjs` in CI, rollback only) covers:
  - every case in `packages/jentra_domain/test/fixtures/lk_statutory_payroll_cases.json`;
  - unchanged results for non-statutory runs;
  - the statutory rule guard;
  - proposal, idempotency, period limits, separate approver, MFA, overlap, retire and
    immutability;
  - tenant isolation, classification, employee details and NIC validation;
  - who may read identifiers, and that identifiers stay out of frozen inputs.
- `packages/jentra_domain/test/payroll_statutory_lk_test.dart` runs the same cases
  against the Dart mirror `calculateLkStatutory` (`jentra_payroll.dart`).

## Part B — desktop screens
- Development builds opt in with `JENTRA_STATUTORY_PAYROLL_CANDIDATE=true`.
  `tools/desktop-release/prepare.mjs` accepts the flag on the development channel only.
  Without it there is no route, no Payroll button and no gateway.
- **People → Payroll → Statutory payroll** (`/people/payroll/statutory`) has four parts:
  - Rates: propose the shipped values, then approve or retire. Approval requires ticking
    "I checked every rate and APIT band against the official sources". The server
    still enforces the separate approver and MFA.
  - Employer EPF and ETF numbers.
  - Earning classification: EPF, ETF and APIT per earning component.
  - Employee statutory details: NIC (validated in the form and on the server), EPF member
    number, coverage, APIT case and declarations.
- The client parses rule versions with basis `statutory`. The client synthetic calculator
  refuses them and points to `calculateLkStatutory`; the server result is
  authoritative.
- A run blocked at preparation shows the plain-language reason for its
  `PAYROLL_STATUTORY_BLOCKED` code (`lkStatutoryBlockerMessage`) instead of a generic
  state error.

## Part C — monthly returns
- Candidate `supabase/candidates/20261120100000_lk_statutory_returns.sql` adds
  `api.people_payroll_statutory_return(month, kind)` for `epf`, `etf` or `apit`.
  - It sums the posted, approved revisions of runs that start in the calendar month.
    Reversed and cancelled runs are left out.
  - It lists each employee with an EPF, ETF or APIT base above zero, with their NIC, EPF
    member number, bases and statutory amounts, plus the employer EPF/ETF numbers and
    the entity TIN.
  - It needs `people.payroll.export` across the whole entity and MFA, because it
    returns identifiers.
- The desktop **Monthly returns** card prepares a return and warns about a missing
  employer number, NIC or member number. **Save CSV** writes UTF-8 with a byte order
  mark, so spreadsheets show Sinhala and Tamil names. The columns follow the official
  forms:
  - EPF C-form: member number, NIC, name, total earnings, 8%, 12% and total;
  - ETF: member number, NIC, name, total earnings, 3%;
  - APIT: NIC, name, regular profits, tax deducted.

  Amounts have two decimals and there is a total row. Cells a spreadsheet could run as
  a formula are prefixed with an apostrophe.
- Not done yet: the exact EPF/ETF e-return upload file layouts and IRD e-filing
  formats. They need their published specifications confirmed first.
