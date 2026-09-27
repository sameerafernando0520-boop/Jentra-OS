# Governed saved-report exports — FR-382 / FR-394 / AC-323

Unapplied additive candidate. Financial statements, AR/AP/GRNI controls, inventory
valuation, tax review, budget variance and consolidated close reviews can export
their complete currently filtered frozen section to CSV or XLSX. Existing report
RPCs remain the authority for source access and section/filter validation. Both
entity and working-branch `finance.reports.export` are additionally required.
No arbitrary table, SQL, upload, scheduler or unbounded export is supported.

`api.report_export_preview` returns one canonical JSON document and its SHA-256.
The document identifies tenant, entity, actor, working branch, report ID/version,
source generation time, report scope, cutoff, period/comparison/budget identity,
section and exact filters. It includes all filtered evidence, in its frozen order,
up to 10,000 rows and 8 MiB. Oversize fails; no silent truncation or partial job.
The client verifies the canonical hash and response identity before encoding.

CSV is UTF-8 RFC-4180 text. XLSX cells use inline strings, preserving exact
decimals and identifiers without spreadsheet number coercion. The first data row
has `record_type=metadata`, so even an empty section retains provenance; following
rows have `record_type=data`. Nested evidence is JSON text. Formula-like labels
in CSV receive an apostrophe prefix; exact signed decimal strings retain their
literal value. XML-invalid control characters, cells above 32,767 characters,
more than 256 columns, excessive cells or files above 10 MiB fail before delivery.
When importing CSV into a spreadsheet, exact amount columns must be text.

`api.record_report_export` rechecks current source and export access before replay,
then verifies the canonical source hash, bounds, filename and file hash. It records
an attributable Wave 2 `core.export_jobs` row through the shared immutable command,
receipt, audit and outbox engine. Metadata registration has completed; local file
delivery is explicitly unconfirmed in server metadata. It never claims the file
was installed, delivered to another person, or accepted by an owner.

The desktop prepares exact bytes and a sealed encrypted request, asks for a local
save target, registers the export, then writes the verified bytes. Cancelled file
selection sends no command. Uncertain registration retries only the sealed request.
Native write failure retains the same registered job and byte hash for recovery;
fresh permission checks precede every delivery retry. Atomic encrypted confirmation
survives route disposal. Offline, scope or MFA changes hide preview/evidence and
prevent new delivery. No authentication or Credential Manager setting is changed.

The reusable export workspace is reached from each supported report with its
current section/filter. These candidates are separate from installation, genuine
native file-dialog/process-restart acceptance, contention/load and owner signoff.
