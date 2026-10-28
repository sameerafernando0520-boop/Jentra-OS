# HR and desktop correction pass — 22 October 2026

**23 October follow-up:** [Hosted HR metadata review](../hr-completion-20261023/README.md)
confirms management access is restored and records the current People/Auth gates.
It supersedes this document's historical access-unavailable finding; the installed
2201 observations below remain version-specific.

This pass fixes reproduced app errors. It does not certify the entire project as
production ready. The separate [HR capability matrix](hr-capability-matrix.md)
identifies existing repository APIs, missing mobile wiring, missing employee-safe
contracts and the hosted checks that still require project access.

## Corrections

- Payroll and Service no longer trap navigation after access is denied. The same
  exit-guard defect is corrected for Employee and project milestones. Pending
  requests remain encrypted and recoverable; active submissions and failed saves
  of unsent drafts still block leaving.
- Assets, Projects and Service explain a disabled module accurately rather than
  suggesting that selecting another scope will necessarily resolve it.
- Empty landed-value, landed-allocation and dimension registers explain their
  state. Bank and fiscal-period screens give the supported setup path.
- Cash-flow mappings distinguish not loaded, empty and paginated account lists.
  A saved selection retired during refresh no longer causes an invalid dropdown
  value. Draft inputs are retained and posting requires a current active account.
- The inbox labels its bounded action **Mark loaded read**, serializes mutations
  and rejects stale results after refresh, disconnect, disposal or overlapping
  actions. Closing the inbox while a request finishes cannot navigate a dead view.
- Employee mobile notices remain scrollable without hiding navigation at 200%
  text in English, Sinhala and Tamil. Sign-in events and their completion handler
  no longer compete to start duplicate workspace loads or clear a newer load's
  busy/error state.

## Native observations on installed 0.2.0+2201

These are actual Windows observations in the separately approved empty
`jentra-qa-221022` workspace. They are not populated-business acceptance tests.
No real HR, inventory, payroll or finance transaction was submitted.

- Restart restored the signed-in workspace. The profile editor displayed the
  existing saved picture and confirmed MFA for the current session. The account
  icon, menu, profile editor, notification inbox and quick-create dialog opened.
  Enter activated the command palette's selected destination.
- Release navigation contained no Design System entry.
- Business setup, CRM, quotations, sales orders and all five receivables tabs
  opened. Setup forms were inspected and cancelled without saving.
- All ten inventory destinations and eleven finance destinations opened. The
  blank/disabled empty states found there motivated the corrections above.
- All six People routes reached the backend's **People is not enabled for this
  business** state. Payroll could not leave that state in 2201; this is the
  reproduced navigation defect addressed by the next candidate.
- Assets, Projects and Service reached denied module states. Service also could
  not leave its denied state in 2201. Source fixes do not enable these modules.
- Audit work queues and engagement register loaded with no work. Audit planning
  showed empty universe/plans and default settings; metrics showed no engagements
  in the selected period. Audit access, Analytics, notification administration
  and Jentra Control destinations opened. No role, subscription, model request,
  notification subscription or hosted setting was changed.

Current candidate test/build/installation results will be recorded separately in
`verification.json`; the preceding native observations remain version-specific.

## Remaining project gates

The public Auth settings check during this pass still reports Google disabled,
email enabled, signup enabled and email confirmation required. The fresh
management check cannot authenticate. Supabase is installed/enabled as a plugin,
but no Supabase management tool is exposed in this session. Project access must
be restored to verify hosted contracts and prepare any required hosted changes.
No password, token, MFA code, session store or Firebase admin key was read.

People is deliberately disabled by the repository's plan-entitlement seed. Native
HR acceptance therefore remains blocked in this workspace. A new desktop build
does not enable hosted modules. The owner required separate approval for
production changes; this pass does not change plan flags, schemas or functions.

The mobile capability gaps in the matrix, Google consent, real confirmation-link
completion, permitted populated HR workflows, native screen-reader acceptance,
trusted distribution signing and owner acceptance remain separate release gates.
The Android deliverables use the existing development package and signer; they
are not store releases. No commit or push is part of this pass.
