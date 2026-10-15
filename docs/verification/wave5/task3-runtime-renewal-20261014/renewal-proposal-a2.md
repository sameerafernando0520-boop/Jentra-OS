This is a proposal to renew the same isolated development runtime for **at most 120 minutes**, measured from an actual fresh server preflight after approval of this exact packet. It would atomically change only the expiry field in the existing edge-authority row and its one existing worker-scope row. Both original issue times, scope IDs, non-window hashes, actors, MFA, roles, grants, providers, secrets and destinations stay fixed. The three jobs stay paused during renewal. **No execution is approved by this packet.**

The saved dependency read at 11:43 UTC on 14 October records two expired permissions: the worker scope expired at 08:13 UTC and the edge authority at 09:57 UTC. Renewing only the edge row would leave backend scope checks denied. The read also binds seven installed functions and ACLs, 115 migrations and 363 API functions. The earlier global snapshot records three approved date pairs, zero exports, zero worker ticks, delivery outcomes, receiver receipts and quota periods, and 24 old scheduled HTTP 404 responses. Those saved observations may now be stale and require fresh checks.

The exact V7 deployment has 25 verified returned source rows. Its one unsigned request returned HTTP 403 WORKER_ACCESS_DENIED. That proves the unsigned ingress denial; it does not prove that the configured service key is valid or authorized by the backend.

All proposed management attempts are included in the cumulative ceiling:

| Phase | Maximum new attempts | Cumulative maximum |
| --- | ---: | ---: |
| Already recorded | 0 | 134 |
| One actual owner readiness GET | 1 | 135 |
| Renewal preflight, one transaction, readback | 3 | 138 |
| Original two exports: 24 ordinary calls and one reserved read-only resolution | 25 | 163 |
| One signed health dispatch: preflight, dispatch, at most three readback polls | 5 | 168 |
| Separate three-job resume: preflight, one transaction, readback | 3 | 171 |

The new overall maximum is **134 + 37 = 171**. The ordinary export maximum is 162; its conditional resolution makes 163. These are proposed maxima, not invented future observations. A6 may use 138 as its prior only after the four preceding attempts actually occur. Fewer, different or additional calls require a revised exact plan and review. The earlier 150, 156, 157, 159 and 160 records remain preserved. The 160 calculation omitted renewal-control overhead.

The guarded SQL has NULL approval and timestamp inputs, so it fails closed as saved. A later exact helper must bind the actual direct human reply, fresh owner metadata, post-approval server anchor, rendered SQL and independent operation review. The template locks the two exact old rows, checks their original expiries and hashes, seven function/ACL bindings, forced RLS and table types, the unchanged billing trial, exact paused jobs and outside-job preservation. It changes only two expiry fields and aborts on any count or postcheck mismatch. It does not select Vault values or change schema, functions, users, grants, secrets or jobs. The original seven-day-from-issue table limits remain. [PostgreSQL row-lock documentation](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS) and [clock semantics](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-CURRENT) support the lock and freshness design; the SQL itself has not been run on a database.

After the original exports, schedules still require one successful, bounded signed manual health invocation while all three jobs remain paused. Require its actual completed response, matching completed health tick and successful outcome through the unchanged backend service-role checks. Keep the model count unchanged. An unsigned 403, catalogue grant or key-shaped string is insufficient. Charge the manual health request as request 25 under the original cumulative 4,320 scheduled-worker request cap. This proposal includes no model invocation; the original cumulative maximum of four remains. Failure keeps schedules paused. Actual schedule resumption has its own final operation review.

The frozen a5 remains unchanged and expired. New a6 source, tests, preparation, actual renewal readback and final private-adapter gate are required. Its test path is docs/verification/wave5/task3-export-renewal-20261014/finance_exports_20261014_r5_a6.test.mjs. The proposed calendar amendment lets only NEW a6 use the same actual approved server-anchored window of at most 120 minutes, including a UTC-day crossing. Fixture dates stay 13 October; statement basis, IDs and completed date commands stay fixed. The version label 20261014 is not an execution-day authorization. No approval or actual application window exists yet. The scheduler candidate is separately owned and actively changing; its exact final source and operation review remain pending. This packet preserves its a1 historical binding without claiming current bytes are unchanged.

The proposal does not resolve missing Windows profile/native keyboard, restart or recovery evidence, private database inputs, 2,000-session load capacity or production release checks. It accepts no requirement rows. Approval, actual timestamps and successful operations are all still absent.

Exact proposal JSON SHA-256: 8bb011428684768dc98b520e895b2bad0d1f9ddf7e17cd198083cc56bca9ef2c. The a2 manifest binds this proposal, SQL, inventory, validation, source and all earlier evidence.
