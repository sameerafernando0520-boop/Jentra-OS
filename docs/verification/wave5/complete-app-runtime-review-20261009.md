# Jentra OS — full backend and Supabase runtime review, October 9

Prepared for one owner decision. **Nothing new is installed, provisioned, activated or deployed.** The owner selected the existing Supabase project and confirmed the six account labels. Those selections do not approve the operations below. This concrete package supersedes the older unbound 28-file Node review.

Bundle SHA-256: **`93db987d8a6f2db65171f76b2897af4131ec9304c57b5b49d512495572b302f7`**. [Machine manifest](complete-app-runtime-review-20261009.json) contains all 500 scope UUIDs, permissions, plans, exact source hashes, deployment files and operation bounds. Any source, ledger, identity, URL or scope drift requires a refreshed review before the dependent operation.

## Decision requested

Approve the **71 exact missing migrations**, the six new Auth accounts, scoped 500-tenant synthetic bootstrap/source caps, four new synthetic plans, one bounded operator authority/grant, one standard Windows test profile/package, three new Vault secrets, one privately supplied model secret, two new Edge functions, three expiring scheduled jobs, the four same-project receiver paths and the bounded real MFA/delivery/export/contention/load run described here. Production, real billing, other destinations, existing acceptance stores/accounts and Git publication remain excluded. Runtime approval is separate from owner acceptance of the app.

## Verified baseline and effect

[Fresh post-rollback read](complete-app-live-after-final-20261009.json), 2026-10-09 11:10:43.511207+00: **43 migrations / 107 API functions**, 87 role-permission rows, one assignment, 28 plan entitlements and one membership. No proposed account, tenant, Vault key, Edge authority, cron/net table or candidate fixture remains. The [six installed migrations](installation-result-20261008.md) are excluded; their connector-assigned versions are not their original source timestamps.

The full app request uncovered **69 uninstalled repository dependencies**: 48 Wave 3, 13 Wave 4 and eight Wave 5. Two new hosted-runtime migrations bring this review to **71**. Expected ledger after only this installation: **114**. Installation changes shared database schemas/APIs/default registrations across waves. W3/W4 source bytes are preserved; their broader native/provider acceptance is not inherited from this review.

The full composition and exact setup/stop bodies pass **105 strict rollback assertions**. A separate **25-assertion full-schema bootstrap probe** verifies all 500 scopes, exact role mappings, payroll/correction/reimbursement date permissions, role isolation, AAL1 denial and the returned Auth-ID binding. It adds no permission-registration shim. Both probes use test-only Auth/policy shapes, end in rollback and make no HTTP call. **63 controlled worker tests** pass and both Edge entrypoints pass Deno checking; their imported JavaScript modules are exercised by the controlled tests, not TypeScript-checked. These gates are separate from installed SQL, real Auth and actual hosted delivery.

## Exact installation order

