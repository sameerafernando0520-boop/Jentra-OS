# Preserved approved golden investigation — 2026-10-02

The completed shared-checkout desktop run records **1,179 passes and 85 failures**.
The [classified log/image comparison](golden-control-20261002.json) reconciles all
85 failures: 81 preserved HEAD control cases, two concurrent Wave 4 payroll
golden cases, one Wave 4 service keyboard test and one Wave 4 test removed between
discovery and loading. These four additional failures must not be labelled Wave 3
golden failures or a Wave 3 product compilation failure.

The current run reproduces all 81 control cases. **67 of the 83 current/control
failure PNGs match byte-for-byte and pixel-for-pixel.** Sixteen shell-bearing PNGs
now differ from the historical HEAD output. Wide images share 19,404 changed
pixels; narrow images share 4,397. This supersedes the historical 83/83 comparison.
The identical failure names do not establish identical rendering or its cause.

The [approved-image measurements](approved-golden-investigation-20261002.json)
compare every preserved approved image against existing current output. All 83
approved images match their failure-master hashes; none was regenerated. All 83
current outputs differ from their approved images, with matching dimensions.
Raw pixel counts, channel deltas, difference bounds and common color changes are
recorded. Numerical sparsity alone is not a visual acceptance decision.

| Inspected evidence | Confirmed observation | Interpretation and remaining work |
|---|---|---|
| Supplier statement light, 1024×1300, 200% | 627 changed pixels, confined to rounded outlined-button borders/corners. Visible text, dates, values and layout match. | Border raster localization is confirmed. An engine/framework A/B probe is required to establish the producing operation. Changing fonts or dates is unsupported for this case. |
| Quotation history light, 1440×1000 | 1,977 changed pixels; isolated differences follow rounded card/control edges and corners. No visible text-content change. | Localization is confirmed; a blanket tolerance or baseline update would not establish cause. |
| Warehouse setup full shell | Difference image shows changed People/Projects/Services/Analytics/Jentra Control sidebar positions, labels and icons, plus rounded-border differences. | Actual navigation content differs from the approved baseline. Current shell output also differs from historical HEAD. A global font override cannot resolve this content difference. Concurrent Wave 4/5 navigation must be preserved. |
| Historical bank failure PNG | Old output adds a report-date field missing from its old master and shifts later content. The file is dated September 29. | This PNG is not among the 81 control failures. Both bank golden tests pass in the October 2 full run. It is historical evidence and is excluded from the current failure classification. |

Local source inspection found the same nonzero-width `RoundedRectangleBorder`
painting operation in the bundled Flutter 3.44.7 and current Flutter 3.47.5 sources:
`drawDRRect` with the original border color and computed inner/outer radii. Their
engine stamps differ. This narrows the proposed renderer probe; it does not prove
the engine caused the approved-image differences. No SDK test window was taken
from the coordinated full-suite verification.

No approved golden, existing test harness, product source, acceptance data or
executable was changed by this investigation. A deterministic harness correction
requires a demonstrated fixture/rendering cause. A global font substitution,
relaxed image comparator or regenerated baseline is not supported by the current
evidence. Complete per-case inspection, renderer cause, current source-compatible
visual regression and native/owner acceptance remain open under NFR-315/AC-326.

Reproduction tools:
[approved/current pixel analysis](../../../tools/wave3/analyze-approved-golden-differences-20261002.py)
and [completed current/control classification](../../../tools/wave3/compare-final-golden-evidence-20261002.py).
They read existing outputs and write dated JSON only. The source-sensitive
[full desktop log](../../../build/remaining-wave3/desktop-full-20261002.log) supplies
the executed results; the PNG measurements alone do not establish execution date.
