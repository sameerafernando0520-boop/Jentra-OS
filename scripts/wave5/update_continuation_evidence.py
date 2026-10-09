"""Compatibility entrypoint for the current Wave 5 evidence updater.

The evidence package is maintained by the Node script so it can run in this
workspace without a Python installation. It validates the strict rollback
result before refreshing the requirement matrix and status records.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'wave5' / 'update_current_evidence.mjs'
subprocess.run(['node', str(SCRIPT)], cwd=ROOT, check=True)
