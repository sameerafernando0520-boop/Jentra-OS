select pg_temp.actor('creator');
insert into procurement_test_results select has_table('core','wave3_notification_subscriptions',
 'private configured Wave 3 in-app recipients');
insert into procurement_test_results select has_function('api','configure_wave3_notification_subscription',
 'versioned authenticated recipient configuration');
insert into procurement_test_results select has_function('core','wave3_notify_command',
 'atomic in-app notice fan-out');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'core.roles.manage')
 on conflict do nothing;
create function pg_temp.configure_notice(enabled boolean,version bigint,command_name text) returns jsonb
 language sql as $$
 select api.configure_wave3_notification_subscription(
  pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
  pg_temp.fid(command_name||'.command'),pg_temp.fid(command_name||'.key'),statement_timestamp(),
  jsonb_build_object('id',pg_temp.fid('notice.posting'),'recipient_id',pg_temp.fid('creator'),
   'event_class','posting','enabled',enabled),version)$$;
create temp table wave3_notice_config as select pg_temp.configure_notice(true,0,'notice.enabled') body;
insert into procurement_test_results select is((select body#>>'{entity,version}' from wave3_notice_config),
 '1','recipient configuration starts at version one');
insert into procurement_test_results select is(pg_temp.configure_notice(true,0,'notice.enabled'),
 (select body from wave3_notice_config),'recipient configuration replays the same receipt');
insert into procurement_test_results select throws_ok(
 $$select pg_temp.configure_notice(false,0,'notice.stale')$$,'40001',null,
 'stale recipient configuration cannot overwrite active selection');
insert into procurement_test_results select throws_ok(
 $$select api.configure_wave3_notification_subscription(pg_temp.fid('tenant'),pg_temp.fid('entity'),
  pg_temp.fid('branch'),pg_temp.fid('notice.invalid.command'),pg_temp.fid('notice.invalid.key'),
  statement_timestamp(),jsonb_build_object('id',pg_temp.fid('notice.invalid'),
   'recipient_id',pg_temp.fid('creator'),'event_class','unknown','enabled',true),0)$$,
 '22023','NOTIFICATION_SUBSCRIPTION_INVALID','unknown event class is rejected');
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,
 actor_id,request_id,command_id,correlation_id) values
 (pg_temp.fid('tenant'),'procurement.receipt.posted','goods_receipt',pg_temp.fid('landed.receipt'),
  '{}'::jsonb,pg_temp.fid('creator'),pg_temp.fid('notice.source.request'),
  pg_temp.fid('notice.source.command'),pg_temp.fid('notice.source.request')),
 (pg_temp.fid('tenant'),'procurement.receipt.posted','goods_receipt',pg_temp.fid('landed.receipt'),
  '{}'::jsonb,pg_temp.fid('creator'),pg_temp.fid('notice.source.request'),
  pg_temp.fid('notice.source.command'),pg_temp.fid('notice.source.request'));
insert into core.command_receipts(tenant_id,actor_id,idempotency_key,command_name,request_id,
 request_hash,response,command_id,correlation_id,aggregate_type,aggregate_id,
 legal_entity_id,branch_id,source_context,completed_at)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator'),pg_temp.fid('notice.source.key'),
 'procurement.receipt.post',pg_temp.fid('notice.source.request'),repeat('a',64),'{}',
 pg_temp.fid('notice.source.command'),pg_temp.fid('notice.source.request'),'goods_receipt',
 pg_temp.fid('landed.receipt'),pg_temp.fid('entity'),pg_temp.fid('branch'),'{}',clock_timestamp());
insert into procurement_test_results select is((select count(*) from workflow.notifications
 where tenant_id=pg_temp.fid('tenant') and command_id=pg_temp.fid('notice.source.command')
  and recipient_id=pg_temp.fid('creator') and notification_type='wave3.posting'),
 1::bigint,'two same-class outbox events create one atomic in-app notice');
insert into procurement_test_results select is((select aggregate_id from workflow.notifications
 where command_id=pg_temp.fid('notice.source.command') and notification_type='wave3.posting'),
 pg_temp.fid('landed.receipt'),'notice keeps the permitted source identity for checked navigation');
insert into procurement_test_results select ok(not exists(select 1 from workflow.notifications
 where command_id=pg_temp.fid('notice.source.command')
  and (body like '%9007199254%' or source_context ? 'amount')),
 'notice contains no raw amount or private event payload');
