# Current and local conflict comparison

This completes the current/local comparison required by FR-387 and EC-302 for
requisitions, purchase orders and supplier bills. It adds no lifecycle command.

A version conflict keeps the encrypted original draft and exact financial strings.
The user may request the current document through a bounded, authenticated read of
the existing scoped API view by its exact ID. Unknown kinds, malformed identities,
scope mismatches and missing records fail explicitly. The read does not mutate the
draft or substitute a new expected version into a sealed command.

The comparison displays the current and local material header and line fields,
including versions, status, source identities, quantities, prices, taxes and
dimensions. It retains exact decimal strings and shows added or removed fields.
Internal local UI metadata and actor audit fields are excluded. A scrollable
comparison handles long documents without dropping lines. Explicit reload requires
confirmation; cancelling preserves the original draft. Reload removes only that
local editor draft and opens the reviewed current document for ordinary editing.
No automatic merge or overwrite is permitted.

The comparison is bound to the originating workspace and access epoch. Disconnect,
reconnect, scope replacement, disposal or a definite access denial removes current
material fields and prevents reload. Unavailable storage during reload retains the
local draft and prevents replacing it with an unverified server version.

Candidate/API source checks and synthetic UI tests do not prove installed or native
authenticated acceptance.
