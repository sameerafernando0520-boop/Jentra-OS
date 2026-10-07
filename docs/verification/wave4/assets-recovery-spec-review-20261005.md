# Asset recovery Spec review

2026-10-05, independent corrections/evidence owner review. The five source files
in `assets-recovery-standards-source-hashes-20261005.json` match their captured
SHA256 values. No edits were made to the asset files. This is a source/spec review,
not a fresh native execution, installed walkthrough or owner signoff.

| Requirement | Reviewed behavior and limit |
| --- | --- |
| FR-404 | Actor/tenant/entity/branch recovery is encrypted in separate action namespaces. `_recover` and `resume` obtain the original action's current authority before decrypting. Revocation clears forms, records, history, provider state and recovery. Pending identity cannot be replaced or discarded. |
| EC-410 | `send` seals the request before dispatch. `_confirmed` validates exact scope/action transition/version and publishes server success before local acknowledgement or cleanup. Failure to save acknowledgement or delete the draft preserves the original pending request. Resume checks the encrypted acknowledgement before any new dispatch; reconciliation verifies original command/idempotency identity. |
| EC-415 | Current scope controller disposal and authority loss clear data. Directory/detail/history/schedule and authority responses check connection epoch before publishing. Old authority denial cannot clear a replacement connection. A late successful command may preserve its original scoped encrypted acknowledgement without restoring disposed visible state. |
| FR-439 | Scoped bounded register/history/schedule and paged recovery are reachable through named controls. The pending editor exposes exact retry/receipt reconciliation; conflict requires current comparison and a fresh authoritative version. Closing/leave guards retain a saveable draft and prevent exit during dispatch. Current permission checks cover recovery actions. |
| NFR-408 | Tests exercise controller recreation over encrypted SQLite and confirmation/cleanup failure. The acknowledgement SHA256 now covers the canonical complete command envelope, including payload and issued timestamp; tests reject borrowed confirmation for changed body/timestamp and wrong scope. These checks do not prove real Windows Credential Manager restart acceptance. |

No actionable inconsistency was found within this reviewed recovery scope.
Existing guarded full-book approval and transition confirmation checks retain the
original financial evidence; optional refresh failure does not erase a confirmed
result. The parent's current native27 and acknowledgement5 passing evidence is
separate from this review. Real native authentication, Credential Manager restart,
contention/load and owner approval remain open gates.
