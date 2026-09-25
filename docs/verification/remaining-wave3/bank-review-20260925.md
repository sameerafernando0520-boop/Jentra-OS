# AC-318 bank reconciliation candidate review — 2026-09-25

The additive `20260923225202_bank_reconciliation.sql` candidate, contract 34,
`/finance/bank` workspace and scoped Supabase gateway are implemented in the dirty
checkout. None is installed. Development project `xpdoufauvrbdmxgngetv` was
`ACTIVE_HEALTHY` on Postgres 17.6.1.166 after verification. The migration ledger
still contains 34 installed versions, ending at
`20260911130900_stock_opening_approver_setup`; `finance.bank_statements` and
`api.bank_reconciliation_command` are absent outside the rollback transactions.
No authentication, production state or stock-opening acceptance artifact changed.

## Source and contract

- Branch-scoped, permission-checked imports store exact signed statement evidence
  without GL posting. Exact balances, date ranges, duplicate identities/references,
  file and row bounds are checked on both sides of the API.
- One-to-one, one-to-many and many-to-one matching claims posted bank journal and
  imported statement lines atomically. A difference requires configured exact
  tolerance and adjustment authority, then posts through the shared immutable
  journal engine. Reversal retains original membership evidence and creates a
  linked inverse journal in an open period when needed.
- The command receipt is checked against scope, action, source, exact values and
  current bank version. Scoped encrypted drafts retain sealed retries. Offline or
  revoked access conceals source evidence and disables mutations. The workspace
  uses capability-gated navigation, bounded pages, confirmed reversal and a
  scrollable 200% text layout.

## Fresh development verification

- `supabase/tests/build_bank_candidate.ps1 -Suite procurement`: **405/405**
  pgTAP assertions passed in a transaction ending in `ROLLBACK`. This includes
  the AC-318 import, match, adjustment, reversal, replay, permission, immutability
  and atomic-failure assertions.
- The same candidate with `-Suite inventory`: **105/105** rollback assertions
  passed. With `-Suite receivables`: **158/158** rollback assertions passed.
- Platform bank gateway, statement CSV/XLSX and Wave 2 codec regression: **29/29**
  tests passed. Desktop controller/recovery/navigation/large-text widget and golden
  tests: **11/11** passed. Both light and dark 200% goldens were visually inspected
  after correcting label spacing and field widths.
- Focused `flutter analyze --no-pub` passed for AC-318 desktop routing/workspace
  and platform adapter/file/codec changes. `git diff --check` passed. `pubspec.lock`
  was restored to HEAD after Flutter's unrelated dependency refresh.
- Security advisor still reports the pre-existing leaked-password-protection
  warning; no auth setting was changed. Performance advisor reports unused-index
  information from the installed schema. Neither is evidence about candidate
  indexes because this migration remains unapplied.

## Open acceptance and review

These are candidate tests, not installed-schema, authenticated-native, load or
multi-session contention evidence. Real Credential Manager restart recovery,
native walkthrough, installation coordination and owner signoff remain open.
Other Wave 3 finance and cross-cutting slices remain separate from AC-318.
