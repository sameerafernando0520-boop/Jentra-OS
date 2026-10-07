"""Audit completed isolated desktop failures without changing approved goldens."""
import argparse
from collections import Counter
import hashlib
import html
import json
from pathlib import Path
import re
from PIL import Image, ImageChops

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

parser = argparse.ArgumentParser()
parser.add_argument("--snapshot", required=True)
parser.add_argument("--log", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
root = Path.cwd()
snapshot = Path(args.snapshot).resolve()
log_path = (root / args.log).resolve()
output = (root / args.output).resolve()
if not output.is_relative_to(root / "docs/verification/remaining-wave3"):
    raise ValueError("Use task-owned output")
if output.exists():
    raise ValueError("Retain previous evidence")
content = log_path.read_text(encoding="utf-8-sig")
progress = list(re.finditer(r"\+(\d+)(?:\s+-(\d+))?\s*:", content))
if not progress or not re.search(r"(Some tests failed|All tests passed)[.!]", content):
    raise ValueError("Completed test log required")
last = progress[-1]
passed, failed = int(last[1]), int(last[2] or 0)
errors = []
pattern = r"^.*?\+(\d+) -(\d+): (.*?\.dart): (.*?) \[E\]\r?$"
previous = 0
for match in re.finditer(pattern, content, re.M):
    chunk = content[previous:match.start()]
    tail = content[match.end():]
    banner = chunk.rfind("══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK")
    block = chunk[banner:] if banner >= 0 else chunk
    goldens = re.findall(r'Golden "([^"]+)": Pixel test\s+failed', block)
    category = "pixel_golden" if goldens else "render_overflow" if "overflowed" in block else "functional_or_load"
    errors.append({"file": match[3], "test": match[4], "failed_counter": int(match[2]),
                   "category": category, "goldens": goldens,
                   "exception_excerpt": block.splitlines()[:16]})
    previous = match.end()
if len(errors) != failed or [row["failed_counter"] for row in errors] != list(range(1, failed + 1)):
    raise ValueError(f"Failure counter mismatch: parsed {len(errors)} expected {failed}")
images = []
for actual in sorted((snapshot / "apps/jentra_desktop/test/failures").glob("*_testImage.png")):
    stem = actual.name.removesuffix("_testImage.png")
    master = actual.with_name(stem + "_masterImage.png")
    approved = root / "apps/jentra_desktop/test/goldens" / (stem + ".png")
    if not master.exists() or not approved.exists():
        images.append({"name": stem, "state": "missing master or approved image"})
        continue
    expected_image = Image.open(master).convert("RGBA")
    actual_image = Image.open(actual).convert("RGBA")
    row = {"name": stem, "actual": str(actual), "master": str(master),
           "approved": str(approved), "actual_sha256": sha(actual),
           "approved_sha256": sha(approved), "master_sha256": sha(master),
           "approved_matches_execution_master": sha(approved) == sha(master),
           "actual_size": list(actual_image.size), "expected_size": list(expected_image.size)}
    if expected_image.size == actual_image.size:
        diff = ImageChops.difference(expected_image, actual_image).convert("RGB")
        changed = sum(pixel != (0, 0, 0) for pixel in diff.getdata())
        row.update({"different_pixels": changed, "pixel_percent": 100 * changed / (diff.width * diff.height),
                    "difference_bbox": diff.getbbox()})
    images.append(row)
report = {"observed_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
          "snapshot": str(snapshot), "log": args.log, "log_sha256": sha(log_path),
          "passed": passed, "failed": failed, "failures": errors,
          "categories": dict(Counter(row["category"] for row in errors)), "images": images,
          "approved_images_unchanged_since_execution": all(row.get("approved_matches_execution_master", False) for row in images),
          "boundary": "Actual completed synthetic widget suite and unchanged approved-image comparisons. Pixel sparsity does not establish cause or visual acceptance. No approved PNG/comparator/tolerance changed; not authenticated native/load/owner signoff."}
output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"output": args.output, "passed": passed, "failed": failed,
                  "categories": report["categories"], "images": len(images),
                  "approved_preserved": report["approved_images_unchanged_since_execution"]}))

