# Current free-provider result

The Cloudflare Free provider is configured and deployed in runtime V9.
Its actual synthetic request passed with 223 returned tokens, its 16 executable
modules matched deployed readback, and all four unsigned hosted endpoints
returned their expected denials. The exposed original credential was rotated;
the replacement was stored privately in Supabase and its temporary local copy
deleted.

Business acceptance remains pending: genuine Jentra sign-in, current bounded
runtime authorization, an authenticated model request and its exact persisted
usage. The original external delivery is still unresolved and was not resent.

Read the [current activation result](../../development/ai-integrations-free-activation-result-20261102.md)
and `activation-result-20261102.json`. Older records in this directory retain
their original step-specific status. In particular, a stale accounting
assessment's zero counters do not replace the rows in the actual dated SQL
snapshot.
