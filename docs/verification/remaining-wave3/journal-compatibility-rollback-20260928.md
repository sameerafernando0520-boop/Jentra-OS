# Posted journal evidence compatibility and rollback review

The unapplied `20260928001000` candidate adds one STABLE read RPC and its
authenticated execution grant. It replaces no function, adds no persistent
table/index/column, and changes no posting, allocation, history, authentication,
stock-opening source or existing ledger SELECT/RLS contract. Its nullable
dimension columns require the earlier dimensions candidate; all 36 ordered Wave 3
candidates therefore precede fixtures in this candidate builder. Concurrent Wave 4
candidates are excluded. It is not safe to install this candidate alone before its
dependencies, and no installation is authorized here.

The final finance fixture narrows source-branch permissions inside a subtransaction
and rolls that probe back. It proves the working branch alone cannot authorize
another journal branch. Stock-linked reads recheck current cost permission;
existing raw-ledger RLS still returns no rows for a nonmember and direct deletion
remains denied. Exact reversal/dimension history and the existing private posting
engine remain intact. Candidate suites retain their documented historical seed
adaptations from the final-stack builder; they are synthetic development proof,
not installed or native acceptance.

The client adds a gateway, read-only workspace and contextual links. Older clients
and APIs continue unchanged. The new destination clears data on disconnect,
denial, failed refresh and disposal, and ignores stale acknowledgements. It neither
creates commands/drafts nor changes the originating encrypted recovery flow.
Removing the new UI links/gateway restores the prior client surface without a
business-data rollback. A future approved installation can withdraw the new RPC
grant/drop this reader through a separate reviewed migration; never rewrite an
installed migration or delete ledger history.

All verification transactions use strict `finish(true)` and final `rollback;`.
Post-test catalog evidence confirms 36 installed migrations, absence of this API,
absence of the prior dimension/read-plan candidates and unchanged shared finance
fingerprints. Native walkthrough, authenticated runtime, real contention/load,
process restart of Credential Manager recovery and owner acceptance remain open.
