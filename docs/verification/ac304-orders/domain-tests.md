# Domain regression evidence

The full `packages/jentra_domain` Dart test suite passed on 2026-09-07 with **78
tests**. Output was captured in the session tool results. This includes five new
AC-304 order workspace tests and five tests from concurrent receivables work.
The baseline-plus-AC-304 domain count is 73.

The AC-304 tests cover exact order draft codecs, separate credit currencies,
required order products, date validation and bounded/validated list queries.
