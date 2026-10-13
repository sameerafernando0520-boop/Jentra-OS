# Installed verification preparation successor a2

Use the a2 catalog query below, together with the unchanged baseline-rename, strict metadata and preservation queries. The original [plan](installed-verification-plan-20261012-r5.md), source inventory and SQL stay preserved. This successor makes the volatility comparison explicitly text and returns a configuration hash instead of raw configuration values. It performs no SQL and adds no live scope.

| Stage | Query | SHA-256 |
|---|---|---|
| 0 | [installed-baseline-rename-fingerprints-20261012-r5.sql](installed-baseline-rename-fingerprints-20261012-r5.sql) | `f4beb12842047ebf0ab8892155c092b1bf357ec27b044be62796bd4f81579b0a` |
| 1 | [installed-catalog-verification-20261012-r5-a2.sql](installed-catalog-verification-20261012-r5-a2.sql) | `1e388eef0a161d3fe90da7f2b2490b7e7c773985e69fa9c3a743fac3c4dd9745` |
| 2 | [installed-strict-metadata-20261012-r5.sql](installed-strict-metadata-20261012-r5.sql) | `906dd7f51f80962b627a62e059637ef57eb896b715acfc27820e4ffea9aec41b` |
| 3 | [installed-preservation-fingerprints-20261012-r5.sql](installed-preservation-fingerprints-20261012-r5.sql) | `8f200dd3a857733c45e4d8b3fc7e4ee7f51c844911ccccbf739630894993a165` |

Record genuine hashes of the three installed baseline bodies before order58 and compare their renamed aliases afterward. Then run the catalog, strict metadata and preservation queries serially, each as its complete read-only transaction ending in ROLLBACK. Actual connector error/result and immediate after-state fingerprints are required. Source/body/table expectations are preparation until actual installed observations match; dynamic RLS coverage and business behavior remain separate checks.

Do not replay the historical 105/25 bundles, fabricate Auth/MFA or add a permission shim. Genuine account-bound rollback behavior remains incomplete until six actual private Auth Admin IDs and real MFA exist. Vault/cron/network setup and actual delivery/model use do not belong in rollback-only tests.

This preparation leaves owner acceptance3/109 and all runtime gates incomplete. Approval of the exact71-migration runtime setup is recorded separately by root; this document grants no additional approval.
