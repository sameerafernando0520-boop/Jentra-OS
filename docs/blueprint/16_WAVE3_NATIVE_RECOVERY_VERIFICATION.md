# Wave 3 native Windows recovery follow-up

Continuation from `f3944014eeabf57862aedf1cabf4f78168cd9c86`, verified on
2026-09-11 in Asia/Colombo (2026-09-10 UTC). This closes the local native
restart-recovery evidence gap identified in the AC-305–AC-308 handoff, within
FR-386, NFR-313, AC-322 and EC-340. It does not constitute authenticated business
acceptance or the complete Wave 3 release gate.

## Changes and reproduced failures

- Simultaneous first saves previously generated independent encryption keys.
  The last key write won, leaving earlier ciphertext unreadable by a fresh
  cipher. A new regression reproduced `SecretBoxAuthenticationError` before
  the fix. The shared application cipher now resolves one durable key for all
  concurrent callers and retains the resolved key after initialization, avoiding
  repeated awaits on an old completed initialization future. Failed key
  initialization is cleared so storage recovery
  can retry; it never retains an unpersisted key as a successful result.
- Creating or editing a receivable could fail its first disk save without
  setting the local-save failure flag. Both new controller regressions failed
  before the fix. All form persistence now records that failure, retains fields,
  reports `LOCAL_STORAGE_FULL`, and prevents the editor's close/back actions
  from silently abandoning them. A visible **Retry local save** action works
  offline. Commands require successful persistence of the current form first.
- After a failed autosave, command recovery now retains the latest reviewed form
  together with its envelope. The earlier persisted form cannot silently replace
  those edits after a response is lost.

The key name and ciphertext format used by ordinary application drafts are
unchanged. The cipher is shared by local drafts and cached reference payloads;
quotation and order regression suites are included in verification.

## Native process evidence

The separate `apps/jentra_desktop/tool/windows_recovery_probe.dart` entry point
uses the real production `WindowsCredentialKeyStore`, `DraftCipher`, disk-backed
Drift/SQLite, `ReceivableDraftStore` and `ReceivablesController`. It runs as a
Windows release executable with the installed secure-storage plugin.

Each run uses a unique synthetic database directory and credential name. The
probe does not access the user's ordinary draft database or draft credential.
A file-backed simulated gateway records a synthetic commit and drops its
response; it makes no network request. This proves native client recovery and
command identity, not authenticated Supabase posting or financial reconciliation.

| Fresh process phase | Verified behavior |
| --- | --- |
| Seed | Eight simultaneous first saves share one native key; an additional offline editor draft persists an exact large decimal; stored payloads exclude the synthetic plaintext marker. Parent forcibly stops the process with SQLite still open. |
| Interrupt | A new process decrypts all nine drafts without writing a key; actor/tenant/entity/branch isolation holds; further offline edits persist and offline submission sends nothing. An online synthetic post commits, loses its response, and retains the exact envelope. Parent forcibly stops this process with SQLite still open. |
| Retry | Another process restores the interrupted command; offline retry sends nothing; online retry sends the byte-identical RPC, IDs, timestamp, version, scope and payload; confirmation removes the recovery record. |
| Verify | A fourth process confirms the completed command stays removed, all nine independent drafts remain, and the later offline edits are intact. No new key is written. |
| Cleanup | A fifth process removes only this run's test credential and verifies its absence. |

Successful final run: `7d124cab-909f-4443-8aac-19d7a83c0ab0`, at
19:34:34–19:34:36 UTC on 2026-09-10. The probe release build passed in 26.9 seconds.
The harness then restored the ordinary `lib/main.dart` release build in 45.0
seconds. Its separate startup smoke remained responsive for ten seconds and
reported three process-owned windows. That startup used the
unconfigured preview; it was not an authenticated walkthrough.

Run from the workspace root after `flutter pub get --offline`:

```powershell
& '.\docs\verification\ac305-ac308\windows-native-recovery.ps1'
```

The harness builds the alternate entry point, copies it into its unique ignored
build directory, starts hidden processes, stops only its own process IDs, deletes
only its unique test credential, and restores the normal release build in
`finally`. Synthetic SQLite and simulated-gateway artifacts remain in the ignored
run directory for diagnosis. Each run replaces the summary with `passed: false`
before starting, so a failed rerun cannot leave an older success as current proof.
Use the console exit status and matching run ID when reviewing evidence.

## Regression and visual evidence

All **275 tests** pass: **78 domain, 66 platform, 10 design-system, and 121
desktop**. The six new tests cover concurrent first saves, retry after credential
write failure, failed initial create/edit persistence, latest-form command
recovery after autosave failure, and the rendered offline retry path. The
whole-workspace analyzer reports no issues; the final non-mutating formatter
reports seven changed-scope Dart files with zero formatting changes. Whitespace
checks pass.

The four package suite logs, analyzer, source fingerprints, and native
reports are recorded under `docs/verification/ac305-ac308/` with
`native-recovery-*` and `windows-native-recovery*` filenames. The new rendered
storage-failure golden was inspected at 1440 pixels. It shows retained editable
fields, an explicit error and retry button, and no clipping. Existing quotation,
order, and receivables goldens are retained and compared without updating them.

## Boundaries and next work

The development project `xpdoufauvrbdmxgngetv` was re-read: ACTIVE_HEALTHY,
31 migrations through `20260910135507`, all five posting/allocation contracts
present, zero security-advisor findings, and no tenant fixtures. This follow-up
made no database changes. The earlier 469 SQL assertions remain prior evidence;
they were not rerun for this client-only change.

Remaining acceptance work:

1. Governed synthetic tenants, operator/approver identities and inventory opening
   setup, followed by the authenticated Windows order-to-receivables walkthrough
   and owner signoff. No credentials or real business fixtures were invented.
2. Multi-session database contention/load and live transport-loss tests. The
   local simulated gateway does not prove server contention or network behavior.
3. Two application processes starting simultaneously with no existing key;
   abrupt termination during the key write itself; Windows sign-out/reboot or
   a different Windows account; actual disk exhaustion and global route/window
   closure during failed writes. Current injected-write tests cover the editor's
   own close/back actions and dispatch persistence, not every navigation surface.
4. The remaining approved Wave 3 procurement, inventory/valuation, supplier
   payments, bank reconciliation and broader finance slices. Production release
   and real financial operations remain separately authorized work.

No Git staging, commit or push was performed. Continuation is not acceptance
signoff, and published migrations remain immutable.