| Order | Filename | Owner | SHA-256 |
|---|---|---|---|
| 1 | 20260912152000_product_unit_conversions.sql | Wave 3 | `1245dd3f3bfca3c00afa4477da67e6a02655ef9f3e25a1c848e5ca3f769f526c` |
| 2 | 20260912153000_procurement_requisition_drafts.sql | Wave 3 | `9b751a04245677ca999b6e11a4b7935a2e577d5080961553df3af30161b49a2c` |
| 3 | 20260913001000_procurement_requisition_workflow.sql | Wave 3 | `05533f3c9b038cc1e023c35869a62b987810d776fbba805621678eaa787579d5` |
| 4 | 20260913002000_procurement_reference_options.sql | Wave 3 | `c56605aa3ab7fafe38dbab4777ca23f731e7a53fd9076ef30a1953fa49adc74c` |
| 5 | 20260913003000_procurement_sourcing.sql | Wave 3 | `d4f92c0fb5c6d24c48d4c21c7184ef042a635abb654c7a53c92129fbc3503d44` |
| 6 | 20260913004000_procurement_purchase_orders.sql | Wave 3 | `8a71252b8bf62a0a8a7325a4683ae770039cecd5c72dc30be131c428636e6795` |
| 7 | 20260913005000_procurement_order_workflow.sql | Wave 3 | `dedb4da3b59ca593a349ecaf4c77fc1adf5dd9e3e56d903726291f6e5e98c077` |
| 8 | 20260913006000_procurement_goods_receipts.sql | Wave 3 | `f38bc858ea03067f56f44208196312842484bd1263b4b9466dc58cb8a7220b76` |
| 9 | 20260913007000_procurement_supplier_bills.sql | Wave 3 | `9212e1dea7c9abcb0e3224ff37bc5a3e1495ea73128bb450f99ef79c4c93c722` |
| 10 | 20260914001000_procurement_supplier_settlement.sql | Wave 3 | `5b776e2dc0eb53a72fa51375f248ab24848768d3141c757233c7b97a4a654bf1` |
| 11 | 20260915001000_payable_allocation_corrections.sql | Wave 3 | `d175cf49fe16783e2d413d46167e99777904b804873e96dbc185992fc2625666` |
| 12 | 20260915002000_procurement_purchase_returns.sql | Wave 3 | `44292af187109e00c267a9be60b50a2de8243e97e421c0dee2f0bd7220e2acc6` |
| 13 | 20260916001000_inventory_transfers.sql | Wave 3 | `de1d6141109130d2c29a8d253966f3d934fa412821baa2ef893ac4691c263dc5` |
| 14 | 20260916002000_inventory_stock_counts.sql | Wave 3 | `90072604b03523e391fb12bd315032a4a4b968d28789ad0fbbe77a15d204b40b` |
| 15 | 20260918001000_inventory_reservation_release.sql | Wave 3 | `fb7782b9389615e6a02bcc335d958bba84caa2662c8a85fb295f76120cf9c3e6` |
| 16 | 20260919181407_inventory_receipt_provenance.sql | Wave 3 | `29becfdc43fef3bbc07a303eb8d79232f6ad3e77cd203d70dd2b82737b7b28e4` |
| 17 | 20260919185538_inventory_landed_value.sql | Wave 3 | `b13ac607ae1418bd860a5b5012a6adbfcb381217b76f256bd6ca313463eb6d1b` |
| 18 | 20260920202547_inventory_valuation_reports.sql | Wave 3 | `8d58f47813dbfac15882bc4c80dd64f650fdeb233f14a61b772468adbbceb0db` |
| 19 | 20260921041348_manual_journals.sql | Wave 3 | `8bea1e05398339b03979bf34569bcb76303c449923b346ece57da3d3d9e79bfd` |
| 20 | 20260922001000_ar_ap_control_reconciliation.sql | Wave 3 | `9de77b0e06887469a682292311d9cd161d598dcb6f871a34a712dbc38aaa5e26` |
| 21 | 20260923225202_bank_reconciliation.sql | Wave 3 | `6d914ceb736d69d2becf7130701509e1f617d8493798b5a8922fd9f268b7f6bd` |
| 22 | 20260924185321_wave3_period_governance.sql | Wave 3 | `c6fae72402c4f47e638d7fd9d74b0f05907937e2ac93568ef3c48edb51e67517` |
| 23 | 20260925002000_wave3_financial_statements.sql | Wave 3 | `7596ec3e5b1ac2b348e4b23371ff6c54818a5336d276fa3a03f14f1ecd5f17b6` |
| 24 | 20260925003000_wave3_cash_flow.sql | Wave 3 | `5c9a3b6db7e562ef8dfdc3ae590c26215e01e23d4cc838b88edd74a48b6e354e` |
| 25 | 20260925004000_wave3_budgets.sql | Wave 3 | `56e5ba5993f32297772a994fcdb39c595ee928de9081e6643a4478c4adf021af` |
| 26 | 20260926001000_wave3_tax_summary.sql | Wave 3 | `dcef36d0dcbf6b5277e6a79f625314d7595434cd88ced42271baa1cfa86b4969` |
| 27 | 20260926002000_wave3_tax_summary_hardening.sql | Wave 3 | `7976c8c944fd776729e4c67949706c1265bb0b5df04b076e83db301e8164ddee` |
| 28 | 20260926003000_wave3_tax_control_reconciliation.sql | Wave 3 | `51fb81ab482fdd6e2091ed46add2e2efa0c377528950393469ef721f081fe17b` |
| 29 | 20260926005000_wave3_governed_journal_tax.sql | Wave 3 | `78ae3cf5ee32b220f164431bdc0891dc5f87e04c7eeb079ae5665a9462ee2910` |
| 30 | 20260926006000_wave3_tax_control_movements.sql | Wave 3 | `41c09e5c0f8b6e40c1fca225e4f04196101b1012ebb88ef954234eee4c1e682d` |
| 31 | 20260926007000_wave3_grni_control_reconciliation.sql | Wave 3 | `b1864d4ac1612ebfc54439873ef5c8afab790051cf399869f55bc8ba4ff67f02` |
| 32 | 20260926008000_wave3_close_control_review.sql | Wave 3 | `654fadae87a9b0b027d20aec58ce32ff0fe52a19f024e5182e4b24e5dc2da0ba` |
| 33 | 20260926009000_wave3_governed_report_exports.sql | Wave 3 | `85238e684c967e8377221e55f911fcb9dfa64e7696110ee28eacffe8b6586386` |
| 34 | 20260926010000_wave3_financial_dimensions.sql | Wave 3 | `34f530f465bc21eff2fd0d137c4fa4b7a8a54d9b82401d91f20110e9f055c900` |
| 35 | 20260926160000_wave4_calendar_resolution.sql | Wave 4 | `6abd4dceddbb3124b4bfa01efd97ecafabd59f03ee1f85f48b5bc2a2f5685053` |
| 36 | 20260926161000_wave4_organization.sql | Wave 4 | `6f682652564a030e8a3a6960999aa9c51aa96486ab0f7219d4347f5445e31c45` |
| 37 | 20260927001000_wave3_control_read_plan.sql | Wave 3 | `bea514edc6178a914c8c7ed3881c1a007bc01760ad60772a4549cb4c41499e49` |
| 38 | 20260927200629_wave3_operational_evidence.sql | Wave 3 | `50a0ab28a3573a0bacc0415450e40ddb9deed5fd98196ee49df17e4357dba8f6` |
| 39 | 20260927200703_wave3_historical_controls.sql | Wave 3 | `4d135f473782c8f6fa776fe2cb3190efc0bc34bf6e88f629968c3a0b86743990` |
| 40 | 20260927200706_wave3_inventory_extensions.sql | Wave 3 | `a89834cd135096cf380e5f0446867c5a3b8b6c5c62f63e0f59011943e9e85eea` |
| 41 | 20260928001000_wave3_posted_journal_evidence.sql | Wave 3 | `1c0808dcdb36ebba8d320b1bf344c514e0c1ed7d23cf3e01581364adc219c4f5` |
| 42 | 20260928082234_wave4_attendance_intervals.sql | Wave 4 | `21cb1745977492f343f2992ccc915400f9320a82957f342d943e36a50db60ad6` |
| 43 | 20260928083449_wave4_leave_ledger.sql | Wave 4 | `1fbdd603a68f1962291c85a90739f599ee629fef27e5714ee6c00e8a0e37d4b3` |
| 44 | 20260929001000_wave3_notifications.sql | Wave 3 | `ec673056482b7219c4e983bc602bc05cf35ba3f0d6315bead6f5b0f27ea8d2e0` |
| 45 | 20260930001000_wave3_landed_extensions.sql | Wave 3 | `b472394fcfff0cd7d0d8e2f123e503c6a95ea6521169af62807cafb6bed9718d` |
| 46 | 20260930002000_wave3_count_partitions.sql | Wave 3 | `18e77c3bb7a9904e96650daa08eec5136758fc5e2d52cab03f6394d97c235613` |
| 47 | 20260930003000_wave3_stock_disposition.sql | Wave 3 | `6dc6b2a9bddafa05b263aeb44f0c1ac0e2c68bcd1424869edd8a141e999dad83` |
| 48 | 20260930004000_wave3_dashboard_metrics.sql | Wave 3 | `c915ac0a5bb6367f22ac83008a1a8fc00db9829978fa0cab8d621865b19dad4d` |
| 49 | 20260930005000_wave3_observability.sql | Wave 3 | `9afecc2a25596b7af50aa099fb0b9ee6fc5c916be06dd10eb52c023c5920031d` |
| 50 | 20260930070000_wave4_synthetic_payroll.sql | Wave 4 | `5517cc4559c3f91901525b38ec8fbf03633da49c587a0d034a885405a43465b2` |
| 51 | 20260930070500_wave4_clock_batches.sql | Wave 4 | `6775123b8ef94c61572ebe2c321557a5b0ab3eb976189115da14a374145baffd` |
| 52 | 20260930071000_wave4_fixed_assets.sql | Wave 4 | `d76ab9fef3720aea51de71288defb6fdae8fa93d82fffb83ecc49566fbbb5bf8` |
| 53 | 20261001080000_wave4_projects_time.sql | Wave 4 | `52ca0ba293d0a621304e01135db1424e69ebff579f14712b6b6c29d8c031e740` |
| 54 | 20261001090000_wave4_service.sql | Wave 4 | `28de902e665845c5eb4d26e0a8b3db621a76ccd908d11987126a9932a5679b84` |
| 55 | 20261001100000_wave4_project_expenses_billing.sql | Wave 4 | `0430f55698a28ee7c26a609bc982a96cbc20319d204c3d5546f9a6ae4272efef` |
| 56 | 20261001110000_wave4_payroll_corrections.sql | Wave 4 | `709170a703a5fd6808ba15de27a4b6cfcb33470da977203b960e2d04e67437cf` |
| 57 | 20261002080000_wave4_project_payroll_impacts.sql | Wave 4 | `19a784b4405288cbb4c9fa1403ab4eda52ae75b76712a85e739431bf1dd7ef54` |
| 58 | 20261003090000_wave3_negative_stock_policy.sql | Wave 3 | `b11c16acddee4cf02a7f706f7e0ff991cbebdd4b5c6d0e02412e657c77334959` |
| 59 | 20261004090000_project_milestones.sql | Wave 3 | `683fa20c6d5e118f0496bf21f1a117e33686340da2b407adaf1e1e5e06e93fd1` |
| 60 | 20261005090000_service_asset_equipment.sql | Wave 3 | `d4723bd8025e44ccdc651e6feab21e8ae939f4e2c850a14357453be3e24ca77e` |
| 61 | 20261005120000_wave4_project_expense_evidence.sql | Wave 4 | `990077dbed0e07e74eb593e77a51cc7ba0b62b5ab50c29700a39d4f235d67aba` |
| 62 | 20261008090000_wave5_historical_pipeline.sql | Wave 5 | `183a8688dd2c78a9e13032a165d2e1787b3d8f9dd4a15aee9b201eddf4767768` |
| 63 | 20261008093000_wave5_persistent_delivery.sql | Wave 5 | `1a636229a0749cf9d6334ae49efe8ff38627b6a2d1bb642789a28e86efd1c663` |
| 64 | 20261008100000_wave5_invocation_storage.sql | Wave 5 | `a9bdd3bf5b1593bd3253930c5a0cd6286f576b7f81161a5832919efbc585d6e8` |
| 65 | 20261008103000_wave5_dated_cash.sql | Wave 5 | `24b5ab44250ec5239ab2b942277cb104867d8e67288666c6297d4fa694e4b391` |
| 66 | 20261008110000_wave5_governed_export_adapter.sql | Wave 5 | `fbe68cc451f5044c03be7b68803ff2afbb858004109a5ee2319960d495e193ed` |
| 67 | 20261008113000_wave5_statement_classifications.sql | Wave 5 | `aad2c6cb360490ad653470858a389354c7016f2346b41e26bff8ac8294dc97c3` |
| 68 | 20261008120000_wave5_cash_payment_dates.sql | Wave 5 | `1463953b0fa76269740a732a59485ff3d160681fb2a6655eedbd8c0aeda42c8a` |
| 69 | 20261008123000_wave5_runtime_scope.sql | Wave 5 | `655df9b9bfa373dbbe8872ca802815f9c730c4f3543b72c7950640563e2da8dc` |
| 70 | 20261009120000_wave5_supabase_runtime.sql | Wave 5 | `9ceb592be38ebb6cff35b54e1d09c63d7e700cd95f8b52f3725966ea1d677164` |
| 71 | 20261009123000_wave5_supabase_schedule.sql | Wave 5 | `4a7a6404ca74f89f165802781782d9ddada1a9c776ac496690aee1609749ccbf` |

