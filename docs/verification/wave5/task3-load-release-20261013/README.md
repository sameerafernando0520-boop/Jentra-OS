# Load and release verification, 13 October 2026

This additive evidence folder belongs to the concurrency/load and release-check subagent. Existing review bundles, sessions, fixtures, application sources and root lockfiles are preserved.

The reviewed Wave 5 target is the synthetic development project `xpdoufauvrbdmxgngetv`: 500 scopes, 2,000 distinct genuine Auth sessions, 60 seconds of warmup plus 300 seconds of measurement, at most 900 seconds for coordinator execution and 100,000 timed requests. The selected initial rate is 20 requests per second and the measured operation mix is 70% indexed reads, 20% fresh forecast commands and 10% bounded analytics. Model calls and webhook sends are excluded.

Local transport/helper checks are not live PostgreSQL, genuine-session load, external-effect or production evidence. Production provisioning/deployment, billing, global Auth changes and acceptance-owned data are excluded. Private credentials remain outside this folder.
