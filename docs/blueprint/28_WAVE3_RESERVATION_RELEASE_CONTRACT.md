# Reservation release and history — FR-352 / FR-361

Development contract, 2026-09-18; additive candidate only.

`api.release_stock_reservation` requires authenticated operational scope,
`inventory.reservations.manage`, expected reservation version, immutable command
identity and a reason. It releases the whole remaining reservation. Mode `manual`
requires no additional condition; `expired` requires expiry at server time; `retired`
requires an inactive product. An early expiry/retirement claim is rejected.

Lock order is order header, warehouse/product advisory key, reservation and stock/order
line projections. Release atomically decrements allocated quantities on both projections,
updates reservation state/reason/time, refreshes the order's reservation status, and
records history, audit, receipt and outbox. On-hand quantities, valuations, movements,
journals and fulfilled demand are unchanged. Underflow, stale version, scope or later
failure rolls back everything. Identical retries return the original receipt.

A new append-only reservation history captures allocation increases, partial delivery,
cancellation and explicit release through a table trigger, including exact snapshots,
actor, reservation version and event time. It does not mistake a reservation's original
command ID for the command causing a later delivery. Existing reservations acquire a
baseline at the history coverage start when first changed; untouched reservations are
known unchanged since that start. No pre-coverage history is invented.

The native workspace shows bounded active, expired, retired and all-reservation queues
with named order/product/warehouse, exact quantity, expiry and version. Users enter a
reason and confirm the selected release mode. Uncertain requests retain their exact
encrypted envelope through restart; definite conflicts preserve the reason for review.
History is a separately bounded scoped read. Queue reads never perform business writes.

`api.stock_reservations_as_of` reproduces held quantities at an explicit UTC instant
at or after the coverage start, in 50-row keyset pages. It selects the last recorded
reservation version at that instant and includes only active versions. Expiry does
not silently remove an allocation before the governed release event. Existing,
untouched reservations use their coverage baseline; later creation is excluded.
The response pins `as_of` across pages, exposes exact quantities and the historical
reservation version, and labels order/product/warehouse names as current reference
labels. Earlier-than-coverage or future instants are rejected, never approximated.
The report is built from committed history visible to each database request; it is
not a sealed period snapshot and does not certify concurrent-commit reproducibility.
Native users can load this report without changing the live work queue.

Automatic expiry/retirement processing and complete as-of reports remain separate
integration requirements. This command supplies their governed release primitive;
no scheduler, persistent fixture, acceptance configuration or applied helper is changed.