## Six confirmed accounts and access

| New label only | Roles | Purpose |
|---|---|---|
| w5-proposer@jentra.invalid | reader, financeAnchor, proposer | proposer |
| w5-approver@jentra.invalid | reader, financeAnchor, approver | approver |
| w5-executor@jentra.invalid | reader, financeAnchor, executor | executor |
| w5-billing-admin@jentra.invalid | billing | billing-admin |
| w5-operator@jentra.invalid | No tenant membership or role | operator |
| w5-foreign-member@jentra.invalid | foreignReader | foreign-member |

Auth Admin must create each account with a new random private password, email confirmation and **no email send**. The non-secret `jentra.w5.created_auth_ids` parameter must bind exactly the six labels to their actual returned Auth Admin IDs on each SQL connection; bootstrap/operator SQL refuses an absent, mismatched or reused identity. No fake Auth ID or JWT claim may serve as runtime evidence. Genuine TOTP enroll/challenge/verify and independent server session IDs are required. Password/TOTP refs stay `Jentra/W5/20261008/<label>/password` and `.../totp` in the isolated private credential store. Existing `test@test.com`, Jentra Acceptance Lab and other chats' credentials are untouched. A collision aborts; no existing label is adopted.

- **reader**: entity + RT1 branch; MFA=false; `analytics.view`, `workflow.process.view`, `crm.opportunities.view`, `finance.view`, `finance.receivables.view`, `sales.returns.view`, `procurement.bills.view`, `people.view`, `people.payroll.view`, `projects.view`, `projects.cost.view`, `ai.proposals.view`, `analytics.reports.view`.
- **financeAnchor**: entity; required by W3 statement/export parent checks; MFA=false; `finance.view`, `finance.reports.export`.
- **proposer**: entity + RT1 branch; MFA=false; `ai.proposals.manage`, `analytics.reports.manage`, `analytics.cash_dates.prepare`, `integrations.manage`, `finance.reports.export`, `people.payroll.settle`, `projects.expenses.settle`.
- **approver**: entity + RT1 branch; MFA=true; `ai.proposals.approve`, `analytics.cash_dates.approve`, `finance.classifications.approve`, `people.payroll.approve`, `people.payroll.correction.approve`, `projects.expenses.approve`.
- **executor**: entity + RT1 branch; MFA=true; `ai.proposals.execute`.
- **billing**: runtime + load-001 tenant only; MFA=true; `billing.read`, `billing.synthetic.manage`, `core.members.invite`.
- **foreignReader**: foreign entity + branch only; MFA=false; `analytics.view`, `workflow.process.view`, `crm.opportunities.view`.
- **loadReader**: load entity + branch only; MFA=false; `analytics.view`, `workflow.process.view`, `crm.opportunities.view`.
- **loadBilling**: load tenant only; MFA=false; `billing.read`.

