"""Read retained r10 approved/current/diff PNGs; write metrics, never images."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/verification/wave5/full-desktop-golden-investigation-20261009-r10.json"
OUTPUT = ROOT / "docs/verification/wave5/continuation-goldens-native-20261009.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    source = json.loads(INPUT.read_text(encoding="utf-8-sig"))
    cases = []
    for index, failure in enumerate(source["failures"], start=1):
        stem = Path(failure["golden"]).stem
        approved = ROOT / failure["approved"]["path"]
        renders = {entry["kind"]: ROOT / entry["path"] for entry in failure["renders"]}
        old = np.asarray(Image.open(approved).convert("RGBA"))
        actual = np.asarray(Image.open(renders["testImage"]).convert("RGBA"))
        same_dimensions = old.shape == actual.shape
        row = {
            "index": index, "stem": stem, "test": failure["name"],
            "golden": failure["golden"], "approved": failure["approved"]["path"],
            "approvedSha256": digest(approved),
            "approvedHashStillMatchesR10": digest(approved) == failure["approved"]["sha256"],
            "approvedMatchesFailureMaster": digest(approved) == digest(renders["masterImage"]),
            "renders": [{"kind": kind, "path": str(path.relative_to(ROOT)).replace("\\", "/"),
                         "sha256": digest(path),
                         "hashStillMatchesR10": digest(path) == next(
                             r["sha256"] for r in failure["renders"] if r["kind"] == kind)}
                        for kind, path in renders.items()],
            "earlierControl": failure["earlierControl"],
            "sameDimensions": same_dimensions,
            "dimensions": [int(old.shape[1]), int(old.shape[0])],
        }
        if same_dimensions:
            delta = np.abs(old.astype(np.int16) - actual.astype(np.int16))
            mask = np.any(delta != 0, axis=2)
            ys, xs = np.where(mask)
            count = int(mask.sum())
            row.update({
                "differentPixels": count,
                "differentPercent": float(100 * count / mask.size),
                "maximumChannelDelta": int(delta.max()),
                "changedAlphaPixels": int(np.count_nonzero(old[:, :, 3] != actual[:, :, 3])),
                "bbox": [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
                "highestDifferenceRows": Counter(ys.tolist()).most_common(8),
                "highestDifferenceColumns": Counter(xs.tolist()).most_common(8),
                "tiles": [
                    {"x": x, "y": y, "differentPixels": int(mask[y:y + 128, x:x + 128].sum())}
                    for y in range(0, mask.shape[0], 128)
                    for x in range(0, mask.shape[1], 128)
                    if mask[y:y + 128, x:x + 128].any()
                ],
            })
            # Full-shell snapshots use a 3x render DPR; small-screen shells use
            # the compact 72px sidebar, large ones the expanded 248px sidebar.
            if stem.startswith(("dashboard_", "setup_", "crm_", "warehouse_setup_", "quick_create_")):
                sidebar = 216 if "1024" in stem or "text200" in stem else 744
                row.update({"sidebarBoundX": sidebar,
                            "sidebarDifferentPixels": int(mask[:, :sidebar].sum()),
                            "bodyDifferentPixels": int(mask[:, sidebar:].sum())})
        cases.append(row)
        print(f"{index:02d} {stem}: {row.get('differentPixels')} px, max {row.get('maximumChannelDelta')}, "
              f"earlier={any(c['identicalToControl'] for c in row['earlierControl'])}")
    # Preserve manual inspection entries on a repeat metrics refresh.
    previous = json.loads(OUTPUT.read_text(encoding="utf-8")) if OUTPUT.exists() else {}
    prior = {case["stem"]: case for case in previous.get("cases", [])}
    for case in cases:
        for key in ("classification", "visualObservation", "visuallyInspected", "causeStatus"):
            if key in prior.get(case["stem"], {}):
                case[key] = prior[case["stem"]][key]
        # Every retained isolatedDiff was visually inspected on October 9.
        # These are investigation labels, not comparator exceptions or approval.
        if case["stem"].startswith("payroll_"):
            case.update({
                "classification": "payroll-content-change",
                "visualObservation": "New Linked corrections toolbar action moves Reload. "
                                     "Changed content is confined to the top toolbar; "
                                     "current payroll source gates the action on people.payroll.view.",
                "causeStatus": "Product/source content change confirmed; separately owned Wave 4 visual decision open.",
                "visuallyInspected": ["isolatedDiff", "payroll-light-master/current", "source"],
            })
        elif case["stem"].startswith(("dashboard_", "setup_", "crm_", "warehouse_setup_", "quick_create_")):
            case.update({
                "classification": "capability-navigation-and-border-raster",
                "visualObservation": "People, Projects, Service and Analytics entries shown in the approved "
                                     "shell are absent in the current capability fixture; Intelligence/Jentra "
                                     "Control moves up. Sparse body border/corner differences remain.",
                "causeStatus": "Navigation content change agrees with current source capability gating; "
                               "fixture/policy and owner visual decisions open. Body raster attribution "
                               "does not accept the complete image.",
                "visuallyInspected": ["isolatedDiff", "representative-master/current", "fixture/source"],
            })
        else:
            assert any(e["identicalToControl"] for e in case["earlierControl"]), case["stem"]
            case.update({
                "classification": "localized-border-raster",
                "visualObservation": "Changed pixels are sparse rounded card/chip/field/button border "
                                     "segments and corners. The isolated difference shows no changed "
                                     "labels, values or icons. Current bytes exactly match a retained "
                                     "earlier control render.",
                "causeStatus": "Pattern agrees with preserved SDK border primitive evidence; exact "
                               "per-screen SDK A/B cause is not proved. Strict comparison and visual "
                               "approval remain open.",
                "visuallyInspected": ["isolatedDiff", "pixel-comparison", "earlier-control-hash"],
            })
    result = {
        "observedAt": datetime.now(timezone.utc).isoformat(), "retainedRun": "r10",
        "input": str(INPUT.relative_to(ROOT)).replace("\\", "/"), "inputSha256": digest(INPUT),
        "boundary": "Fresh read-only hash/pixel measurements of retained r10 renders; not a newly run Flutter suite. "
                    "No approved PNG, comparator, navigation, credentials or acceptance store changed.",
        "summary": {"cases": len(cases), "dimensionChanges": sum(not c["sameDimensions"] for c in cases),
                    "approvedHashDrift": sum(not c["approvedHashStillMatchesR10"] for c in cases),
                    "approvedMasterMismatches": sum(not c["approvedMatchesFailureMaster"] for c in cases),
                    "renderHashDrift": sum(not r["hashStillMatchesR10"] for c in cases for r in c["renders"]),
                    "exactEarlierControlMatches": sum(any(e["identicalToControl"] for e in c["earlierControl"]) for c in cases),
                    "classificationCounts": dict(Counter(c["classification"] for c in cases)),
                    "isolatedDiffsVisuallyInspected": sum("isolatedDiff" in c["visuallyInspected"] for c in cases)},
        "cases": cases, "nativeKeyboard": "unverified", "ownerAcceptance": False,
        "cashSpacingCandidate": {
            "minimumLogicalGap": 16,
            "captureVariants": 12,
            "testStatus": "Awaiting root-agent serialized Flutter verification; formatter passed.",
            "sourceBindings": [
                {"path": path, "sha256": digest(ROOT / path)}
                for path in (
                    "apps/jentra_desktop/lib/src/features/analytics/cash_scenario_screen.dart",
                    "apps/jentra_desktop/lib/src/features/analytics/cash_payment_dates_section.dart",
                    "apps/jentra_desktop/test/wave5_continuation_test.dart",
                )
            ],
            "boundary": "Current edited source, distinct from retained r10 golden renders. "
                        "Source files also include concurrent provider/controller work.",
        },
    }
    if "cashSpacingVerification" in previous:
        result["cashSpacingVerification"] = previous["cashSpacingVerification"]
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["summary"]))


if __name__ == "__main__":
    main()