select pg_temp.configure_notice(false,1,'notice.disabled');
insert into procurement_test_results select is((select version from core.wave3_notification_subscriptions
 where id=pg_temp.fid('notice.posting')),2::bigint,
 'disabling a subscription preserves versioned configuration history');
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,
 actor_id,request_id,command_id,correlation_id)
 values(pg_temp.fid('tenant'),'procurement.receipt.posted','goods_receipt',pg_temp.fid('landed.receipt'),
 '{}'::jsonb,pg_temp.fid('creator'),pg_temp.fid('notice.off.request'),
 pg_temp.fid('notice.off.command'),pg_temp.fid('notice.off.request'));
insert into core.command_receipts(tenant_id,actor_id,idempotency_key,command_name,request_id,
 request_hash,response,command_id,correlation_id,aggregate_type,aggregate_id,
 legal_entity_id,branch_id,source_context,completed_at)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator'),pg_temp.fid('notice.off.key'),
 'procurement.receipt.post',pg_temp.fid('notice.off.request'),repeat('b',64),'{}',
 pg_temp.fid('notice.off.command'),pg_temp.fid('notice.off.request'),'goods_receipt',
 pg_temp.fid('landed.receipt'),pg_temp.fid('entity'),pg_temp.fid('branch'),'{}',clock_timestamp());
insert into procurement_test_results select is((select count(*) from workflow.notifications
 where command_id=pg_temp.fid('notice.off.command')),0::bigint,
 'disabled subscription receives no later notice');
set local role authenticated;
insert into procurement_test_results select throws_ok(
 $$select count(*) from core.wave3_notification_subscriptions$$,'42501',null,
 'desktop role cannot enumerate private recipient configuration');
reset role;

-- Exercise actual finalization, access changes and late transaction rollback.
create function pg_temp.emit_notice(label text,topic text default 'procurement.receipt.posted') returns jsonb
 language sql as $$select core.wave3_finish_command(pg_temp.fid('tenant'),'procurement.test.notice',
 pg_temp.fid(label||'.command'),'goods_receipt',pg_temp.fid('landed.receipt'),pg_temp.fid(label||'.key'),
 repeat('c',64),null,jsonb_build_object('id',pg_temp.fid('landed.receipt')),pg_temp.fid('entity'),
 pg_temp.fid('branch'),'{}',jsonb_build_object('to_status','posted'),
 jsonb_build_array(jsonb_build_object('topic',topic,'payload','{}'::jsonb)))$$;
select pg_temp.configure_notice(true,2,'notice.reenabled');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant')
 and role_id=pg_temp.fid('creator.role') and permission_code='inventory.cost.view';
select pg_temp.emit_notice('notice.cost.denied');
insert into procurement_test_results select is((select count(*) from workflow.notifications
 where command_id=pg_temp.fid('notice.cost.denied.command')),0::bigint,
 'cost source notification is withheld after recipient cost permission is revoked');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.cost.view');
select pg_temp.emit_notice('notice.finalizer');
insert into procurement_test_results select is((select count(*) from workflow.notifications
 where command_id=pg_temp.fid('notice.finalizer.command')),1::bigint,
 'real source-command finalizer creates one notice atomically');
insert into procurement_test_results select is(core.wave3_notification_classes('procurement.receipt.reversed'),
 array['reversal'],'receipt reversal is not misclassified as a new posting');
insert into procurement_test_results select is(core.wave3_notification_classes('inventory.sales_order.reserve'),
 array['allocation'],'stock reserve topic maps to allocation');
insert into procurement_test_results select is(core.wave3_notification_classes('workflow.operational_approval.decide'),
 array['decision'],'approval decision topic maps to decision');
insert into procurement_test_results select is(core.wave3_notification_classes('finance.budgets.variance.generated'),
 '{}'::text[],'report generation is not misclassified as a business exception');

select api.configure_wave3_notification_subscription(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('notice.approver.command'),pg_temp.fid('notice.approver.key'),
 statement_timestamp(),jsonb_build_object('id',pg_temp.fid('notice.approver'),
 'recipient_id',pg_temp.fid('approver'),'event_class','posting','enabled',true),0);
update core.memberships set status='suspended' where tenant_id=pg_temp.fid('tenant') and user_id=pg_temp.fid('approver');
insert into procurement_test_results select lives_ok(
 $$select api.configure_wave3_notification_subscription(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('notice.suspended.disable.command'),pg_temp.fid('notice.suspended.disable.key'),
 statement_timestamp(),jsonb_build_object('id',pg_temp.fid('notice.approver'),
 'recipient_id',pg_temp.fid('approver'),'event_class','posting','enabled',false),1)$$,
 'administrator can disable a subscription after recipient suspension');
insert into procurement_test_results select throws_ok(
 $$select api.configure_wave3_notification_subscription(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('notice.suspended.enable.command'),pg_temp.fid('notice.suspended.enable.key'),
 statement_timestamp(),jsonb_build_object('id',pg_temp.fid('notice.approver'),
 'recipient_id',pg_temp.fid('approver'),'event_class','posting','enabled',true),2)$$,
 '42501','NOTIFICATION_RECIPIENT_UNAVAILABLE','suspended member cannot be enabled');
