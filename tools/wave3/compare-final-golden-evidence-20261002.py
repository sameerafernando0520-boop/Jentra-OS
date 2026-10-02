"""Compare completed source-sensitive logs and existing PNGs without updating goldens."""
import hashlib
import json
import re
from pathlib import Path
from PIL import Image, ImageChops

root = Path.cwd()
base = root / "docs/verification/remaining-wave3"
current = root / "build/remaining-wave3/desktop-full-20261002.log"
control = root / "build/remaining-wave3/head-control-full-completed-20260930.log"
prior = json.loads((base / "golden-control-final-current-20261001.json").read_text(encoding="utf-8-sig"))


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def failures(p):
    lines = p.read_text(encoding="utf-8-sig").splitlines()
    rows = []
    for i, line in enumerate(lines):
        if "[E]" not in line:
            continue
        match = re.search(r"test/([^:\r\n]+\.dart)(?:: (.+?))? \[E\]", line)
        if not match:
            raise ValueError("Unclassified failure: " + line)
        name = match.group(2) or "loading " + match.group(1)
        segment = "\n".join(lines[max(0, i - 65):i + 15])
        category = ("test-discovery drift" if "loading " in line and "file specified" in segment
                    else "golden" if re.search(r'Golden ["\']', segment)
                    else "non-golden test failure")
        rows.append({"file": match.group(1), "name": name, "category": category})
    return rows


new_failures = failures(current)
old_failures = failures(control)
key = lambda row: row["file"] + ": " + row["name"]
old_keys = set(map(key, old_failures))
new_keys = set(map(key, new_failures))
last = re.findall(r"\+(\d+)(?:\s+~\d+)?\s+-(\d+):", current.read_text(encoding="utf-8-sig"))[-1]
if int(last[1]) != len(new_failures):
    raise ValueError("Failure count does not reconcile to final test summary")

images = []
for item in prior["images"]:
    old = Path(item["control_path"])
    new = root / item["current_path"]
    if not old.exists() or not new.exists():
        raise ValueError("Missing referenced image")
    a, b = Image.open(old).convert("RGBA"), Image.open(new).convert("RGBA")
    row = {"image": item["image"], "control_path": str(old),
           "current_path": str(new.relative_to(root)), "control_sha256": sha(old),
           "current_sha256": sha(new), "size_matches": a.size == b.size}
    if a.size == b.size:
        diff = ImageChops.difference(a, b).convert("RGB")
        row.update({"different_pixels": sum(pixel != (0, 0, 0) for pixel in diff.getdata()),
                    "total_pixels": a.width * a.height})
    images.append(row)

new_only = [r for r in new_failures if key(r) not in old_keys]
result = {"review_date": "2026-10-02", "head": prior["head"],
          "sdk": prior["sdk"], "current_log": str(current.relative_to(root)),
          "control_log": str(control.relative_to(root)), "current_log_sha256": sha(current),
          "control_log_sha256": sha(control), "whole_desktop_passed": int(last[0]),
          "whole_desktop_failed": int(last[1]), "current_failed_cases": len(new_failures),
          "control_failed_cases": len(old_failures), "current_only": new_only,
          "control_only": [r for r in old_failures if key(r) not in new_keys],
          "failure_breakdown": {"preserved_control_golden_cases": len(old_keys & new_keys),
                                "new_wave4_payroll_golden_cases": sum(r["file"] == "payroll_workspace_test.dart" for r in new_only),
                                "new_wave4_service_keyboard_cases": sum(r["file"] == "service_workspace_test.dart" for r in new_only),
                                "concurrent_test_discovery_drift": sum(r["category"] == "test-discovery drift" for r in new_only)},
          "compared_images": len(images),
          "identical_images": sum(r.get("different_pixels") == 0 for r in images),
          "images": images, "failures": new_failures,
          "boundary": "Full shared-checkout test log includes concurrent Wave4 work. Control failures "
                      "and current output comparisons do not prove approved-image acceptance or cause. "
                      "PNG comparisons use existing output and preserve every approved image. "
                      "A deleted Wave4 test between discovery and loading is checkout drift, not a "
                      "Wave3 product compile failure. New Wave4 failures require separate owner review."}
(base / "golden-control-20261002.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: result[k] for k in ["whole_desktop_passed", "whole_desktop_failed", "failure_breakdown", "compared_images", "identical_images", "current_only"]}))
