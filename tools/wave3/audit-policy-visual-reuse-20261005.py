"""Read-only audit of preserved visual evidence; does not execute Flutter or edit PNGs."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image

ROOT = Path.cwd()
BASE = ROOT / "docs/verification/remaining-wave3"


def read(name):
    return json.loads((BASE / name).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def compare(row, field="file", expected="sha256"):
    path = ROOT / row[field].replace("\\", "/")
    actual = sha(path) if path.exists() else None
    return {
        "file": relative(path),
        "recorded_sha256": row[expected].lower(),
        "current_sha256": actual,
        "matches": actual == row[expected].lower(),
    }


review_file = "policy-visual-review-20261004.json"
review = read(review_file)
manifest_file = "policy-visual-image-manifest-20261004.json"
manifest = read(manifest_file)
capture_files = [
    "client-sources-policy-controller-20261004.json",
    "client-sources-policy-widgets-final-20261004.json",
]
captures = []
for name in capture_files:
    capture = read(name)
    comparisons = [compare(row) for row in capture["files"]]
    captures.append({
        "file": relative(BASE / name),
        "sha256": sha(BASE / name),
        "original_observed_at": capture["observed_at"],
        "original_head": capture["head"],
        "captured_file_count": len(comparisons),
        "mismatches": [row for row in comparisons if not row["matches"]],
    })

key_sources = [compare(row) for row in review["current_source_matches"]]
# These dependencies influence the actual fixture or its rendered output. Keep
# the complete-capture drift separate from this explicitly named subset.
widget_capture = read(capture_files[1])
dependency_paths = {
    "apps/jentra_desktop/test/quotation_controller_test.dart",
    "apps/jentra_desktop/test/sales_order_controller_test.dart",
    "apps/jentra_desktop/lib/src/shell/navigation.dart",
    "apps/jentra_desktop/lib/src/features/sales/sales_order_dialogs.dart",
    "apps/jentra_desktop/lib/src/features/operations/operational_read_access.dart",
}
dependencies = [compare(row) for row in widget_capture["files"]
                if row["file"] in dependency_paths
                or row["file"].startswith("packages/jentra_design_system/lib/")]
found_dependencies = {row["file"] for row in dependencies}
missing_dependencies = sorted(dependency_paths - found_dependencies)

images = []
for row in manifest["images"]:
    comparison = compare(row)
    with Image.open(ROOT / row["file"]) as image:
        comparison.update({"decoded_size": list(image.size),
                           "recorded_size": row["size"],
                           "size_matches": list(image.size) == row["size"],
                           "decoded_mode": image.mode})
    images.append(comparison)
contacts = [compare(row) for row in manifest["contact_sheets"]]
states = Counter()
combinations = Counter()
for row in manifest["images"]:
    match = re.fullmatch(
        r"(1024x720|1440x900|1920x1080|3840x2160)_"
        r"(light|dark)_(compact|comfortable)_text200_"
        r"(loading|error|empty|active|deficits|corrections)\.png",
        Path(row["file"]).name,
    )
    if match:
        combinations["_".join(match.groups()[:3])] += 1
        states[match.group(4)] += 1

logs = []
for name, expected in [("policy-controller-20261004.log", 43),
                       ("policy-widgets-final-20261004.log", 20)]:
    path = BASE / name
    content = path.read_text(encoding="utf-8-sig")
    counts = re.findall(r"\+(\d+): All tests passed!", content)
    count = int(counts[-1]) if counts else None
    logs.append({"file": relative(path), "sha256": sha(path),
                 "recorded_pass_count": count,
                 "expected_pass_count": expected, "matches": count == expected,
                 "boundary": "Original Oct4 execution retained; no Oct5 execution claimed."})

approved_source = "approved-golden-investigation-20261002.json"
approved = read(approved_source)
goldens = [compare(row, "approved", "approved_sha256") for row in approved["images"]]

classification_file = "desktop-current-failure-classification-20261004.json"
classification = read(classification_file)
classification_counts = Counter(row["category"] for row in classification["failures"])
classification_log = compare(classification["executed_log"])
report = {
    "observed_at": datetime.now(timezone.utc).isoformat(),
    "review_date": "2026-10-05",
    "reviewer": "/root/client_visual_completion",
    "current_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "original_visual_review": {"file": relative(BASE / review_file),
                               "sha256": sha(BASE / review_file),
                               "observed_at": review["observed_at"]},
    "original_visual_manifest": {"file": relative(BASE / manifest_file),
                                  "sha256": sha(BASE / manifest_file),
                                  "matches_review_record": sha(BASE / manifest_file) == review["image_manifest"]["sha256"]},
    "key_sources": key_sources,
    "render_dependencies": dependencies,
    "missing_render_dependencies": missing_dependencies,
    "whole_captures": captures,
    "original_executed_logs": logs,
    "images": images,
    "contact_sheets": contacts,
    "matrix": {"combinations": dict(sorted(combinations.items())),
               "states": dict(sorted(states.items())),
               "png_count": len(images), "contact_sheet_count": len(contacts),
               "complete": len(combinations) == 16 and set(combinations.values()) == {6}
                           and len(images) == 97 and len(contacts) == 16},
    "approved_wave3_golden_audit": {
        "source": relative(BASE / approved_source), "source_sha256": sha(BASE / approved_source),
        "original_review_date": approved["review_date"], "images": goldens,
        "listed": len(goldens), "matching": sum(row["matches"] for row in goldens),
        "boundary": "Preservation against recorded approved PNG hashes only; no acceptance or comparison waiver."},
    "historical_desktop_failure_classification": {
        "file": relative(BASE / classification_file), "sha256": sha(BASE / classification_file),
        "original_observed_at": classification["observed_at"],
        "executed_log": classification_log,
        "passes": classification["passed"], "failures": classification["failed"],
        "categories": dict(classification_counts),
        "counter_matches": sum(classification_counts.values()) == classification["failed"],
        "boundary": "Oct4 mixed-source execution only; rerun required for compiler fixes and current aggregate status."},
    "boundary": "Read-only Oct5 verification of preserved original evidence and current hashes. Matching named source/render dependencies qualify reuse of the original synthetic policy result only. Whole-capture drift is listed and cannot establish current aggregate acceptance. No Flutter run, approved golden/source/comparator change, installation, authenticated native acceptance, accessibility certification or owner signoff.",
}
output = BASE / "policy-visual-reuse-audit-20261005.json"
output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps({
    "current_head": report["current_head"],
    "key_sources_matching": sum(row["matches"] for row in key_sources),
    "key_sources": len(key_sources),
    "render_dependencies_matching": sum(row["matches"] for row in dependencies),
    "render_dependencies": len(dependencies),
    "missing_render_dependencies": missing_dependencies,
    "whole_capture_mismatches": {row["file"]: len(row["mismatches"]) for row in captures},
    "pngs_matching": sum(row["matches"] for row in images),
    "sheets_matching": sum(row["matches"] for row in contacts),
    "matrix_complete": report["matrix"]["complete"],
    "approved_matching": report["approved_wave3_golden_audit"]["matching"],
    "approved_listed": len(goldens),
    "historical_failure_categories": dict(classification_counts),
}))
