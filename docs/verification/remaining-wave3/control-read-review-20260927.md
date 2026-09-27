# Wave 3 close-control read-plan follow-up — 2026-09-27

Contract 47 and unapplied additive candidate `20260927001000` replace the private
inventory-account correlation with a deduplicated command/source join and add
`stock_movements_finance_command_source`. Current product mappings and original
posted asset accounts, plain/`.stock` source identity, cutoff, permissions and
the 50-account atomic failure boundary remain unchanged. Shared posting,
allocation, residual and period-lock engines are untouched.

The complete 35-candidate stack passes **775 procurement/finance, 105 inventory
and 169 receivables strict rollback assertions** (1,049 total) with **JIT enabled**.
The previously timing-out oversized account-basis probe now passes. The three
named `control-read-*-release-candidate-20260927.json` files contain final results;
query hashes are recorded in `control-read-query-hashes-20260927.json`.

Three EXPLAIN ANALYZE calls on the completed synthetic dataset record account-
basis execution times of **17.724, 15.116 and 14.988 ms**, with JIT enabled and
buffer/plan metadata retained in the procurement result. These warm synthetic
timings do not establish installed behavior, production p95 or concurrent load.
The preceding default-JIT timeout in the dimension review is diagnostic history,
superseded for this candidate fixture by the passing read-plan follow-up.

The public client contract and UI are unchanged; the passing **123 platform and
169 desktop tests**, scoped analyzers, six inspected new 200% renders and isolated
**112.7-second** Windows build remain the dimension checkpoint. No executable was
launched. Candidate read-plan verification is distinct from native acceptance.

At **2026-09-26 19:23:14 UTC**, the development ledger still has **36** installed
migrations through `20260926082441`. The new read index, dimension tables and API
are absent outside rollback. All four installed shared finance MD5 fingerprints
match. Raw catalog/ledger/fingerprint evidence is `control-read-after-20260927.json`.
The earlier refreshed advisors remain unchanged; no authentication, production,
stock-opening acceptance, Git index or concurrent Wave 4 work was altered.

Future installation requires compatibility review of the ordered stack. This is
a forward read-plan repair: withdrawing it can restore the previous private
reader and remove the additional index through a reviewed additive migration,
without modifying posted financial or inventory history. No installation or
down-migration rehearsal has occurred.

Wave 3 remains incomplete: wider landed allocation/correction, oversized counts/
disposition, operational dashboards/list and party/bank exports, source/attachment
navigation, broader recovery and real contention/load proof remain development
work. Installed/native/Credential Manager/owner acceptance stay separate.
