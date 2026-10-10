# Payroll exact-image review — October 10, 2026

The two failures are intentional Wave 4 toolbar content changes: “Linked corrections” appears before Reload. Preserve that feature and its capability gate. Owner visual decisions are absent; both approved PNGs remain unchanged.

HEAD: `1b03ad09af331262534f535762148b1beeaf8fa4`. Measurements use retained r13 images; no new Flutter or native test was run. The fixture is 1440 × 1100 at 200% text.

## payroll_light_200

4,025 pixels differ (0.254104%); bounding box [537, 31, 905, 77]. No dimension or alpha change.

Approved SHA-256: `54f696b9643d007185adb28b2edb68dceac4c72e88ebf3311cc0f2862296a126`

Candidate SHA-256: `2e94307892e5514cb7860277551ed0d42d3bd78cc81df99703c3e91b69e97925`

![Approved payroll](C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/test/goldens/payroll_light_200.png)

![Candidate payroll](C:/Users/sheha/Desktop/Jentra OS/build/w5win9r13/preview/apps/jentra_desktop/test/failures/payroll_light_200_testImage.png)

![Isolated pixel difference](C:/Users/sheha/Desktop/Jentra OS/build/w5win9r13/preview/apps/jentra_desktop/test/failures/payroll_light_200_isolatedDiff.png)

Proposed decision: retain the Linked corrections action and, only after explicit approval of these candidate bytes, update [this one approved PNG](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/test/goldens/payroll_light_200.png>). The unchanged strict comparison must pass afterward.

## payroll_dark_200

4,025 pixels differ (0.254104%); bounding box [537, 31, 905, 77]. No dimension or alpha change.

Approved SHA-256: `45079c92e03a4c6618601d8b612c1ea6ae605089246c219319853e95a73026cb`

Candidate SHA-256: `a79d578157545249abf5586ede31a58e9e9f213dd2b5ed1b00a1ed21a34e644b`

![Approved payroll](C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/test/goldens/payroll_dark_200.png)

![Candidate payroll](C:/Users/sheha/Desktop/Jentra OS/build/w5win9r13/preview/apps/jentra_desktop/test/failures/payroll_dark_200_testImage.png)

![Isolated pixel difference](C:/Users/sheha/Desktop/Jentra OS/build/w5win9r13/preview/apps/jentra_desktop/test/failures/payroll_dark_200_isolatedDiff.png)

Proposed decision: retain the Linked corrections action and, only after explicit approval of these candidate bytes, update [this one approved PNG](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/test/goldens/payroll_dark_200.png>). The unchanged strict comparison must pass afterward.

## Permission and source rationale

- [apps/jentra_desktop/lib/src/features/people/payroll_screen.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/lib/src/features/people/payroll_screen.dart:428>): people.payroll.view gates the navigation action; it opens PayrollCorrectionScreen in a dialog without issuing a correction command.
- [apps/jentra_desktop/lib/src/features/people/payroll_correction_controller.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/lib/src/features/people/payroll_correction_controller.dart:21>): Current operational scope, loaded capabilities, source repositories and people.payroll.view are independently required; encrypted drafts reauthorize through the correction repository.
- [apps/jentra_desktop/lib/src/features/people/payroll_correction_screen.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/lib/src/features/people/payroll_correction_screen.dart:74>): Preparation is a separate capability/action; busy or offline disables it. Missing controller shows an unavailable state.
- [supabase/migrations/20261001110000_wave4_payroll_corrections.sql](<C:/Users/sheha/Desktop/Jentra OS/supabase/migrations/20261001110000_wave4_payroll_corrections.sql:165>): Candidate server correction_access validates named capability/current People access and genuine aal2 for protected write/read flows; this SQL is not installed runtime proof.
- [docs/blueprint/63_WAVE4_PAYROLL_CORRECTIONS_CONTRACT.md](<C:/Users/sheha/Desktop/Jentra OS/docs/blueprint/63_WAVE4_PAYROLL_CORRECTIONS_CONTRACT.md:20>): Prepare/approve/source-view permissions and current entitlement/scope/MFA checks remain distinct.
- [docs/blueprint/53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md](<C:/Users/sheha/Desktop/Jentra OS/docs/blueprint/53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md:96>): Separate payroll command capabilities; live entitlement/scope/capability/MFA revalidation.
- [docs/development/wave4-status.md](<C:/Users/sheha/Desktop/Jentra OS/docs/development/wave4-status.md:10>): October 6 checkpoint already records these same two intentional toolbar comparisons with approved images preserved.
- [apps/jentra_desktop/test/payroll_workspace_test.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/test/payroll_workspace_test.dart:506>): Layout-only fixture uses all payroll capabilities, 1440x1100 and 200% text; it does not tap the dialog, authenticate, or prove native keyboard access.

The view action opens a separately gated workspace. It does not grant preparation, approval, posting or replay authority. Current server SQL is candidate evidence; a toolbar render does not prove dialog loading, installed authorization, genuine MFA or native keyboard use.

Exact measurements, input/source hashes and the pending decisions are in [the JSON record](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/wave5/payroll-visual-review-20261010.json>). Image decisions are independent from runtime approval and requirement acceptance.
