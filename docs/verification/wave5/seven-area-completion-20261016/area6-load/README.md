# Area 6: load, limits and recovery

The local implementation work repaired a false-pass load gate. It previously accepted nine manipulated traces while retaining plausible summary fields. The integrated validator now derives coverage, P95 and dispatch invariants from the actual trace. CLI review must bind the new module.

**204 distinct controlled tests passed**: 199 combined coordinator/provider/preparation/reader-writer/integration checks, including16 new trace/CLI controls, and5 separate capacity arithmetic tests. The original one-pass/nine-failure regression record and a later sandbox junction failure are preserved; the final full suite passed without skips outside the sandbox. No network, live PostgreSQL, genuine session provisioning, private input or SDK operation was performed.

**All11 assigned requirements remain open. Full target load: NOT_RUN.** The existing 500-scope/2000-session protocol and seven committed race definitions are retained. The former source-bound reviews are historical after this change and need a successor independent source review before execution.

The saved Auth settings imply3940s optimistic one-source issuance versus2700s freshness allowance. Two genuine source hosts give an optimistic1940s bound; reserving300s final verification leaves2400s issuance. This arithmetic does not prove deployed per-source independence, verification throughput, MFA, infrastructure or a working cohort. Do not fabricate IPs/tokens or change global Auth policy.

| Row | Work still required |
|---|---|
| FR-502 | Run the seven committed races, then extend exact retry/version/receipt/audit/outbox checks to every remaining authoritative command family; one forecast duplicate race alone does not close this universal criterion. |
| FR-508 | Exercise actual installed time/rows/groups/output/pages boundaries across every analytics surface; retain named rejection and zero partial totals, including genuine pagination permission loss. |
| NFR-503 | Verify actual default50/cap200 pages and exact 10000rows/100groups/366UTCdays/8MiB boundaries. Three over-limit fixture populations exceed or are absent from the existing reviewed preparation; do not fabricate evidence. |
| NFR-504 | Run the published 500-scope/2000 genuine-session 60s+300s protocol and independently audit actual dispatch trace, zero errors and strict P95 read<500ms/command<1500ms on a recorded reference environment. |
| NFR-505 | Identify/implement the allowed large analytics job path with durable scoped progress, <=1000rows/committed chunk, failure/cancellation/resume and source authorization; the reviewed load provider contains no implementation or live demonstration of that job lifecycle. Measure bounded analytics P95<3000ms. |
| NFR-506 | Run all seven genuine independent overlapping committed races (100duplicates,2seats,2admissions,2activation,2execution,2leases,20quota); preserve winner/loser effects and no overshoot. Controlled barriers are preparation only. |
| AC-503 | Combine installed exact-boundary rejection/zero-effect evidence, allowed resumable job evidence and the actual reference-workload latency report; these are three distinct unclosed dependencies. |
| EC-514 | Inject bounded job crash, cancellation and unavailable worker failures in an isolated reviewed fixture; verify named state, no partial totals, durable progress and safe resume without replaying uncertain effects. |
| NFR-552 | Exercise exact and over-limit process snapshot time/rows/groups/output/page boundaries through the installed adapter, with zero partial totals and no hidden truncation. |
| AC-555 | Prove actual paginated source completeness, duplicate identity rejection and allowed/excess source/group/time/output boundaries; fresh controlled arithmetic is narrower than installed pagination evidence. |
| EC-557 | Run real pagination permission loss/retrieval-cap cases plus malformed UTC/inverted windows/oversized serialized output, and verify all-or-nothing failure with protected aggregates cleared. |

The root's frozen actual call count is137;115 migrations/363 API functions, both old authority windows expired and3 jobs paused are coordination inputs. This child did not refresh or change them.

See [completion-report.json](completion-report.json) for full statements, source/test hashes, preserved failures, exact commands and evidence boundaries.
