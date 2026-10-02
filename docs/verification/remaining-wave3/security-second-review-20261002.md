# Independent recovery and access review — 2026-10-02

This review reads the current shared checkout against contracts 32, 35, 49, 51,
55, 56, both current contract 57 files and 58. It is source review and synthetic
client verification preparation, not installed authentication, native acceptance,
real concurrency, load or owner signoff. Product edits are assigned explicitly to
their owning agents; concurrent Wave 4/5 and stock-opening acceptance are preserved.

## Actionable findings recorded before corrections

| Finding | Source at review | Required correction and ownership |
|---|---|---|
| Obsolete/disposed failures still assign current public error text. All eight procurement operation catches guard access invalidation but assign `error` unconditionally afterward. | `procurement_controller.dart:130`, `sourcing_controller.dart:121`, `purchase_order_controller.dart:137`, `goods_receipt_controller.dart:133`, `supplier_bill_controller.dart:140`, `supplier_payment_controller.dart:347`, `product_unit_controller.dart:126`, `purchase_return_controller.dart:101`. | Capture the originating epoch before work; suppress every obsolete/disposed presentation mutation while retaining original durable command failure handling. Assigned to final target reviewer. |
| Optional post-confirmation refresh catches swallow current permission/MFA/authentication denials and leave server evidence visible. They also assign generic errors after a disconnect/reconnect. | Same controllers at optional refresh catches: lines 386, 371, 489, 526, 520, 747, 310 and 387 respectively. | A current four-class typed denial clears all register, selected source, statement and allocation evidence and retains fixed typed guidance. An obsolete failure does nothing to replacement presentation. A durable known confirmation cannot be recreated or resent. Contract 56 clarified before the correction; assigned to final target reviewer. |
| Single-receipt landed posting's optional register failure can deny the replacement epoch. | `landed_value_controller.dart:407`, `clearDeniedAccess(e)` without the originating epoch guard. | Guard optional failure handling by original epoch; retain known confirmation and original encrypted input. Assigned to root. |
| Reservation release's optional save/refresh catch assigns stale presentation and suppresses current access denial. | `reservation_controller.dart:337`. | Preserve atomic input-only confirmation; reject obsolete failure and clear current server evidence on four-class denial. Assigned to root. |
| Receivables' optional register catch suppresses current typed access denial and updates message after access replacement. | `receivables_controller.dart:451`. | Check captured read epoch and invalidate current register/document evidence on definite denial without recreating the already completed request. Assigned to root. |

Line references above describe the reviewed pre-correction source. Final source
hashes and correction verification are appended when the owning checks complete.

## Reviewed boundaries with no further finding in this pass

Bank and period/FX transmission check their operation epoch after encrypted
save/sealing; durable completion precedes optional reads, and those optional
catches check the originating epoch before access invalidation. Their current
typed-denial handlers clear register/detail evidence. Manual journal captures an
epoch before preparation and atomically confirms an input-only recovery form
before optional detail/register reads; posted lines and attachment metadata are
excluded from offline recovery. Multi-receipt landed posting seals exact protocol
payloads and version before dispatch, checks the original epoch, and completes
its aggregate before any recovery/register read. Later inputs do not change an
already sealed command. These statements are source-level observations; current
client regression evidence and native acceptance remain distinct.

Quotation/order autosave retain classified `LOCAL_STORAGE_FULL` errors and dirty
navigation state. Failed-edit tracking blocks changing aggregates and explicit
discard remains user-directed. Exact stored input and sealed command identities
are retained. Procurement conflict comparison reads an exact scoped ID, validates
bounded lines and exact financial strings, displays added/removed material fields,
and binds the root-navigator dialog to the originating access epoch. Reload checks
that epoch before and after discard and does not open another aggregate after a
failed discard. No silent merge or destructive historical correction was found
in these reviewed changes.

## Verification in progress

`security_second_procurement_failure_epoch_test.dart` contains 56 synthetic
regressions across eight modules: obsolete reconnect/disposed read failures, each
of four current typed denials after known confirmation, and an obsolete optional
read denial. Each post-confirmation case verifies the original command was sent
exactly once and encrypted pending recovery was already cleared before the optional
read. RED/GREEN logs will be retained without changing approved goldens.