Runtime: tenant `babe6c86-a764-4d3a-80a3-952a7c096c2c`, entity `caa2bb06-219a-47e9-8132-66d1271b0ffd`, branch RT1 `3813692c-f0de-4c69-8e34-d56cf54695b1`. RT2 `ed14db1b-8088-4e4d-89e0-34da88d2d769` is a denial target. Foreign member belongs only to `c1ae4d89-6379-45ef-8ee8-1779593eb8d9`. All 498 load tenants and their read/billing mappings are enumerated in the manifest. Scheduled worker authority covers **RT1 only for 24 hours**. No owner/all-permissions role is assigned. Explicit RPC MFA checks remain in force; the existing worker subscription delegation uses AAL1 and is not human MFA evidence.

## Scoped synthetic setup

[Bootstrap SQL](runtime-bootstrap-complete-app-20261009.sql) creates 500 tenants, 500 entities, 501 branches, 1997 memberships, 1003 roles and 2003 assignments. Its separate 25-check probe applies the full candidate schema, adds no permission shim and uses test-only Auth shapes. The runtime plan includes People plus the source-specific payroll/reimbursement settlement and independent approval permissions required by the cash-date contract; existing Wave 4 stores and RPC MFA checks are preserved. Synthetic activation allowlist is runtime and load-001 only; the scheduled worker applies runtime only. Trial windows last seven days from authoritative setup time.

