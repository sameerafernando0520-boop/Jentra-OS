# Negative-stock client visual review — 2026-10-04

Independent reviewer `/root/policy_client_final` inspected all sixteen contact
sheets covering the actual 97 task-owned PNGs from the final policy widget run.
The source-bound run completed 20 tests successfully. The controller suite
separately completed 43 tests successfully, including ordered scope/capability
loss and restoration at read, encryption and receipt boundaries.

The matrix covers 1024×720, 1440×900, 1920×1080 and 3840×2160, both light/dark
themes and compact/comfortable density, at 200% text. Each combination contains
loading, read error, inactive empty, active empty, deficit and correction views.
The extra PNG shows the keyboard-opened review dialog with reduced motion.

No policy layout defect was confirmed in this inspection. At the minimum size,
explanatory text wraps and the list retains reachable actions. Scrolled deficit
and correction views display exact quantities, provisional/actual values,
variance, source movement and correction journal references. The next-page
button is visible in those views. Light and dark captures include their actual
Scaffold background. Larger viewports retain the content without horizontal
clipping. The selected keyboard modal keeps its title, reason and Back/Record
actions visible; its fixture verifies tab, space and escape behavior.

Original PNGs inspected beyond the contact sheets:

- `1024x720_light_compact_text200_error.png`
- `1024x720_dark_comfortable_text200_corrections.png`
- `keyboard_1024x720_light_compact_text200_review.png`
- `3840x2160_dark_comfortable_text200_corrections.png`

All originals are under `build/remaining-wave3/negative-policy-final-renders-20261004`.
The [image manifest](policy-visual-image-manifest-20261004.json) records every
PNG and derived contact sheet hash. The [structured review](policy-visual-review-20261004.json)
records the execution capture hash and matching current policy source hashes.
The fixture SHA256 is
`78efb37ac7517a91fdb9a107991e75196a5ea66da3949b916686b22e52120b0a`;
controller fixture SHA256 is
`b4f5dddf2c2961286150498c2c53c3abf28af2e60597854444c14448cf23de6a`.

These are synthetic Flutter widget renders with fake repositories and an
in-memory database. This review inspected all combinations through contact
sheets and selected originals; it does not claim pixel-by-pixel original-size
inspection of every PNG. It does not establish installed or authenticated
native acceptance, accessibility certification, approved-golden acceptance or
owner signoff. No production source, navigation, comparator or golden changed
during this review.

The current full-desktop log completed 1,617 passes and 76 failures. The
[per-case classification](desktop-current-failure-classification-20261004.json)
validates all failure counters: 67 strict pixel golden failures, seven compiler
load failures from the concurrent Wave 4 `ProjectTaskBasis.ownerId` omission,
and two existing 317-pixel payroll correction overflows. It found no other
non-pixel failure. Reduced observed golden counts cannot imply improvement:
several test files never loaded.

Read-only fresh supplier statement and quotation history comparisons retain the
same exact values, labels and visible layout. Their
[representative measurements](golden-representative-review-20261004.json)
corroborate the earlier rounded-edge raster diagnosis. They do not establish
one cause for every golden failure. The warehouse output remains historical
because that test file failed to load in this run. Concurrent Wave 4 service
goldens and capability-based navigation were preserved; no rebaseline or gate
waiver is part of this review.
