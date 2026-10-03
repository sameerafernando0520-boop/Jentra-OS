# Preserved Wave 3 golden causes — 2026-10-03

This extends the approved 2026-10-02 investigation. Approved PNGs, comparators,
existing test harnesses and product navigation are preserved. Measurements are
read-only PIL/numpy observations; existing image outputs are not evidence that a
later source revision was executed.

## Raster probe

The old isolated probe actually completed one test with Flutter 3.44.7. Its
512×512 output contains a grid of identical one-pixel rounded borders translated
through eighth-pixel origins. A new current-SDK package was prepared under
`build/remaining-wave3/golden-cause-20261003/current`, copying the same pubspec and
test without modification. Both test copies hash to
`e5efce74237c8b174d9407bf4a91b5f65338ccc36e52a6f1c3f80a07fae53448`.
The current probe actually completed one test under the coordinator's serialized
Flutter window (`current/current-probe-20261003.log`): Flutter 3.47.5 / Dart 3.13.4,
matching the declared current CI SDK. Both probes passed their rendering test.
Their identical source produces 12,743 different pixels out of 262,144 (4.86%),
with bounding box [7,7,497,501] and maximum channel difference 54. No alpha channel
changes occur. The probe draws only rounded one-pixel borders at eighth-pixel
origins; it contains no fonts, text, navigation or application layout.

The old SDK is Flutter 3.44.7 / Dart 3.12.2. Its engine revision is
`69c8c61792f04cc809dfef0c910414fb9afc06cd`; the current engine revision is
`af7e796e161ae0bb1ff0758c71a7105418bd9ded`. Framework files
`rounded_rectangle_border.dart` and `border_radius.dart` are byte identical across
both SDKs, and the BorderSide source before ShapeBorder is identical. The same
rounded-border paint operation invokes `canvas.drawDRRect` in both. This
controlled comparison establishes an SDK/runtime raster difference for the
rounded-border primitive and rules out fonts and application content as its
cause. It does not establish the provenance of every approved PNG or prove that
every full-screen golden failure has only this cause. The distinct shell source
changes below must still be assessed. Old-SDK passing evidence would be a
secondary diagnosis; current-SDK regression remains the CI verification gate.

## Source and navigation mismatch

Independent inspection of both warehouse PNGs confirms the approved image shows
People, Projects and Service rows. Current output omits these rows and moves
Intelligence upward. The actual warehouse fixture grants only
`core.setup.view`/`core.setup.manage`. Current navigation requires
`people.view` plus `people.employees.view`, `projects.view` and `service.view` to
display those implemented workspaces. The historical September 30 control source
already gated People; current source additionally gates Projects and Service.
Thus approved-to-control and control-to-current differences have distinct source
components. Identical failure names do not establish identical shell output.

Read-only representative measurements reproduce the previous investigation:

| Preserved approved versus existing output | Changed pixels | Observation |
| --- | ---: | --- |
| Warehouse setup, 4320×3000 | 23,918 | 21,445 sidebar pixels and 2,473 body pixels; source navigation plus rounded borders |
| Supplier statement light at 200% | 627 | Rounded outlined-button edges; prior visual inspection found text/date/value/layout unchanged |
| Quotation history light, 1440 | 1,977 | Rounded control/card edges; prior inspection found no content change |

The [dated measurements](golden-cause-20261003.json) contain file hashes and bounds.
The measurement script is
[`analyze.py`](../../../build/remaining-wave3/golden-cause-20261003/analyze.py).
It writes JSON only and never alters image data.

## Meaning of an isolated approved-navigation fixture

A standalone, frozen pre-Wave-4 navigation fixture could measure the approved
Wave 3 viewport composition using the original labels/icons/capabilities. It
would require explicit provenance from the approved baseline and must retain
the existing strict comparator. Such a fixture tests that frozen composition;
it does not prove current product shell navigation, permissions or full-screen
acceptance. Current capability behavior should be verified independently against
current navigation requirements. Adding unauthorized placeholder routes back to
the product or silently changing original fixture capabilities to obtain a match
would lose that distinction.

No such shell fixture was installed or claimed verified here. Renderer probe,
case-by-case visual inspection, current-source golden regression, native visual
acceptance and owner signoff remain separate gates. A blanket tolerance, global
font substitution or baseline regeneration is unsupported by this evidence.

## Full-suite failure boundaries

The actual `desktop-full-20261003.log` completed with 1,372 passes and 90 failures.
The [per-failure classification](full-failure-classification-20261003.json)
identifies 85 golden failures and five other failures: two Wave 3 reservation
expectation failures, two Wave 4 payroll editor overflows, and one Wave 4 service
scroll ambiguity. The 85 image failures include the preserved 81-case Wave 3
control family and four Wave 4 payroll/service golden cases. These counts refer
to that recorded run, not subsequent repaired source. The warehouse test's
final `takeException` observed its golden mismatch (23,918 pixels / 0.18%);
its preceding saved-row assertions had passed. It does not provide evidence
of a separate warehouse save failure.
