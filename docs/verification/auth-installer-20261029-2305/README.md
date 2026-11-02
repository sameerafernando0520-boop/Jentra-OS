# Auth and native installer verification — 29 October 2026

Version **0.3.2+2305 Development**. The collector refuses to publish its final
report or handoff until matching Windows/web identities, native staging, clean
analysis, test logs and both Firebase preview/live proofs pass.

Run `node docs/verification/auth-installer-20261029-2305/collect.mjs` once from
the repository root after the release checks. Existing reports/artifacts are
never overwritten. The frozen build directories and earlier failed diagnostics
remain under `build/`.

`verification.json` records exact source, artifact and served-content SHA-256,
the Firebase version and prior rollback version. The four controlled auth
scenarios exercise actual compiled UI while intercepting all backend traffic;
no real registration, mail, tenant record or push is created. Browser screenshots
show the final live sign-in and account form.

The actual native installer runs only in workspace staging mode. All 48 runtime
and manifest files must match; registration, shortcuts and user-profile install
must stay untouched. The unsigned installer still needs acceptance on the other
PC. The exact cause of the original Setup.exe symptom remains unconfirmed.

Hosted Auth changes are limited to the owner's approved web/native redirect
repair. Public Gmail SMTP fields were prepared, with credential entry and Save
left to the owner. SMTP delivery, a real verified-account session, production
signing and company launch acceptance are not certified by this report.

The native installer, portable Windows ZIP, optional Web ZIP, instructions and
checksums are copied to `dist/Jentra-OS-0.3.2-2305-Development`. Firebase serves
the web client and portable ZIP. Its Spark plan rejects raw executable uploads;
billing and the employee Hosting site were not changed.
