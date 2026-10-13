**Jentra OS r5 native keyboard investigation — 12 October 2026**

All four native failures remain failed, and the full native keyboard gate remains open. The applicable source handlers exist; this investigation did not establish a Dart defect or an input-provider defect. It performed no new native actions, SDK jobs, tests or live calls.

The original [native record](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/wave5/native-preview-userflows-20261010-r5.json>) ran on 11 October from 2026-10-11T11:53:49.256Z to 2026-10-11T12:13:25.589Z: **27 pass, 4 fail, 2 blocked**, with 33 original screenshots. Its SHA-256 remains `4a8783db056143e7cf6d8031bc30dba7ff7707e315324892acf05fa2fac42840`. Every original screenshot byte hash matched; this investigation did not conduct a new visual review.

| Native case | Original result | Finding |
|---|---|---|
| K04 Control+A | abc became abcf after physical f | Selection failed; modifier delivery not traced. |
| K07 Control+K | Palette did not open | Handler exists; delivered chord/state unknown. |
| K08 literal text | Warehouse edit remained empty twice | Physical q/a later worked; input mechanism unresolved. |
| K11 palette Return | Highlighted row did not open | K12 later succeeded after refocus **and** query change. |

**Source findings**

[jentra_shell.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/lib/src/shell/jentra_shell.dart:34>) binds Control+K. Its search FocusNode handles Down/Up and Enter/numpad Enter at line 618, autofocuses the edit at line 687 and rechecks permission-filtered choices before navigation. [app.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/lib/src/app.dart:21>) has no application shortcut override.

[business_setup_screen.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/lib/src/features/setup/business_setup_screen.dart:1798>) uses a standard TextFormField with no input formatter that explains disappearance of the whole literal string; warehouse code autofocus is declared at line 2453.

Current local Flutter source maps Windows Control+A to SelectAllTextIntent and requires the matching keydown plus pressed Control state for SingleActivator. Those local framework files are separately hashed in the JSON. Their historical source bytes were not pinned by the native build record. Product metadata remains Flutter 3.47.5 / Dart 3.13.4, with four unchanged SDK tool file bindings.

All **1068 current desktop inputs** and **1068 Preview snapshot inputs** matched their manifest hashes before and after this audit; exactly three runner identity overlays remain. The four reviewed application files match their Preview copies. The historical desktop suite remains **2010 pass, 0 fail, 0 skip**, completed 2026-10-10T15:26:33.587Z; it was not rerun today. [jentra_app_test.dart](<C:/Users/sheha/Desktop/Jentra OS/apps/jentra_desktop/test/jentra_app_test.dart:100>) deliberately holds Control down, presses K and releases Control. Controlled widget success does not prove native modifier delivery.

**Evidence limits**

The supported input API explicitly documents `Control_L+a`, plus-separated chords and `Control`/`Ctrl` aliases. The chord syntax was valid. The record contains no engine-delivered keydown/keyup/modifier trace, so requested Control input is not proof that Flutter received Control held. The two Control failures could share a modifier path; this remains an inference.

Generic focus labels cannot establish root cause. K10 Down passed with the same “0 window” label as failed K11. K09 physical typing passed with the same “1 pane” label as failed literal input. K12 changed focus and query, so it is not a focus-only control. Original interference events and stale accessibility dialog nodes remain attached to the native record.

The documentation bundle is `computer-use/26.1007.21434`; the installed `@oai/sky` runtime package version remains **unverified**. Documentation version, input-provider runtime version and Flutter SDK version are separate.

**Checks still to execute**

1. Capture physical abc, one documented Control+A, exposed selected-text/visible selection, then physical f in the freshly focused isolated Preview edit. Keep each action and observation separate; a documented alias may be compared in its own trial.
2. With fresh visible shell focus outside an edit, press one Control+K. If modifier controls still fail, obtain supported provider diagnostics or separately reviewed isolated app event diagnostics for event type, logical key, modifier flags and anonymous focus category only. Do not invent tool key-down/up APIs or log entered text.
3. Compare type_text, physical q/a and optional documented set_value on one freshly observed synthetic warehouse edit. Direct accessibility replacement is distinct from typing acceptance.
4. Repeat palette Down then Return after clicking the search edit **without changing query text**. This separates refocus from the extra query change in K12.
5. If justified by the active task and ambiguity persists, compare the same input mechanisms on an independent noncredential scratch edit surface. That narrows the path without proving a root cause.

These checks are concrete pending diagnostics; none was executed by this investigation. Preserve the four historical failures. Only new current-bound native observations can establish resolution. Any justified future source change needs fresh analysis/tests/build/render evidence and a separate native rerun.

The [storage namespace audit](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/wave5/native-local-storage-namespace-audit-20261011-r5.json>) remains bound at SHA-256 `c806fc271dc7ae33b873090df64ac2e75842e7b5ca7315d9f5f89fff384790bf`; no namespace fix is proposed. No account, acceptance row, session, local-store value or runtime approval changed. Authenticated native, MFA, delivery, contention, load and owner acceptance remain separate open gates.

A first read-only report attempt failed before writing outputs because the snapshot layout was guessed incorrectly. The manifest-backed snapshot path was then checked, and both full source audits passed. No SDK, native action or past evidence was affected.

The [machine-readable investigation](<C:/Users/sheha/Desktop/Jentra OS/docs/verification/wave5/native-keyboard-failure-investigation-20261012-r5.json>) contains every exact source, SDK, documentation, screenshot and historical record binding. SHA-256: `c3785b68693e9665a0b25d06020a7b494547a2f9607efdf0de70e19379c00ddc`.