| New plan | Seats | Enabled entitlements and limits |
|---|---|---|
| w5_runtime_20261008 | 5 | analytics=true; module.ai=true; module.projects=true; module.finance=true; quota.ai.tokens=8000; quota.webhook.deliveries=100; quota.integration.commands=200; module.people=true |
| w5_load_20261008 | 4 | analytics=true; quota.ai.tokens=0; quota.webhook.deliveries=0; quota.integration.commands=0 |
| w5_quota10_20261008 | 4 | analytics=true; quota.ai.tokens=10; quota.webhook.deliveries=10; quota.integration.commands=10 |
| w5_foreign_20261008 | 1 | analytics=true; quota.ai.tokens=0; quota.webhook.deliveries=0; quota.integration.commands=0 |

Per-tenant source maxima: 200 opportunities, 800 process events, 100 posted journals, 200 journal lines and 120 open items. Runtime-only maxima: 10 payroll obligations, four corrections, 10 reimbursements, three financial publications, one classification review, four cash scenarios and eight governed exports. Only new synthetic scopes receive business fixtures; caps do not themselves establish valid posted sources. No source body or private HR/receipt evidence enters generic analytics/command receipts. Invitation/seat races reuse the reviewed approver/executor labels in load-001 without email.

## Exact hosted worker, receiver and secrets

