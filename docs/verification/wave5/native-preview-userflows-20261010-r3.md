# Actual native Preview observations — October 10, 2026 r3

The ordinary isolated Windows Preview was exercised through the supported native UI tool. **14 recorded cases comprise 10 passes, 2 failures and 2 blocked cases.** This is offline Preview evidence; authenticated native acceptance and the full native keyboard gate remain false.

The [actual observation record](native-preview-userflows-20261010-r3.json) has SHA-256 `56b786ff721e1f3bbd54d4d277801d85e0c9125ceb705705be3b5dcb156d401c`. It binds the exact new packaged executable, source manifest, recorder and [prelaunch path observation](windows-userflow-storage-before-20261010-r3.json). The packaged Preview executable SHA-256 is `2dde1076175a4209d57a7480617a838778722da9f8fb528c418ab4f1250a22a9`; its PE product is `com.jentra.test / JentraOS_WindowsTest_20261010-r3_Preview`. Each case matches an independently returned executable/window identity with the exact Preview title. This is a separate product on the existing Windows account; no new OS security boundary was provisioned.

| Case | Result | Actual outcome |
|---|---|---|
| P01_STARTUP | Pass | Ordinary dashboard rendered with visibly labelled sample metrics; no login performed. |
| K01_INITIAL_CTRL_K | Fail | Ctrl+K did not open the command palette after initial launch. |
| K02_ESCAPE | Pass | Escape dismissed an open palette and kept the dashboard page. |
| K03_DIRECT_LETTER | Pass | Physical `f` appeared in focused search and filtered Finance. Earlier native `type_text` calls had no visible effect. |
| P02_FINANCE_BLOCKED | Blocked | Enter opened Finance, but its foundation placeholder exposed no posting, ledger or report controls. |
| P03_SETUP_LIST | Pass | Business setup showed four sample chart-of-account records and the expected sample scope. The offline page also displayed “Online confirmation ready”; this label does not prove a connection. |
| P04_REQUIRED_VALIDATION | Pass | An empty account save showed required errors for both code and name and kept the dialog open. No business save occurred. |
| K04_FORM_TAB | Pass | The visible caret/focus moved from Account code to Account name; the accessibility focus entry remained a generic pane. |
| P05_DARK_THEME | Pass | Cancel closed the unused form; dark setup retained the sample scope and four records. |
| P06_DENSITY | Pass | Control and row spacing changed without losing the sample scope or records. |
| P07_THEME_RESTART | Pass | A controlled close and relaunch of the same executable restored dark theme. No encrypted accounting draft was created or recovered. |
| P08_PROCUREMENT_BLOCKED | Blocked | Procurement showed only Product units, with no supplier bill/payment controls or explanatory connection/permission message. |
| P09_MAXIMIZED | Pass | Maximize exposed the wider command field and Create label while preserving the shell. |
| K05_CTRL_K_RECHECK | Fail | Tested Control_L+k and Ctrl+k chords still did not open the palette after focus and maximization. |

Ctrl+K remains unresolved. These screenshots establish the visible failure; they do not distinguish native input-tool behavior, focus routing and application shortcut handling. Mouse search, physical `f`, Enter, Escape and Tab worked in the separately recorded cases. A complete native keyboard acceptance claim would be inaccurate.

The observation interval is 07:01:37.982–08:22:23.733 UTC. Three exact Preview window IDs were bound: 985376, 1507522 and 329628. The initial window was no longer present after an intervening pause; the cause was not observed. Root later relaunched the same verified executable. That intervening transition is not a controlled recovery test. The later P07 close/relaunch is the explicit preference check. No observation from one window is represented as a continuous session across all three windows.

Independent review rehashed all 14 screenshot files and decoded every image, confirming the recorded dimensions (12 at 1267×714 and 2 at 1536×816). There are **13 unique screenshot byte hashes**: P09 and K05 have identical bytes, consistent with the screen remaining unchanged after the shortcut recheck. They remain separate action observations, not two distinct visual states. Five representative images were independently viewed: K03, P04, P07, P08 and K05. Their visible search filter, required-field errors, dark restart, limited Procurement page and unchanged maximized screen agree with the bounded observations. This review did not replay the native actions.

The [paired ordinary package report](windows-test-verification-20261010-r3.json) separately verifies both source-bound builds, 68 release entries and 75 decoded portable ZIP entries. The matching base-source full desktop suite passed 2004/0/0 in its earlier warm tree; it was not rerun in the r3 identity-overlay copies. The [528 accounting checks](accounting-checks-result-20261010-r2.md) are controlled calculations and injected contracts, not user transactions.

The [postlaunch path metadata](windows-userflow-storage-after-20261010-r3.json) checks the same four exact new product directories. Only Preview application-support/Roaming exists after these actions; Preview cache and both Connected paths remain absent. Directory contents, credentials, session data, existing acceptance stores and other product paths were not inspected or copied. This observation supports product-directory isolation only, not draft recovery or authenticated storage acceptance.

No authenticated Connected session, real accounting posting, authoritative report generation, genuine MFA, actual export/model/worker delivery, independent-session contention or target-scale load was performed. Owner acceptance remains the separately recorded three complete criteria, AC-551/552/553, out of 109. Additional runtime installation and whole-system signoff remain open. Production and real billing remain excluded.
