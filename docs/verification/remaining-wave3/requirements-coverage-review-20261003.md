# Current source coverage review — 2026-10-03

At the completed pre-policy desktop execution, the unchanged cumulative 189-path
scope measured 26,359 / 32,388 lines (81.38508%). The locked 25-file pure-domain
scope measured 643 / 677 branches (94.97784%). The raw and exact-declaration
supplement are preserved separately as `requirements-coverage-pre-policy-raw-20261003.json`
and `requirements-coverage-pre-policy-reviewed-20261003.json`. These figures are
recorded execution evidence, not a percentage for subsequently edited sources.

The later current-HEAD source-reuse audit binds `cbdb9f8166034bbb6e6112d68baf149cd1d7be84`
and rejects stale records. Five quotation-related production files now differ
from the pre-policy coverage capture. Concurrent Wave 4 source/test changes also
prevent claims that the older whole-suite or isolated Windows build matches the
entire current checkout. The audit records those differences without assigning
ownership or overwriting concurrent work.

The explicitly approved negative-stock policy requires five planned additional
source paths, making the prepared cumulative list 194 paths while retaining all
189 baseline paths. The planned domain model also extends the pure-domain
branch denominator beyond the locked 25-file report. The additive pure-domain
aggregation requires actual source-matched measurements and retains the 90%
threshold. Neither prepared scope nor source presence is measurement; final
coverage must include all real added paths and reject stale executable records.

The remaining paragraphs preserve the earlier review chronology and explain
why smaller or partially measured reports could not close the coverage gate.

The cumulative approved-Wave-3 scope contains 189 Dart source paths: 119 prior
paths plus 70 additionally discovered paths from the approved specification
baseline. It retains full shared router/provider/shell/setup sources and excludes
recorded Wave 4/5 modules. The paths are not reduced to reach a threshold.

`prepare-checked-coverage-20261003.mjs` pairs every LCOV input with its actual
source capture and invokes the unchanged reviewed summarizer. Stale records are
rejected. The fresh full platform run added real executable measurements and a
larger denominator; the earlier preliminary 80.14% subset did not satisfy the
gate because edited executable sources were unmeasured. The refreshed platform
and dialog inputs give approximately 73% before final complete desktop coverage.
The final percentage must be regenerated after all source changes and final runs.

The independent `requirements-declaration-diagnostic-20261003.mjs` certifies
only two exact source hashes for `CrmRepository` (nine methods) and
`LeadToCashRepository` (eleven methods). Every method ends in a semicolon;
inner braces represent named arguments and `limit = 50` is a constant default.
They have zero executable lines. The locked classifier incorrectly rejects
these signatures. Its raw false gate remains saved unchanged. The separately
tested exact-hash supplement corrects their declaration and paired-source flags,
preserving all selected paths, hits, lines, branches, denominators and thresholds.
It leaves the gate open while any executable source is unmeasured or below 80%.

`requirements-coverage-gaps-20261003.json` records exact current measured missed
lines and snippets. Before final full desktop, the largest owned apparent holes
are count (352), disposition (331), control screen (245) and landed extension
screen (186). Their existing real workspace suites cover rendering, pickers,
sealed commands, recovery, private read clearing and exact evidence; the full
run must restore their current-source coverage before adding redundant tests.
Shared setup screen/controller and Supabase CRM adapter remain substantive
broader gaps. Test execution remains separate from native/visual acceptance.

The first executed full desktop log has 1,372 passes and 90 failures. Independent
per-case comparison confirms 85 pixel mismatches and five nonpixel failures:
two reservation expectations, two concurrent Wave 4 payroll overflows and one
Wave 4 service keyboard finder failure. The first classifier version mistakenly
borrowed an earlier golden block for two plain Dart errors, whose exception text
follows their `[E]` lines. The corrected source checks following errors first and
matches all 90 classifications with the separate finance review. Neither this
classification nor partial GREEN runs close the final full suite or visual gate.
