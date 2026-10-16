# Export adapter independent source review — a1

The frozen a1 candidate requires a correction before private use. Independent local checks executed 16 tests: 15 passed and one failed. PowerShell parsing found no errors; the candidate was never executed.

- **EXP-ADAPTER-001 (P1):** The final guard before DPAPI rechecks metadata, final review and time, but omits the child source and generated plan hashes. A child replaced after public preflight can receive private stdin. Recheck and preserve the exact reviewed execution inputs through launch. The peer regression fails `MISSING_FINAL_CHILD_SOURCE_HASH_CHECK`.
- **MGMT-TEMPLATE-001 (P2, adjacent source):** The new common management template expects `generatedPlan` and uniform preflight hash fields. Health/Scheduler use `planBinding`; Scheduler currently emits different preflight fields. The source template also has unresolved SHA markers and no Renewal launcher. These are source integration gaps, not observed live failures.

The pure builder reproduced candidate SHA `a0b0babf2cf2806016e5f7d5293df0079e370edd2c95d35f7b2e955dfed5f891` from unchanged predecessor `b01b6c20cb2819cb419fa10423bce37c0cba86b44ee7e2f5b9c0c9387d19be1f`. Public preflight ordering, exact A10/review selection, unchanged window serialization, legacy modes, ACL/time functions and public output paths passed the source checks. The independent JSON includes exact input bindings and the genuine failing test output. Root's separate 98-test suite, nine controls and 13 AST checks were read as evidence; this reviewer did not rerun those suites.

No private files, credentials, network, SDK, native UI, live SQL, adapter execution, renewal, exports, schedules, acceptance stores or Git operations were used or changed. This review grants no execution approval. Exact future human approval, fresh private readiness, installed readback and the remaining runtime gates must be completed separately.

