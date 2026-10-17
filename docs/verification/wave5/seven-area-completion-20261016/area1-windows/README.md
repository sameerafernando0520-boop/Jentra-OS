# Area 1: authenticated Windows workflows

Observed on 16 October 2026. **All nine native criteria remain open.** The source and artifact verification is complete for this bounded area review; actual authenticated Windows acceptance is not complete.

## Work completed

- Executed the existing approved native helper in its read-only `Validate` mode. All **1,068 approved snapshot inputs and 34 exact Connected release files** passed integrity verification. The exact account `jentra-w5-runtime`, package directory and new profile are absent. The current token is not an administrator. No account/package was created and no credentials, stores, SDK, network or native actions were used.
- Rebound the nine full requirement statements and all **33 existing native protocol cases**. No owner decisions were added.
- Independently verified all **25 historical report bindings**, including the actual saved desktop test logs. The historical run finished **13 October 2026 at 18:55:57 UTC** with 2,026 passing desktop tests. Its five focused Process workspace cases cover late response rejection, denied/offline clearing, disposal and light/dark 200% rendering. This is controlled evidence from the historical run.
- Compared **10 relevant current source/test files** against both the historical source manifest and saved tested snapshot: **zero drift**. No expensive SDK tests were repeated for a new date.
- Traced Process controller/provider ownership, epoch invalidation, post-read authorization, encrypted actor/context filter storage, local storage failure conversion and the existing recovery probe. No confirmed product defect was established by this scoped trace, so no speculative product changes were made.

The feature boundary is Process workspace/controller/provider plus the shared encrypted filter store, draft repository, storage error conversion and shell keyboard binding. Actor/session/capability/context changes replace and dispose the controller; connectivity clears its server evidence; reads reauthorize after the awaited snapshot and reject an older epoch. Filter restore authorizes before decryption and after the awaited store read. Only filter input is persisted, not server results or authority. Existing storage tests exercise actual SQLite FULL within disposable storage, while credential adapters are controlled fixtures. The separate receivables native recovery probe uses a simulated server and does not satisfy authenticated Wave 5 acceptance.

## Remaining actual execution

| Criterion | Work still required |
|---|---|
| FR-530 | Actual Connected Analytics, AI, integration, subscription and operator workflows; scopes, explanations, keyboard and named result states. |
| FR-531 | Real encrypted filter/scenario/uncertain-command recovery after restart, sign-out, access loss and offline operation. |
| NFR-508 | Native keyboard focus and action reachability across both themes/densities, 200% text and all three required window sizes. |
| AC-515 | Observe the combined authenticated restart/context/access-loss/offline recovery matrix. |
| EC-513 | Confined, reversible actual native secure-store/disk-full failures plus sign-out/context/stale-response recovery and preserved ciphertext. |
| FR-558 | Inspect actual rendered source basis, cutoffs, completeness and explanations; observe cleared stale/denied evidence. |
| FR-559 | Observe encrypted filter binding, late response rejection and fresh authorization after actor/context change. |
| AC-556 | Actual in-flight/context/permission changes across every supported native variant. |
| EC-558 | Actual provider absence/version drift, network loss and auth/context changes yielding explained cleared states. |

The immediate dependency is the missing exact isolated Windows account/package/profile and a privately authenticated Connected session. The existing [native protocol](../../task3-windows-20261013/native-acceptance-protocol.md) preserves the approved binary and requires private authentication/security handoffs. Root coordinates the live owner; no request to repeat private setup has been sent from this area. SDK or standalone recovery fixtures cannot replace these observations. An isolated native storage failure harness still needs review and real execution after the new profile exists; filling the system disk or changing the owner's actual secure store is outside this protocol.

## Evidence

- [Fresh prerequisite result](native-prerequisites-20261016T121213690Z.json), SHA-256 `6183b217692cad3be0e22c881034f9fd6b44b2d509da12c6d9bb23d4fd1e3fe0`.
- [Independent source and historical evidence verification](source-and-historical-evidence-verification.json), SHA-256 `f68132d3ec755a63e1e64979707424c91b33578d86186f52ee9c4211e81d9e16`.
- [Read-only prerequisite observer](refresh-prerequisites.ps1); each execution creates a new result exclusively and rejects helper/source drift.
- [Source/evidence verifier](verify-source-and-evidence.mjs); verifies saved evidence hashes and reports source drift without inferring a new test run.

Acceptance recommendation: **retain all nine rows as open** until the full actual observations linked in the JSON case map pass. Production readiness, target workload, live billing and genuine native authentication are not asserted.
