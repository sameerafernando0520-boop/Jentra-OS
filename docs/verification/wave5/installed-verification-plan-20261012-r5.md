# Prepared installed verification, 2026-10-12 r5

This is offline preparation for the exact approved runtime bundle `db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b`. The 71 migration inputs are freshly hashed; the original six are not included for replay. No SQL, fixture, account, secret, native session, SDK job or installation was executed by this preparation.

Read the three baseline rename fingerprints before migration order58 and again after installation. Then run the three postinstall queries serially after root records the actual71 connector-installed ledger rows. Each query has one complete caller-owned read-only transaction ending in ROLLBACK. Keep the raw connector result and live context. Strict metadata raises on a missing/incorrect grant, forced RLS or ledger count; catalog table/body mismatches are separate failures. These are not business behavior tests.

| Order | Query | SHA-256 |
|---|---|---|
| 0 | [installed-baseline-rename-fingerprints-20261012-r5.sql](installed-baseline-rename-fingerprints-20261012-r5.sql) | `f4beb12842047ebf0ab8892155c092b1bf357ec27b044be62796bd4f81579b0a` |
| 1 | [installed-catalog-verification-20261012-r5.sql](installed-catalog-verification-20261012-r5.sql) | `7d84efee06b401d7d75f02f2fa395b86f2669b0c96523237d7beb81cac1e6c08` |
| 2 | [installed-strict-metadata-20261012-r5.sql](installed-strict-metadata-20261012-r5.sql) | `906dd7f51f80962b627a62e059637ef57eb896b715acfc27820e4ffea9aec41b` |
| 3 | [installed-preservation-fingerprints-20261012-r5.sql](installed-preservation-fingerprints-20261012-r5.sql) | `8f200dd3a857733c45e4d8b3fc7e4ee7f51c844911ccccbf739630894993a165` |

There are 541 final function-body expectations, 215 directly created tables, 72 explicit/reviewed forced-RLS predicates and 18 exact function grant predicates. Function expectations include the three concrete supplier-bill wrappers, the exact guarded return-aware transforms and30 reviewed body-mapped rename/schema moves. Three other renamed bodies originate in the already installed baseline and require actual before/after fingerprints. CRLF is normalized to LF; no other source-body normalization is allowed. These are source mappings until an actual installed result matches them. Catalog fingerprints capture other policy/grant/constraint/trigger and dynamically forced table details for independent comparison; the explicit forced-RLS predicate subset is not claimed as all dynamic RLS coverage.

Compare the protected four access-row fingerprints and the old provider identities against the immediately preinstall full live read, with only source-bound approved replacements allowed. The frozen October 10 snapshot and October 12 count-only read do not establish current preservation. Read the actual ledger again and retain all old43 name/version pairs and the original six exact versions. Existing desktop account identity and confirmation are checked without selecting password/session/token fields.

The reviewed historical 105/25 SQL probes prepend all71 schema migrations and insert synthetic Auth rows. The older126 installed probe also inserts/deletes test MFA factors. Preserve these files and their historical results; do not run them unchanged or call their results fresh installed evidence. Their successful source probes do not override the current no fabricated Auth/MFA rule.

Account-bound rollback behavior remains incomplete until all six private Auth Admin creates return genuine IDs and actual MFA is available. Use only exact reviewed new tenant scopes, no permission-registration shim, no constructed JWT proof, and no existing acceptance role/store/session change. An already committed bootstrap cannot be repeated as a rollback fixture. Cash/provider/scenario/lease/model cases require fresh bounded nonempty source fixtures and exact committed-state evidence. Actual persistent setup, real delivery/model calls and independent-session contention/load remain separate stages.

Do not split a transaction over connector calls. On an error preserve the failed raw result; a new connection cannot roll back an old connection. Obtain fresh after-state fingerprints before reporting preservation. No real HTTP/Vault/cron work belongs in a rollback-only probe.

Owner acceptance remains3/109, with106 open. This plan supplies no additional acceptance and leaves installed behavior, authenticated native/MFA, actual delivery/model, contention/load and full owner acceptance open.
