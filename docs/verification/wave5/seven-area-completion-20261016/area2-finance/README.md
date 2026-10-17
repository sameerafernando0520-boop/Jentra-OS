# Area 2: analytics and financial basis

Two client boundary defects are fixed. Realized invoice/credit currency must match its own frozen opportunity; merely appearing elsewhere in the forecast is insufficient. Historical requests now reject malformed UTC instants and a business cutoff after the recorded cutoff before calling the provider.

The focused platform suite passes 6/6 and scoped analysis reports no issues. The new cutoff tests verify that invalid requests make zero RPC calls. Existing realized mapping cases now include currency substitution between two currencies both present in the same frozen forecast. These are client regression results; no new installed provider execution occurred.

The offline financial auditor reproduces all nine captured ratio arithmetic rows with BigInt and reproduces six base numerator/denominator pairs from the two retained statement summaries. Eight controlled cases check exact rounding, values beyond binary integer precision, unavailable denominators, scope/period/currency drift, operand tampering, missing formulas and provenance. The source observations remain dated 13 October 2026. Their administrative synthetic source attribution is retained.

All 15 assigned requirements remain open. The full statements and exact next evidence are in [area2-report.json](area2-report.json). The retained statement files contain summaries rather than canonical account-level publications, so their canonical statement hashes and the classified operands cannot be independently reconstructed. Genuine complete source manifests, late commit/backfill evidence, realized cohorts, obligation residuals and actual scenario freeze/reopen with no ledger effects are still required.

No live queries, credential reads, migrations, posting, runtime renewal, exports, health probes or scheduler actions were performed by this area.

The first focused test failure is preserved: its malformed-input expectation used FormatException while the shared UTC parser correctly emits DomainError with VALIDATION_ERROR. The corrected final suite passes. SDK sandbox lockfile and telemetry failures are also retained in the report; the authorized reruns succeeded.

The review used the SQL Database Assistant and Supabase skills. Current [Supabase changes](https://supabase.com/changelog) and [RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security) were consulted. Installed authorization remains authoritative; client hashes and this audit do not grant access.
