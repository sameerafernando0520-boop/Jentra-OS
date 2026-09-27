# Close-control inventory basis read plan — FR-375 / AC-320 / NFR-320

Unapplied additive performance candidate. The close-review public API, exact
amounts, permissions, cutoff, historical source attribution and 50-account
failure boundary remain unchanged. No posting, journal, allocation, residual or
stock-opening engine is changed.

The private inventory-control account reader expands each scoped immutable stock
command to its plain and `.stock` journal source types once, deduplicates command
identities, and joins posted asset journal lines dated through the cutoff. Current
product account mappings remain in the basis. A supporting scoped command/source
index avoids repeated correlated stock-history scans. More than 50 distinct
accounts still raises `CLOSE_INVENTORY_ACCOUNT_LIMIT` atomically.

The complete final-stack regressions run with JIT enabled. Rollback-only EXPLAIN
ANALYZE evidence records the helper's plan and repeated execution timings on the
synthetic dataset. This establishes candidate read-plan behavior, not production
p95, installed behavior, multi-session load or native acceptance. Installation
requires the same coordinated compatibility review as contracts 43 and 46.
