"""Summarize completed local checks without upgrading their acceptance scope."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

from pypdf import PdfReader

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read(name):
    return (HERE / name).read_text(encoding="utf-8-sig")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


flutter = []
for name, label in [
    ("desktop-tests.log", "desktop Windows widgets and strict goldens"),
    ("employee-tests-final.log", "employee VM tests"),
    ("domain-tests.log", "domain"),
    ("platform-tests.log", "platform adapters"),
    ("design-system-tests.log", "design system"),
]:
    count = re.findall(r"\+(\d+): All tests passed!", read(name))
    if not count:
        raise RuntimeError(f"No successful terminal result: {name}")
    flutter.append({"suite": label, "passed": int(count[-1]), "log": name})

node = []
for name, label in [
    ("node-verification.log", "Edge handlers, candidate runners and Hosting preparation"),
    ("intelligence-worker-tests.log", "intelligence workers with controlled providers"),
]:
    content = read(name)
    counts = {key: re.findall(rf"(?:ℹ|#)\s*{key}\s+(\d+)", content)
              for key in ["tests", "pass", "fail", "cancelled", "skipped"]}
    if (any(not value for value in counts.values()) or
        counts["tests"][-1] != counts["pass"][-1] or
        any(int(counts[key][-1]) != 0 for key in ["fail", "cancelled", "skipped"])):
        raise RuntimeError(f"Incomplete Node terminal result: {name}")
    node.append({"suite": label, "passed": int(counts["pass"][-1]), "log": name})

assert "No issues found!" in read("workspace-analysis-final.log")
assert "Formatted 867 files (0 changed)" in read("format-check-final.log")
for name in ["assurance-download-deno.log", "assurance-verify-deno.log"]:
    assert "Check file:///" in read(name)

provenance = json.loads(read("employee-release-provenance.log"))
installer_path = ROOT / "build/desktop-release-installer-check-be986767/verification.json"
installer = json.loads(installer_path.read_text(encoding="utf-8-sig"))
for result in [provenance, installer]:
    assert all(item["passed"] for item in result["checks"])
(HERE / "installer-verification-result.json").write_text(
    json.dumps(installer, indent=2) + "\n", encoding="utf-8")

inventory = json.loads((ROOT / "docs/user-guide/feature-inventory.json").read_text())
assert inventory["advertised_destinations"] == inventory["matching_routes"] == 43
assert not inventory["production_certified"]
assert len(PdfReader(ROOT / "build/launch-guide-render/Jentra OS Company Setup and Operating Guide.pdf").pages) == 10

source_paths = [
    ".github/workflows/ci.yml", "README.md", "pubspec.yaml", "pubspec.lock",
    "apps/jentra_desktop/lib/main.dart",
    "apps/jentra_desktop/lib/src/shell/navigation.dart",
    "apps/jentra_desktop/lib/src/router.dart",
    "apps/jentra_desktop/lib/src/features/people/employee_requests_controller.dart",
    "apps/jentra_desktop/test/employee_requests_workspace_test.dart",
    "apps/jentra_employee/lib/src/data/employee_account_actions.dart",
    "apps/jentra_employee/test/employee_document_export_test.dart",
    "apps/jentra_employee/test/employee_app_test.dart",
    "packages/jentra_platform/lib/src/analytics/reviewed_model_gateway.dart",
    "workers/wave5/openai_model_adapter.mjs",
    "supabase/functions/assurance-evidence-download/handler.mjs",
    "supabase/functions/assurance-evidence-verify/handler.mjs",
    "supabase/functions/tests/assurance_evidence_download.test.mjs",
    "supabase/functions/tests/assurance_evidence_verify.test.mjs",
    "supabase/candidates/20261023090000_employee_push.sql",
    "supabase/candidates/20261025090000_employee_self_service.sql",
    "supabase/candidates/20261025100000_employee_cases_documents_notifications.sql",
    "supabase/candidates/20261027100000_employee_hr_event_producers.sql",
    "supabase/candidates/tests/employee_hr_event_producers_test.sql",
    "scripts/employee/build_production_release.ps1",
    "scripts/employee/release_artifact_provenance.ps1",
    "scripts/employee/tests/release_artifact_provenance_test.ps1",
    "docs/development/launch-readiness-20261028.md",
    "docs/development/employee-hr-event-producers-candidate.md",
    "docs/user-guide/README.md", "docs/user-guide/feature-completeness.md",
    "docs/user-guide/feature-inventory.csv", "docs/user-guide/feature-inventory.json",
    "docs/user-guide/Jentra OS Company Setup and Operating Guide.docx",
    "docs/verification/launch-readiness-20261028/build_operating_guide.py",
    "docs/verification/launch-readiness-20261028/verify-function-preservation.mjs",
    "docs/verification/launch-readiness-20261028/company-inventory-readonly.sql",
    "docs/verification/launch-readiness-20261028/write_verification_summary.py",
]
source_hashes = {name: sha(ROOT / name) for name in source_paths}
assert source_hashes["supabase/candidates/20261023090000_employee_push.sql"].upper() == (
    "D0A92D80C7BAA2E0012230716A2237FEFF31A4D0FC90E5DA80F5D18C8F9A1D31")

summary = {
    "kind": "local-launch-readiness-evidence",
    "recordedAtUtc": datetime.now(timezone.utc).isoformat(),
    "baseCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "sourceState": "dirty shared workspace preserved; hashes recorded at publication",
    "productionCertified": False,
    "flutterSuites": flutter, "flutterPassed": sum(x["passed"] for x in flutter),
    "nodeSuites": node, "nodePassed": sum(x["passed"] for x in node),
    "analyzer": "No issues found", "formattedFiles": 867,
    "denoEntrypointsChecked": 2,
    "syntheticInstallerPassed": len(installer["checks"]),
    "syntheticReleaseProvenancePassed": len(provenance["checks"]),
    "inMemoryPostgresqlProbe": json.loads(read("function-preservation-result.json")),
    "workflowYaml": json.loads(read("workflow-yaml-result.json")),
    "advertisedDesktopRoutes": 43, "manualPages": 10,
    "manualVisualReview": "All ten pages inspected during authoring; changed final pages 8-10 reinspected",
    "notPerformed": ["hosted company discovery/deletion", "migration installation", "sender deployment",
                     "full 77-assertion Supabase suite", "hosted workflow for current source",
                     "current production release compilation", "authenticated native acceptance",
                     "actual model usage and delivery", "target-scale load", "company signoff"],
    "companyCleanupBlocker": "Invalid management access token and no exposed Supabase SQL tools",
    "publicationSourceHashes": source_hashes,
    "evidenceHashes": {path.name: sha(path) for path in HERE.iterdir()
                       if path.suffix in [".log", ".json"] and path.name != "verification-summary.json"},
    "guideRenderPageHashes": {path.name: sha(path) for path in
                             sorted((ROOT / "build/launch-guide-render").glob("page-*.png"))},
}
(HERE / "verification-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: summary[key] for key in ["flutterPassed", "nodePassed", "manualPages", "productionCertified"]}))
