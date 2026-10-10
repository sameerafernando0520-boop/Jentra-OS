"""Read existing evidence and write a dated 65-case raster diagnosis only.

This never invokes Flutter, changes source, or writes a PNG. The recorded r13
run remains historical evidence; current-source drift is reported explicitly.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/verification/wave5/raster-golden-diagnosis-20261010.json"
MARKDOWN = OUTPUT.with_suffix(".md")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))


def binding(path):
    return {"path": str(path), "sha256": sha(ROOT / path)}


def versions(text):
    result = {}
    for name, block in re.findall(
        r"^  ([a-zA-Z0-9_]+):\n(.*?)(?=^  [^ ]|^sdks:|\Z)",
        text, flags=re.M | re.S,
    ):
        match = re.search(r'^    version: "([^"]+)"', block, flags=re.M)
        if match:
            result[name] = match[1]
    return result


def main():
    retained_path = "docs/verification/wave5/continuation-goldens-native-20261009.json"
    comparison_path = "docs/verification/wave5/continuation-goldens-comparison-20261009-r13.json"
    manifest_path = "docs/verification/wave5/windows-test-preview-source-20261009-r13.json"
    review_path = "docs/verification/wave5/complete-app-runtime-review-20261009-r13.json"
    retained = read(retained_path)
    comparison = read(comparison_path)
    manifest = read(manifest_path)
    review = read(review_path)
    actual_cases = {x["stem"]: x for x in comparison["cases"]}
    cases = []
    files = set()
    for item in retained["cases"]:
        if item["classification"] != "localized-border-raster":
            continue
        actual = actual_cases[item["stem"]]
        assert actual["classification"] == item["classification"]
        approved = item["approved"]
        assert sha(ROOT / approved) == item["approvedSha256"]
        renders = []
        for render in actual["renders"]:
            assert sha(ROOT / render["r13Path"]) == render["r13Sha256"]
            assert sha(ROOT / render["r10Path"]) == render["recordedR10Sha256"]
            assert render["r13ByteIdenticalToR10"]
            renders.append({"kind": render["kind"], "path": render["r13Path"],
                            "sha256": render["r13Sha256"]})
        test_file = "apps/jentra_desktop/test/" + item["test"].split("/test/")[1].split(":")[0]
        files.add(test_file)
        earlier_exact = any(x["identicalToControl"] for x in item["earlierControl"])
        assert earlier_exact and item["sameDimensions"] and item["changedAlphaPixels"] == 0
        cases.append({
            "stem": item["stem"], "classification": item["classification"],
            "testFile": test_file, "testName": actual["name"],
            "approved": binding(approved), "renders": renders,
            "dimensions": item["dimensions"], "differentPixels": item["differentPixels"],
            "differentPercent": item["differentPercent"],
            "maximumChannelDelta": item["maximumChannelDelta"],
            "changedAlphaPixels": item["changedAlphaPixels"], "bbox": item["bbox"],
            "exactEarlierControlMatch": earlier_exact,
            "observation": item["visualObservation"],
            "inspectionSource": binding(retained_path),
            "strictComparisonPassed": False, "ownerAccepted": False,
            "proposedCandidate": next(x for x in renders if x["kind"] == "testImage"),
        })
    assert len(cases) == 65 and len(files) == 19
    test_files = []
    for name in sorted(files):
        content = (ROOT / name).read_text(encoding="utf-8")
        test_files.append({**binding(name), "lines": len(content.splitlines()),
                           "imports": re.findall(r"^import '([^']+)'", content, flags=re.M),
                           "explicitFontLoader": "FontLoader(" in content,
                           "setsSurfaceSize": "setSurfaceSize(" in content,
                           "setsViewPixelRatio": "devicePixelRatio" in content})
    source_drift = [{"path": name, "recordedSha256": expected,
                     "currentSha256": sha(ROOT / name) if (ROOT / name).exists() else None}
                    for name, expected in manifest["baseSourceHashes"].items()
                    if not (ROOT / name).exists() or sha(ROOT / name) != expected]
    artifact_drift = [x["path"] for x in review["artifacts"]
                      if not (ROOT / x["path"]).exists() or sha(ROOT / x["path"]) != x["sha256"]]
    assert not artifact_drift, "RUNTIME_BOUND_ARTIFACT_CHANGED"
    sdks = []
    for label, base in [("old", ROOT / "build/remaining-wave3/sdk-3.44.7/flutter"),
                        ("current", Path("C:/src/flutter"))]:
        version = json.loads((base / "bin/cache/flutter.version.json").read_text(encoding="utf-8"))
        paths = ["bin/cache/flutter.version.json", "bin/cache/engine.stamp",
                 "bin/cache/artifacts/engine/windows-x64/flutter_tester.exe",
                 "bin/cache/dart-sdk/bin/dart.exe", "packages/flutter/lib/src/painting/rounded_rectangle_border.dart",
                 "packages/flutter/lib/src/painting/border_radius.dart",
                 "packages/flutter/lib/src/painting/borders.dart",
                 "packages/flutter_tools/lib/src/test/flutter_tester_device.dart", "DEPS"]
        deps = (base / "DEPS").read_text(encoding="utf-8")
        sdks.append({"label": label, "path": str(base), "version": version,
                     "skiaRevision": re.search(r"'skia_revision': '([^']+)'", deps).group(1),
                     "files": [{"relativePath": p, "path": str(base / p),
                                "sha256": sha(base / p)} for p in paths]})
    sdk_files = [{x["relativePath"]: x["sha256"] for x in sdk["files"]} for sdk in sdks]
    for name in ["rounded_rectangle_border.dart", "border_radius.dart"]:
        key = "packages/flutter/lib/src/painting/" + name
        assert sdk_files[0][key] == sdk_files[1][key], "PAINTING_SOURCE_CHANGED"
    old_probe = "build/remaining-wave3/raster-probe-20261002/old/probe.png"
    current_probe = "build/remaining-wave3/golden-cause-20261003/current/probe.png"
    old = np.asarray(Image.open(ROOT / old_probe).convert("RGBA"))
    new = np.asarray(Image.open(ROOT / current_probe).convert("RGBA"))
    delta = np.abs(old.astype(np.int16) - new.astype(np.int16))
    mask = np.any(delta != 0, axis=2)
    ys, xs = np.where(mask)
    old_test = "build/remaining-wave3/raster-probe-20261002/old/test/raster_test.dart"
    current_test = "build/remaining-wave3/golden-cause-20261003/current/test/raster_test.dart"
    assert sha(ROOT / old_test) == sha(ROOT / current_test)
    assert int(mask.sum()) == 12743 and int(delta.max()) == 54
    package_config = read(".dart_tool/package_config.json")
    incompatible = [{"name": x["name"], "languageVersion": x["languageVersion"]}
                    for x in package_config["packages"]
                    if tuple(map(int, x["languageVersion"].split("."))) > (3, 12)]
    r13_lock = ROOT / "build/w5win9r13/preview/pubspec.lock"
    before_versions = versions(r13_lock.read_text(encoding="utf-8"))
    current_versions = versions((ROOT / "pubspec.lock").read_text(encoding="utf-8"))
    lock_delta = [{"package": name, "r13": before_versions.get(name), "current": current_versions.get(name)}
                  for name in sorted(set(before_versions) | set(current_versions))
                  if before_versions.get(name) != current_versions.get(name)]
    font_files = [binding(str(p.relative_to(ROOT)).replace("\\", "/"))
                  for p in sorted((ROOT / "packages/jentra_design_system/assets/fonts").glob("*.ttf"))]
    result = {
        "observedAt": datetime.now(timezone.utc).isoformat(),
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "worktreeStatus": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True).splitlines(),
        "boundary": "Read-only fresh hashes and retained primitive/image measurements. No Flutter job, source/test/comparator/image change, native action, runtime operation or owner acceptance. Existing r13 execution is historical and current lock drift is separate.",
        "summary": {"cases": len(cases), "testFiles": len(test_files),
                    "minimumChangedPercent": min(x["differentPercent"] for x in cases),
                    "maximumChangedPercent": max(x["differentPercent"] for x in cases),
                    "maximumChannelDelta": max(x["maximumChannelDelta"] for x in cases),
                    "dimensionChanges": 0, "alphaChanges": 0,
                    "exactEarlierControlMatches": 65, "r13ByteIdenticalToInspectedR10": 65,
                    "approvedHashDrift": 0, "strictFailuresRemaining": 65, "ownerAccepted": 0},
        "runtimeReviewPreservation": {**binding(review_path), "bundleSha256": review["bundleSha256"],
                                      "artifactCount": len(review["artifacts"]), "artifactHashDrift": artifact_drift},
        "sourceAttribution": {**binding(manifest_path), "selectedInputs": len(manifest["baseSourceHashes"]),
                              "currentDrift": source_drift, "currentSourceMatch": not source_drift,
                              "r13Lock": {"path": str(r13_lock.relative_to(ROOT)).replace("\\", "/"), "sha256": sha(r13_lock)},
                              "currentLock": binding("pubspec.lock"), "lockPackageVersionDelta": lock_delta},
        "evidence": [binding(retained_path), binding(comparison_path),
                     binding("docs/verification/remaining-wave3/golden-cause-20261003.json"),
                     binding("docs/verification/wave5/windows-test-preview-desktopAll-20261009-r13.json"),
                     binding("docs/verification/wave5/windows-test-preview-desktopAll-20261009-r13.log")],
        "toolchains": sdks,
        "primitiveProof": {"executedOn": "2026-10-02/03 (retained logs; not rerun today)",
                           "testCopies": [binding(old_test), binding(current_test)],
                           "sameExactTestBytes": True, "before": binding(old_probe), "after": binding(current_probe),
                           "logs": [binding("build/remaining-wave3/raster-probe-20261002/old/old-probe.log"),
                                    binding("build/remaining-wave3/golden-cause-20261003/current/current-probe-20261003.log")],
                           "differentPixels": int(mask.sum()), "totalPixels": int(mask.size),
                           "differentPercent": float(100 * mask.sum() / mask.size),
                           "maximumChannelDelta": int(delta.max()),
                           "bbox": [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
                           "changedAlphaPixels": int(np.count_nonzero(old[:, :, 3] != new[:, :, 3])),
                           "paintOperation": "RoundedRectangleBorder.paint -> canvas.drawDRRect (rounded_rectangle_border.dart:136)",
                           "roundedBorderAndRadiusSourceByteIdentical": True,
                           "containsTextFontsNavigationOrApplicationLayout": False},
        "environment": {"ci": binding(".github/workflows/ci.yml"), "ciFlutter": "3.47.5",
                        "ciQualityOs": "ubuntu-latest", "r13GoldenOs": "Windows",
                        "testBackend": "flutter_tester software rendering / skia-deterministic-rendering (SDK source default)",
                        "fontAssets": font_files, "testFiles": test_files,
                        "desktopPubspec": binding("apps/jentra_desktop/pubspec.yaml"),
                        "desktopRequiredSdk": "Dart ^3.13.0; Flutter >=3.47.0",
                        "packagesWithLanguageVersionAboveOldDart": incompatible},
        "diagnosis": {
            "confirmed": "SDK/runtime rounded-border raster output differs for identical text-free primitive input and byte-identical border/radius painting source. All 65 inspected screen differences are localized rounded-border segments/corners, with unchanged dimensions and no changed labels, values or icons in isolated diffs; candidates match earlier retained controls.",
            "notEstablished": "The exact engine/Skia change and producing SDK provenance of each approved PNG; no unchanged-current-source complete-screen old/current SDK A/B was executed. Skia DEPS revisions differ, but that alone does not identify the causative commit.",
            "oldFull65Feasibility": "Unsupported unchanged workspace: old Dart 3.12.2 / Flutter 3.44.7 violates desktop pubspec/lock and eight package-config language versions. Lowering constraints, language metadata or dependency versions is a controlled fixture overlay and cannot prove ordinary supported current-app behavior. No such overlay was made.",
            "historicalCiTransition": "At commit 0b2261f (2026-09-16) CI used Flutter 3.44.7 and desktop required Dart ^3.12.2. Commit 7c08ea8 (2026-10-03) updated CI to 3.47.5. Quotation baseline last changed e35a05e (2026-09-09); supplier statement baseline last changed 0b2261f. Git chronology supports the hypothesis but does not prove execution provenance.",
            "risks": [{"risk": "MED", "issue": "65 strict approved baselines differ from supported-SDK raster output; an owner visual decision is still required."},
                      {"risk": "MED", "issue": "Current pubspec.lock differs from r13; fresh current-lock candidate execution is required before current-source strict verification."},
                      {"risk": "MED", "issue": "CI quality tests run on Ubuntu while retained r13 goldens ran on Windows; Windows strict evidence cannot establish Linux strict success."}],
        },
        "proposedResolution": {
            "strategy": "Freeze a candidate using current source/current lock and exact Flutter3.47.5 engine/font hashes; retain the strict comparator; render and compare candidates to these 65 exact reviewed r13 hashes. Present every old/current/diff in the combined 83-case owner packet. After an explicit decision bound to candidate paths/hashes, replace only the individually approved baseline PNGs and rerun strict current-source desktop tests without --update-goldens.",
            "comparatorToleranceChange": False, "fontSubstitution": False, "productLayoutChange": False,
            "approvedImageReplacementExecuted": False, "ownerDecisionRecorded": False,
            "oldSdkRollbackRecommended": False,
            "currentSdkFullSuiteRequired": True,
            "nativeAnd109RequirementAcceptanceSeparate": True,
        },
        "cases": cases,
    }
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    lines = ["# Localized desktop raster diagnosis — 2026-10-10", "",
             "All **65 localized raster cases** remain strict failures pending a concrete owner visual decision. This report reads preserved images and hashes; it changes no approved PNG, product source, comparator or runtime-bound artifact.", "",
             "The controlled text-free rounded-border probe uses identical test bytes under cached Flutter 3.44.7 / Dart 3.12.2 and Flutter 3.47.5 / Dart 3.13.4. Its retained completed logs show one test passed on each SDK. Fresh image measurements reproduce 12,743 / 262,144 changed pixels (4.86%), maximum channel delta 54 and no alpha changes. RoundedRectangleBorder and BorderRadius source files are still byte identical; both invoke `canvas.drawDRRect` at line 136. Engine/tester binary hashes and Skia revisions differ. This establishes an SDK/runtime primitive raster difference; it does not identify the exact engine commit or prove every approved image's producing SDK.", "",
             "Each of the 65 screen candidates is byte identical to its inspected r10 render and earlier retained control. Differences occupy %.4f–%.4f%% of each image, maximum channel delta %d, with unchanged dimensions and alpha. The isolated diffs show rounded card, field, chip and button border segments/corners; no changed labels, values or icons. The 19 originating test files, imports, font-loading/viewport controls, and all exact image paths/hashes are in the machine report." % (result['summary']['minimumChangedPercent'], result['summary']['maximumChangedPercent'], result['summary']['maximumChannelDelta']), "",
             "An ordinary unchanged current-app old-SDK run is infeasible: desktop and lock require Dart 3.13 / Flutter 3.47, while eight package-config entries require Dart language 3.13. Adjusting constraints, package metadata or dependencies would create an explicitly controlled fixture. No such overlay or new Flutter job was made here. The existing primitive proof is sufficient for this diagnosis; supported current-SDK regression remains the verification gate.", "",
             "Fresh source attribution reports %d changed r13 inputs: %s. All other selected source inputs—including these Dart tests and font assets—retain their r13 hashes. The %d exact runtime review artifacts still match bundle `%s`. Preserve the changed owner/current lock and produce fresh candidate tests under that lock; r13 execution is historical." % (len(source_drift), ', '.join(x['path'] for x in source_drift) or 'none', len(review['artifacts']), review['bundleSha256']), "",
             "The reviewed resolution is a strict baseline transition under the supported pinned SDK, following an explicit owner decision for exact candidate hashes. The coordinator prepares the combined 83-case gallery and frozen candidate, runs it with the current lock, verifies candidate renders against the reviewed images, and then requests the visual decision. Only approved case images may subsequently replace baselines. Run strict tests without `--update-goldens` after replacement. Keep native interaction, authenticated acceptance, runtime operations and the 109 requirement owner decisions separate. CI's Ubuntu quality run also needs its own evidence; Windows rendering does not prove Linux strict comparisons.", "",
             "[Machine report](raster-golden-diagnosis-20261010.json) · [Retained primitive cause](../remaining-wave3/golden-cause-20261003.md) · [All-case inspection](continuation-goldens-native-20261009.md) · [r13 byte comparison](continuation-goldens-comparison-20261009-r13.json)", "",
             "| Case | Changed pixels | Changed percent | Candidate SHA-256 |", "| --- | ---: | ---: | --- |"]
    lines.extend("| %s | %d | %.4f%% | `%s` |" % (x['stem'], x['differentPixels'], x['differentPercent'], x['proposedCandidate']['sha256']) for x in cases)
    MARKDOWN.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"json": str(OUTPUT.relative_to(ROOT)), "jsonSha256": sha(OUTPUT),
                      "markdown": str(MARKDOWN.relative_to(ROOT)), "markdownSha256": sha(MARKDOWN),
                      "cases": len(cases), "sourceDrift": source_drift,
                      "runtimeArtifactHashDrift": artifact_drift}, indent=2))


if __name__ == "__main__":
    main()
