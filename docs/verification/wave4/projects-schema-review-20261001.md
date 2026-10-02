# Project schema tooling review

The database-designer workflow was run against the actual temporary candidate
catalog. Its SQL reader could not parse the schema-qualified DDL, so the real
Postgres tables/columns/constraints/indexes were exported within the rollback
transaction instead. The catalog has 16 tables and 66 indexes; the schema analyzer's
JSON adapter reports zero indexes because it does not consume that field. Its zero
is a tool limitation, not a missing-index finding.

Private resource rates were normalized from a JSON collection into immutable
`projects.resource_costs`, physically separate from operational capacity. Budgets
and approved time costs are separate private tables. The candidate now includes
the scoped time-cost index needed for that protected paged read.

The remaining eight normalization heuristics were reviewed. Tenant/entity/project
columns in composite keys deliberately enforce same-scope foreign keys. Dependency
identity is the complete plan/task/prerequisite edge. Immutable task progress and
billable units intentionally freeze their original version/digest. Ordered bounded
break JSON preserves original interval evidence and is validated before use. The
project code already has a tenant/entity-scoped unique constraint; a global unique
constraint would incorrectly couple unrelated tenants. Versions retain JS-safe
BIGINT bounds, and index/grouping conventions match installed module contracts.

The index optimizer analyzed eight query patterns and 66 real indexes, reporting
34 suggestions and 11 alleged redundancies. It reasons about isolated columns and
does not preserve scoped composite uniqueness or GiST exclusion semantics. None
of its suggested constraint/index removals was applied. Existing tenant/entity/
branch prefixes support scoped keyset pages; exclusion indexes remain essential
for capacity and common work ownership. These heuristic reports are not EXPLAIN,
contention or measured-load evidence.

The migration feasibility helper initially failed JSON serialization on its own
dataclass values. A temporary runtime serialization adapter, without editing the
installed plugin, allowed it to emit its validation plan. That file is a plan;
executed feasibility/security proof is the candidate rollback suite.

The generated `projects-schema-erd-20261001.mmd` is available for review. No
database installation or role/plan change was performed by these tools.
