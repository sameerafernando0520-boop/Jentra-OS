# Process owner-review coverage — October 10, 2026

This is a read-only mapping of five complete criterion statements to current source. It executes no tests or analysis and records no acceptance. A fresh focused exact-source run can support a separate calculation decision for AC-551, AC-552 and AC-553. AC-555 and AC-558 remain conservative pending bounds/quality review. Installed adapters, source permissions, native behavior and load are independent.

## AC-551

AC-551: Explicit cohort and recorded cutoff (FR-551, FR-552, FR-553) Given events at window start/end and events recorded before/after cutoff When the validated snapshot is calculated Then only the half-open entered cohort recorded by cutoff is included.

After a fresh exact-source passing focused domain run, the complete calculation statement is directly evidenced.

Half-open entered_at selection; recorded cutoff inclusion/exclusion; completion at/asOf vs future/open; frozen canonical projected bytes.

Remaining: Fresh run result bound to exact domain source/test hashes, then explicit owner decision.

- [AC-551 EC-551 half-open entry and inclusive recorded/completion cutoffs](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:178>)
- [AC-551 EC-552 canonical captured bytes freeze source values and selection](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:550>)

## AC-552

AC-552: Exact nearest-rank duration (FR-554, NFR-551) Given completed durations of 0, 1, 2, 3 and 10 microseconds When P50 and P90 are calculated with every input permutation Then the exact values are 2 and 10 microseconds with no rounding drift.

After a fresh exact-source passing focused domain run, the complete calculation statement is directly evidenced.

All 120 permutations of 0/1/2/3/10 microseconds require P50=2, P90=10 and unchanged canonical bytes; even/single/tied samples and values beyond safe JSON integers preserve discrete exactness.

Remaining: Fresh run result bound to exact domain source/test hashes, then explicit owner decision.

- [AC-552 EC-554 exact P50/P90 over every permutation including zero](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:199>)
- [AC-552 nearest rank is discrete for even, single and tied populations](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:224>)
- [AC-552 durations larger than safe JSON integers serialize exactly as strings](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:507>)

## AC-553

AC-553: Open, invalid and empty are distinct (FR-555, FR-556) Given missing/future completions, malformed durations, and default-zero work fields When summaries are calculated for nonempty and empty completed samples Then counts conserve population and unsupported/empty measures are unavailable, while a real zero remains available.

After a fresh exact-source passing focused domain run, the complete calculation statement is directly evidenced.

Empty/null percentiles, valid zero, missing/future completions, negative/invalid timing, count conservation and uncertified measures are directly asserted. Future-open completion is in the shared AC-551 fixture.

Remaining: Fresh run result bound to exact domain source/test hashes, then explicit owner decision.

- [AC-551 EC-551 half-open entry and inclusive recorded/completion cutoffs](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:178>)
- [AC-553 EC-554 empty, valid zero and open-only samples remain distinct](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:255>)
- [AC-553 EC-555 invalid duration/minutes conserve counts and mark partial](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:271>)
- [AC-553 default-zero and positive minutes cannot certify other measures](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:294>)

## AC-555

AC-555: Bounded complete snapshot (FR-552, NFR-552) Given page truncation, duplicate identities and source/group/time/output boundaries When a snapshot is submitted Then incomplete or over-limit input fails without a partial result and allowed boundary input succeeds.

Keep full criterion open until group/output wording is explicitly discharged; a passing current focused run covers the recorded row/time/completeness cases.

Forged/over-limit counts, duplicate identities, incomplete/mismatched/unsorted manifests, 10,000-row success/10,001 rejection, and 366-day success/+1 microsecond rejection.

Remaining: The criterion names group and output boundaries. This domain definition has a single fixed group and bounded output; this focused domain fixture does not drive 100/101 group or exact 8 MiB/8 MiB+1 output cases. The separate platform hasher tests reject oversized bytes, but that is not a domain output-boundary test. Provide a reviewed applicability proof or meaningful additional evidence before full acceptance.

- [AC-555 forged row/identity counts do not evade input limits](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:133>)
- [AC-555 EC-553 duplicate event IDs fail; shared document IDs remain distinct](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:398>)
- [AC-555 incomplete, mismatched and unsorted manifests fail closed](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:410>)
- [AC-555 EC-557 10000 rows succeed and 10001 fail without partial totals](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:476>)
- [AC-555 EC-557 366-day cohort succeeds; one microsecond excess fails](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:494>)

## AC-558

AC-558: Source and quality contract (FR-551, FR-552, NFR-554) Given malformed scope/UTC/manifest data and a verified immutable definition When domain verification and analysis run Then invalid input is rejected deterministically and all required cases pass without analysis findings.

The malformed source/definition portion is directly mapped; whole-criterion readiness requires fresh clean analysis and resolution of the all-required-cases wording.

Malformed container/scope/UUIDs/UTC/calendar and cutoff order, strict minute parser, unsupported source revisions, private/unknown fields, canonical definition code/version, wrong/malformed digests, verifier error redaction and immutable results.

Remaining: Fresh exact-source domain verification and clean scoped analysis; independently verify the immutable definition; resolve AC-555 group/output applicability before claiming all required cases. Injected ExpectedBytesHasher checks exact canonical bytes rather than computing real SHA-256; real digest transport is separately tested in the platform fixture.

- [AC-558 EC-558 verifier failures preserve domain errors and redact unknown errors](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:102>)
- [AC-558 malformed container shapes and foreign selection fail safely](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:147>)
- [AC-558 EC-557 strict UTC rejects normalized invalid calendar values](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:318>)
- [AC-558 manifest instants and generation time require ordered UTC](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:341>)
- [AC-558 exact minute parser rejects numeric coercion and silent rounding](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:363>)
- [AC-558 EC-556 foreign tenant/entity/branch and null entity are denied](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:426>)
- [AC-558 null branch permits authorized mixed-branch observations only within entity](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:444>)
- [AC-558 unsupported source revision or document kind fails before calculation](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:463>)
- [AC-558 source projection rejects private/unknown fields and missing required fields](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:535>)
- [AC-558 manifest/hash verification rejects wrong or malformed digest](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:587>)
- [AC-558 verified observations/manifests/results are immutable](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:609>)
- [AC-558 identifiers canonicalize case and reject malformed UUIDs safely](<C:/Users/sheha/Desktop/Jentra OS/packages/jentra_domain/test/analytics/process_metrics_test.dart:629>)

Exact source/test hashes are in [the JSON mapping](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/wave5/process-owner-review-coverage-20261010.json>). All owner acceptance flags remain false.
