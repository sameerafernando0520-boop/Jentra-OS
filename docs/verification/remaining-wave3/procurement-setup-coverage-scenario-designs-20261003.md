# Shared setup workflow verification designs — 2026-10-03

These are read-only designs pending the final 189-file current-source coverage
report. No test or product source is changed. Existing warehouse and Jentra app
tests already cover preview-mode creation, basic field validation, unsaved
discard, selected branch and accessibility/goldens. They do not exercise a
concrete setup gateway's version conflict, file pipeline or command failure paths.
Existing CRM platform tests cover only scope absence, one child-page bound and
invalid lead input; source-matched final coverage must determine further need.

1. **Existing warehouse save and explicit version-conflict merge.** Mount the
   actual setup route with an encrypted memory repository and a concrete fake
   gateway returning warehouse version 3 in the selected branch. Edit its name;
   Save returns typed `VERSION_CONFLICT` and `findById` returns version 4.
   Require one upsert at expected version 3, retained encrypted local payload,
   displayed local/server versions, and no implicit second mutation. Use the
   actual manual-merge control, review the unchanged local fields and Save again;
   require the original warehouse/branch IDs, expected version 4, exact edited
   name and successful draft removal. A separate failed follow-up read must retain
   the conflicted draft and disable unavailable merge authority. This exercises
   actual conflict controls and storage, not method-touch coverage.

2. **Import preview cancellation, local rejection and atomic server outcome.**
   Override only the existing file-service/codec ports with a bounded CSV byte
   fixture for the chosen resource. Open Import from the real toolbar. Invalid
   required fields must show row validation and disable Apply, with zero import
   calls; Cancel on a valid preview also sends none. Apply a valid two-row fixture
   and require exact selected resource/scope/format/file metadata and both
   canonical rows. A typed server failure must show its failure guidance without
   imported list rows or an atomic-success message; success triggers the scoped
   list refresh and reports the confirmed atomic import. File bytes remain
   synthetic and no native file dialog or real import is executed.

3. **Filtered audited export through the actual toolbar.** Set literal search
   and status in the setup workspace, render two exact records and choose CSV
   export via the actual menu. Use a fake file-save port recording output bytes.
   Verify stable headers and exact values, then require the export command to
   record the selected resource/scope, normalized literal filters, columns, row
   count and actual byte size. Cancelling the save sends no export command;
   denied/offline export is disabled; a failed audit-job response must not show
   the audit-success notice. This separates file-generation evidence from a
   recorded export receipt.

4. **Private attachment registration/upload/completion stages.** Use the actual
   attachment resource/upload interaction with a permitted aggregate and
   synthetic allowed bytes. An invalid MIME/size/name fails before registration.
   A rejected registration must send no upload/completion; a transport upload
   failure must retain a staged result and show fixed upload-failed guidance,
   with no ready attachment or completion call. Success must preserve the same
   staged attachment identity through upload and completion and refresh only
   after confirmation. Read-only/offline controls send no upload. These assertions
   target actual staged/ready boundaries; they do not claim private Storage or
   native file-picker acceptance.

If final coverage confirms the CRM adapter gap, supplement its existing three
tests with a synthetic HTTP contract harness for a successful exact lead save,
pipeline/activity paging and typed RPC failure decoding, checking the scoped
request, immutable envelope IDs/version/timestamp, exact decimal strings and
bounded response shape. Do not use a real localhost server or installed project
as a substitute for deterministic transport evidence.
