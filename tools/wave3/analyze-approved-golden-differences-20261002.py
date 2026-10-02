"""Measure preserved approved PNGs against existing failure output; never edits PNGs."""
from collections import Counter
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops

root = Path.cwd()
base = root / "docs/verification/remaining-wave3"
control_path = base / "golden-control-final-current-20261001.json"
control = json.loads(control_path.read_text(encoding="utf-8-sig"))


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


rows = []
for item in control["images"]:
    actual = root / item["current_path"]
    stem = actual.name.removesuffix("_testImage.png")
    expected = root / "apps/jentra_desktop/test/goldens" / (stem + ".png")
    master = actual.with_name(stem + "_masterImage.png")
    row = {"name": stem, "actual": str(actual.relative_to(root))}
    if not expected.exists() or not actual.exists():
        row["state"] = "missing current or approved image; not compared"
        rows.append(row)
        continue
    row.update({"approved": str(expected.relative_to(root)),
                "approved_sha256": fingerprint(expected),
                "actual_sha256": fingerprint(actual),
                "approved_matches_failure_master":
                    fingerprint(expected) == fingerprint(master) if master.exists() else None})
    a = Image.open(expected).convert("RGBA")
    b = Image.open(actual).convert("RGBA")
    row.update({"approved_size": list(a.size), "actual_size": list(b.size)})
    if a.size != b.size:
        row["state"] = "different dimensions; semantic inspection required"
        rows.append(row)
        continue
    difference = ImageChops.difference(a, b).convert("RGB")
    points = [(i % a.width, i // a.width, old, new)
              for i, (old, new) in enumerate(zip(a.getdata(), b.getdata())) if old != new]
    count = len(points)
    row.update({"state": "identical" if count == 0 else "different; cause requires inspection",
                "different_pixels": count, "total_pixels": a.width * a.height,
                "different_percent": 100 * count / (a.width * a.height),
                "difference_bbox": difference.getbbox(),
                "maximum_channel_delta": max((max(abs(old[c] - new[c]) for c in range(4))
                                               for _, _, old, new in points), default=0),
                "highest_difference_rows": Counter(y for _, y, _, _ in points).most_common(12),
                "highest_difference_columns": Counter(x for x, _, _, _ in points).most_common(12),
                "most_common_color_changes": [
                    {"approved": list(old), "actual": list(new), "pixels": n}
                    for (old, new), n in Counter((old, new) for _, _, old, new in points).most_common(8)]})
    rows.append(row)

notes = {
    "supplier_statement_light_200": {
        "cause_status": "visually confirmed localization; renderer cause unproved",
        "finding": "Inspected approved/current and isolatedDiff: differences occur on outlined-button "
                   "rounded border/corner pixels. Text, values, original date and layout match. "
                   "No evidence supports changing fonts or fixture dates for this case.",
    },
    "bank_reconciliation_light_200": {
        "cause_status": "historical stale failure output; excluded from current 81-case control",
        "finding": "Current/HEAD includes Report as of field 2026-09-29 absent from the approved "
                   "image. Subsequent bank/import/matching content moves about 77 pixels down. "
                   "This cannot be repaired safely by a font or date harness override. The failure "
                   "PNG is dated September29 and is NOT among the current 81-control failing cases; "
                   "the October2 full run passes both bank goldens. It is not a current gate failure.",
        "source": "apps/jentra_desktop/lib/src/features/bank_reconciliation/bank_reconciliation_screen.dart",
    },
    "quotation_history_1440_light": {
        "cause_status": "visually confirmed border/corner localization; renderer cause unproved",
        "finding": "Inspected isolatedDiff: sparse differences are on rounded control/card border "
                   "corners and edges. No text/content difference is visible. Numerical sparsity "
                   "alone does not establish which framework or renderer operation caused them.",
    },
    "warehouse_setup_form": {
        "cause_status": "confirmed source/baseline navigation content mismatch plus border raster differences",
        "finding": "Inspected isolatedDiff: sidebar Projects, Services, Analytics, Jentra Control "
                   "icons/labels and group positions differ from preserved approved image. Other "
                   "differences follow rounded control corners. This retained HEAD mismatch cannot "
                   "be closed by a global font loader or raster tolerance.",
    },
}
for row in rows:
    if row["name"] in notes:
        row["inspected_finding"] = notes[row["name"]]

result = {
    "review_date": "2026-10-02", "baseline_control": str(control_path.relative_to(root)),
    "baseline_control_sha256": fingerprint(control_path),
    "boundary": "Existing failure outputs, not a newly executed golden suite. Measurements compare "
                "each preserved approved image, not only current versus HEAD. Source changes are "
                "separate from raster differences. No approved golden, test harness or product source changed.",
    "images": rows,
    "summary": {"listed_images": len(rows),
                "compared": sum("different_pixels" in r for r in rows),
                "identical": sum(r.get("different_pixels") == 0 for r in rows),
                "different": sum(r.get("different_pixels", 0) > 0 for r in rows),
                "dimensions_changed": sum(r["state"].startswith("different dimensions") for r in rows)},
    "conclusion": "At least two distinct CURRENT failure causes exist: rounded-border raster "
                  "differences and changed shell navigation content. Historical bank PNG is excluded "
                  "from current failure classification. A global font substitution, "
                  "renderer tolerance, baseline regeneration or date override is not supported. "
                  "Complete per-case visual review and a renderer A/B probe remain open.",
}
output = base / "approved-golden-investigation-20261002.json"
output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result["summary"]))
