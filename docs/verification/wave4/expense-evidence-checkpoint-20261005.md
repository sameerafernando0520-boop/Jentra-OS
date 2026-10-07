# Protected expense evidence checkpoint

2026-10-05. Full separate SQL/Edge/domain/gateway/encrypted recovery/native source
is implemented under contract67 and integrated into finance's frozen expense
proofs. Root owns real main-provider wiring and the two candidate config entries.
No migration or function was installed/deployed; no business retention policy or
worker was activated. No Git mutation was performed.

## Actual verification

| Evidence | Actual result |
| --- | --- |
| Integrated finance/protected evidence SQL | 180 assertions, strict rollback. Final executed query SHA256 `853B4CC3EDB48F3B2AE4421CADECCC0052C3BD192425F5F25C262971030F4B5E`; provider `990077DBED0E07E74EB593E77A51CC7BA0B62B5AB50C29700A39D4F235D67ABA` appears byte-for-byte in the executed query; finance source `0430F55698A28EE7C26A609BC982A96CBC20319D204C3D5546F9A6AE4272EFEF`. Finance owner preserved query/result/hash artifacts from the same execution. |
| Domain | 8 passed, `expense-evidence-domain-final-20261005.log`. |
| Gateway/encrypted recovery | 9 + 7 = 16 passed, `expense-evidence-platform-final-20261005.log`; exact owned source was copied/hash-matched to the authorized isolated checkout. |
| Native controller/widget | 14 passed with golden update and final no-update; `expense-evidence-native-update-final-20261005.log` and `expense-evidence-native-no-update-20261005.log`. Two subsequent private image regressions bring the current suite to 16; fresh execution is pending the serialized SDK slot. |
| Edge handler | 14 passed, `expense-evidence-edge-final-20261005.log`, Node test isolation disabled because child spawning is restricted. |
| Trusted Edge entrypoints | Both actual `index.ts` checks passed with pinned Deno 2.6.0/TypeScript 5.9.2 and their separate `deno.json`; `--no-lock`, temporary module cache, no deployment. Runtime and each entrypoint logs retained. |
| Focused analyzer | No issues across the ten owned model/gateway/store/controller/screen/test files in `expense-evidence-analyzer-final-20261005.log`, before the final safe image errorBuilder addition. |
| Rendered previews | Both 1024x720, 200% text light/dark images individually inspected and copied into owned goldens. Light SHA256 `450A3154E39D9F59BB0B26CBE4BA1A587AED6CD44E45CE3223A281D0D1E65916`; dark `2E97F13A8E816617F0A6EE056FE8E42FA53848C902BA2B839FABA921753FCF8E`. Verified content controls fit with readable loaded fonts. Visual inspection is not user signoff. |

The initial independent provider run actually passed 145, against then-current
108 finance assertions plus 37 provider assertions. Its exact query/result/source
binding is preserved; it is not relabeled 147 or 180. The final 180 composed query
adds current finance assertions, historical retained proof reads, scope/policy
regressions and actual attached expense create/submit/independent approve/post/
reverse, stale worker/proof and current own-receipt/replay permission checks.

## Findings resolved and failure preservation

Root review found current business status missing from issued-ticket authority,
branch authority incorrectly sufficient for an entity policy, and policy recovery
missing the entity namespace. SQL checks now revalidate tenant trial/active and
active entity/branch; entity-wide retention authority applies to policy create,
replay, own receipt and null-project recovery access. Tests issue actual tickets
then deactivate each business scope, and deny branch-only policy access/replay.
Native tests recreate controllers after lost policy response and expired body,
retain original immutable IDs/minimal receipt and prohibit a replacement policy.

Native verification found that exact document field validation had incorrectly
rejected minimal policy confirmations in both domain and gateway. Action-specific
exact sets now accept the actual policy confirmation and reject injected document
fields; domain/gateway/native regression checks pass. The initial native11/2-fail
log and four diagnostic logs remain preserved. A cached encryption key made the
first cleanup failure injection ineffective; the corrected test uses an actual
SQLite DELETE-abort trigger, verifies confirmed server result survives failure,
then reconciles without a second dispatch.

Finance review identified a selected retired original proof that could not be
detached during rejected expense correction. Current management authority now
permits explicit deselection, while new selection of nonactive documents rejects.
The native regression passes. View-only selection, late picker/read disposal and
export authority loss after byte fetch are independently covered. The final image
decoder errorBuilder keeps a malformed but original hash-verified image from
throwing an unhandled Flutter exception; a scoped MemoryImage evicts private
decoded content when closed, replaced or disposed. Both added regressions await
final serialized execution. Finance Standards found that a growing selected file
could exceed the memory bound before `readAsBytes` rejected it. The picker now
uses a length-plus-one bounded stream, early excess-chunk rejection/cancellation,
exact snapshot length and post-read size verification. Four bounded-reader
regressions are saved and await the same serialized platform test slot.

## Source binding and next work

`expense-evidence-source-hashes-final-20261005.json` captures 26 provider/client/
contract/config/preview files for the actual 14-test final run, with all package/
app/test/golden bytes matched to the isolated source. The later image preview
change affects only the owned screen and native test, so those two manifest entries
must be recaptured with the fresh 16-test execution, including the new bounded
reader source and its four tests. Other source remains frozen.
Finance has requested independent Standards/security review of this final vertical;
root's independent Spec review is `expense-evidence-spec-review-20261005.md`.

The SDK is serialized: finance currently owns its run, then native16/platform20
verification, then service asset client. No overlapping Flutter build/test is
authorized by this checkpoint. Direct read-only review may continue.

The complete undeployed adapter still needs reviewed concrete installation scope,
role/plan permission provisioning, chosen real retention purpose/period, worker
secret/artifact configuration, scheduled private probe and leased purge activation,
post-install physical byte/hold/purge/ACL tests, authenticated native acceptance,
actual Credential Manager restart, real separate-session contention/load, full
current-source app build and owner signoff. Synthetic rollback fixtures and local
previews do not close those gates.