update core.memberships set status='active' where tenant_id=pg_temp.fid('tenant') and user_id=pg_temp.fid('approver');

select api.configure_wave3_notification_subscription(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('notice.due.config.command'),pg_temp.fid('notice.due.config.key'),
 statement_timestamp(),jsonb_build_object('id',pg_temp.fid('notice.due'),
 'recipient_id',pg_temp.fid('creator'),'event_class','due','enabled',true),0);
create function pg_temp.scan_due(label text,cutoff date default '2026-09-29') returns jsonb
 language sql as $$select api.scan_wave3_due_notifications(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid(label||'.command'),pg_temp.fid(label||'.key'),statement_timestamp(),
 jsonb_build_object('kind','AP','as_of',cutoff),null)$$;
create temp table wave3_due_scan_result as select pg_temp.scan_due('notice.due.first') body;
insert into procurement_test_results select ok((select (body#>>'{entity,emitted}')::int>0 from wave3_due_scan_result),
 'bounded time scan creates notices for due positive AP residuals');
insert into procurement_test_results select is(pg_temp.scan_due('notice.due.first'),
 (select body from wave3_due_scan_result),'due scan uncertain outcome replays the original receipt');
insert into procurement_test_results select is(pg_temp.scan_due('notice.due.repeat')#>>'{entity,emitted}',
 '0','repeated scan with a fresh command cannot duplicate source/cutoff notices');
insert into procurement_test_results select ok(not exists(select 1 from workflow.notifications n
 join finance.open_items o on o.tenant_id=n.tenant_id and o.source_id=n.aggregate_id
 where n.notification_type='wave3.due' and n.command_id=pg_temp.fid('notice.due.first.command')
 and (o.original_amount<0 or (finance.flow_residual(o.tenant_id,o.id,'2026-09-29')->>'amount')::numeric<=0)),
 'credits and settled dated residuals create no due notice');
insert into procurement_test_results select throws_ok(
 $$select pg_temp.scan_due('notice.due.future',(clock_timestamp() at time zone 'UTC')::date+1)$$,
 '22023','NOTIFICATION_DUE_SCAN_INVALID','future due cutoff is rejected');

create function pg_temp.reject_notice_receipt() returns trigger language plpgsql as $$begin
 if new.command_id in(pg_temp.fid('notice.late.command'),pg_temp.fid('notice.due.late.command')) then
 raise exception using errcode='P0001',message='SYNTHETIC_LATE_RECEIPT_FAILURE';end if;return new;end$$;
create trigger z_wave3_synthetic_notice_failure after insert on core.command_receipts
 for each row execute function pg_temp.reject_notice_receipt();
insert into procurement_test_results select throws_ok($$select pg_temp.emit_notice('notice.late')$$,
 'P0001','SYNTHETIC_LATE_RECEIPT_FAILURE','late receipt failure rolls back atomic notice fan-out');
insert into procurement_test_results select throws_ok($$select pg_temp.scan_due('notice.due.late','2026-09-28')$$,
 'P0001','SYNTHETIC_LATE_RECEIPT_FAILURE','late receipt failure rolls back a due scan');
insert into procurement_test_results select ok(
 not exists(select 1 from workflow.notifications where command_id in(pg_temp.fid('notice.late.command'),pg_temp.fid('notice.due.late.command')))
 and not exists(select 1 from core.outbox_events where command_id in(pg_temp.fid('notice.late.command'),pg_temp.fid('notice.due.late.command')))
 and not exists(select 1 from core.command_receipts where command_id in(pg_temp.fid('notice.late.command'),pg_temp.fid('notice.due.late.command'))),
 'late failure retains neither notice, event nor receipt');
drop trigger z_wave3_synthetic_notice_failure on core.command_receipts;
insert into procurement_test_results select ok(
 (api.wave3_notification_admin_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'subscriptions')->'items') @>
 jsonb_build_array(jsonb_build_object('id',pg_temp.fid('notice.due'),'event_class','due','enabled',true,'version',1)),
 'administrator reads exact scoped subscription versions');
insert into procurement_test_results select ok(not exists(
 select 1 from jsonb_array_elements(api.wave3_notification_admin_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'members')->'items')r
 where r->>'status'<>'active' or r ? 'email' or r ? 'private_hr'),
 'recipient picker exposes only active scoped membership identities without private fields');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok(
 $$select api.wave3_notification_admin_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'subscriptions')$$,
 '42501',null,'outsider cannot inspect notification configuration');
select pg_temp.actor('creator');
