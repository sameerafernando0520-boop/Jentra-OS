# V7 provider credential compatibility candidate

Seven new source files are ready for independent review. All 21 controlled tests pass, and all seven syntax checks passed. Opaque service keys now use apikey only; legacy service JWTs retain the exact existing apikey and Bearer headers. This implements the verified [Supabase API-key guidance](https://supabase.com/docs/guides/getting-started/api-keys#known-limitations).

The same key validator protects the default runtime and receiver factories and the shared privileged RPC transport. Scoped controls import that V7 transport without altering their allowlist. Publishable keys, malformed keys and keys shorter than 32 characters are rejected for service use. Reserved sb_ prefixes are checked before the legacy JWT shape, preventing dotted API-key strings from using that fallback. No key is decoded and no secret dictionary or new environment name is read.

The public model reader remains unchanged: its requests keep the caller’s JWT in Authorization and the public key in apikey. Tests cover the actual default raw/scoped worker ports, signed receiver key and receipt calls, HMAC denial, provider readiness, legacy header equality and unchanged public-user headers. The first failed controlled run remains saved; only its incomplete readiness fixture was corrected, with a denial regression added.

The exact payload inventory is 17 runtime files and 10 receiver files, or 27 rows, 20 unique files and 18 unique source modules. The static/dynamic-inclusive graphs are 16/16 for runtime and 8/9 for receiver. The literal lazy worker_runtime.mjs dependency is retained. Runtime also retains the old persistent transport solely for the unchanged public model reader. All old sources and evidence remain intact.

Routing, TLS, runtime scope, schedule/HMAC/caller MFA checks, configuration, caps and request deadlines remain unchanged. The original expiry is 2026-10-14T09:57:07.481942Z. Schedules stay paused; the root and live owner retain the exact operation review, deployment and probe work. No real configuration or credentials were accessed and no live success or release acceptance is claimed.

Candidate manifest: docs/verification/wave5/task3-v7-provider-20261014/candidate-manifest.json (SHA-256 49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6).
Canonical candidate bundle: 2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c.
Source proof: docs/verification/wave5/task3-v7-provider-20261014/source-proof.json (SHA-256 ea94c14e3ee120216796546f6f57e5a6b4820c0ae01b53266816c9efc3688013).