Worker: `https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime`. Receiver: `https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-receiver/accept`. Hosting is the owner-selected existing project, using [Supabase Cron, pg_net and Vault](https://supabase.com/docs/guides/functions/schedule-functions). No additional host or reverse proxy is required.

| Receiver mode | Exact subscription ID | URL ending | Behavior |
|---|---|---|---|
| accept | 58699e8a-28fd-4356-8cad-87ce46e17ddd | /wave5-receiver/accept | Save immutable exact-byte receipt before ACK |
| redirect | 2bdbd842-5b94-464b-85fc-22d722498831 | /wave5-receiver/redirect | Authenticate committed source, return 307 without ACK |
| timeout | 0961e194-dc0b-4632-8c2d-65686fc9f111 | /wave5-receiver/timeout | Save receipt, then delay 12s; unknown worker outcome requires review |
| reject | 360e7a9d-08a5-4349-854f-c2343ce2ff5d | /wave5-receiver/reject | Authenticate committed source, return 503 without ACK |

The two exact [runtime](supabase-deploy-wave5-runtime-20261009.json) and [receiver](supabase-deploy-wave5-receiver-20261009.json) upload payloads include entrypoints, Deno configuration and every relative dependency. Both set `verify_jwt=false` because their bodies implement the listed schedule/credential/caller-JWT or HMAC authentication. This is explicitly reviewed custom authentication; an anonymous request cannot issue a tick, command or receipt.

[Prepared setup](supabase-runtime-setup-20261009.sql) generates only three fresh 32-byte Vault values: `jentra-w5-runtime-20261009-schedule`, `...-delivery-v1`, `...-delivery-v2`. Existing secret values are never queried. HMAC refs are `w5/runtime/20261008/delivery/v1` and `.../v2`; rotation occurs through the real MFA API. The exact public build key is checked by SHA, not privately provisioned. Platform-injected service/anon variables remain on the Edge server. `W5_OPENAI_API_KEY` must be supplied privately to this project after approval; no secret value belongs in a chat, artifact, desktop binary or log. Auth Admin/private runtime execution likewise needs an owner-authorized private context; connected SQL alone does not create real Auth users.

The three jobs `jentra-w5-20261009-delivery`, `...-subscription`, `...-health` run once per minute, at most 4320 scheduled requests over 24 hours. Delivery batch <=3, subscription page <=50; Edge request budget 65s and tick lease 90s. Database leases prevent overlapping jobs of the same kind across isolates. HTTP concurrency <=8 is per isolate; global quota/lease checks are persistent. Source authority is rechecked before sending and receiving. Quota is 100 delivery units with bounded attempts; this is not a claim of only 100 network attempts. No redirect is followed and uncertain sends cannot auto-retry. [Stop SQL](supabase-runtime-stop-20261009.sql) disables only this authority/scope and unschedules its three recorded IDs; unrelated jobs survive. Expiry performs the same scoped shutdown.

External credential: new private random value; only its SHA is registered through real MFA for `analytics.freeze_pipeline.v1`, exact RT1 and 24-hour expiry. Atomic throttle is 60/minute with 200-command quota. It has no generic dispatch or foreign/sibling authority.

Model: `openai.responses.v1`, `gpt-4.1-mini-2025-04-14`, policy revision 1, <=4 distinct persistent invocations, <=2000 reserved tokens each and 8000-token plan ceiling. Only the numeric `pipeline.current_weighted.v1` projection goes to the two named OpenAI Responses/token-count endpoints. No names/free text/receipt/HR bodies, tools, storage or background responses are enabled. Unknown outputs retain reservations. Actual provider token counts settle trusted usage. Native Control now implements the [reviewed request/recovery contract](../../blueprint/wave5/W5_REVIEWED_MODEL_NATIVE_CONTRACT.md): actor/scope-bound encrypted original invocation/usage IDs, exact parameter recovery, current source/access checks and explicit selection into the human proposal form. Selecting a suggestion issues no command; proposal, distinct MFA approval and executor remain separate. Fifteen gateway/control tests and 20 native model tests pass; authenticated provider usage remains unproved.

## Operator, native target and acceptance run

The separate operator has zero tenant membership. [Authority SQL](runtime-operator-authority-complete-app-20261009.sql) binds its returned Auth ID and limits it to the exact runtime tenant/reason for 45 minutes; a genuine MFA call issues a <=30-minute grant within that deadline. Foreign tenant, changed reason, longer deadline, different recipient and AAL1 are denied. No grant is inserted as a substitute for authenticated issuance.

The owner delegated native-target selection. The reviewed new standard Windows profile is `jentra-w5-runtime`, package path `C:\Users\Public\Documents\JentraWave5Runtime\20261009`, password ref `Jentra/W5/20261009/native-profile/password`. [Preparation script](../../../scripts/wave5/prepare_native_runtime_profile.ps1) requires exact review approval and verifies all source/release hashes before creating that one OS account and copying the ordinary release with private ACLs. Existing account/package collisions abort. The fresh [portable r5 preview/connected apps](windows-test-verification-20261009-r5.md) use separate runner identities and are available now. Both releases match 1056 selected desktop dependency inputs and 34 release files per app. Scoped analysis, 96 workspace/cash tests, six keyboard tests and two startup tests pass. Twelve cash and twelve model render variants at 200% text produce 60 and 24 images; eight cash and four model images plus the two native startup windows were inspected. Controlled images/dashboard/sign-in are separate from authenticated acceptance. Native keyboard focus was not acquired in the earlier own-window probe; no keys were sent and that gate remains open.

After approval: install and validate SQL; create/bind six real Auth accounts; provision only reviewed synthetic data/entitlements; obtain real independent MFA sessions; deploy exact Edge payloads and private configuration; register through MFA; run native dates/statements/scenarios/export download/reopen/revocation/restart; test actual model/delivery/rotation/replay; issue scoped operator grant; run concurrent races and bounded load. Do not change global Auth settings to make the harness pass.

Contention: two or more independently authenticated/trusted connections, barrier and actual overlap; 100 duplicate requests, quota-10 competing reservations, lease races, seat/activation races, exact original identities and committed before/after counts. Load: 500 tenants, 2000 distinct real sessions, 60s warmup +300s measurement, <=900s total and <=100000 timed requests; p95 reads <500ms, commands <1500ms, analytics <3000ms. Record actual tier/hardware/populations/errors; unsupported Auth/connection limits remain an unmet gate. Model/webhook calls are excluded from load. The operator is excluded from load sessions. Owner signoff is required for each of 109 Wave 5 IDs; the agent cannot sign for the owner.

## Remaining app work and decision boundary

The [remaining-work record](complete-app-remaining-work-20261009.md) distinguishes provider installation, private Auth/provider setup, authenticated native/export/worker behavior, independent contention/load, the 13 shared golden failures, broader W3/W4 provider acceptance and final owner release approval. Native model request/recovery is implemented as a tested candidate; its real provider path is not yet verified. The current Windows package is a test build. **Jentra OS and Wave 5 remain incomplete.**

The prior approval covers only the six already installed migrations. This new 71-file installation plus bootstrap/activation/secrets/OS profile/deployment/delivery/load requires one explicit approval of the bundle SHA above. No production rollout, real billing, unrelated data cleanup, blanket role grant, golden replacement, staging, commit or push is included.
