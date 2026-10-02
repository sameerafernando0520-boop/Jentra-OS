-- Include after wave3_tracked_counts_test.sql in the synthetic inventory suite.
-- Uses that rollback fixture only; never persistent or acceptance-owned stock.
set constraints all deferred;
select pg_temp.actor('actor');
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,inventory_account_id,created_by,updated_by)
select pg_temp.fid(n),pg_temp.fid('t'),pg_temp.fid('e'),upper(n),n,'stocked',pg_temp.fid('u'),mode,
 pg_temp.fid('inventory-account'),pg_temp.fid('actor'),pg_temp.fid('actor')
from (values('partition.serial','serial'),('partition.lot','lot'),('partition.overflow','serial'))v(n,mode);
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
select pg_temp.fid(n||'.bal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid(n),qty,
 pg_temp.fid('actor'),pg_temp.fid('actor') from (values('partition.serial',501),('partition.lot',501),('partition.overflow',10001))v(n,qty);
insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
select pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(n||'.bal'),qty*2,
 pg_temp.fid('actor'),pg_temp.fid('actor') from (values('partition.serial',501),('partition.lot',501),('partition.overflow',10001))v(n,qty);
insert into inventory.serials(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
select pg_temp.fid(n||'.identity.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid(n),upper(n)||'-'||i,
 pg_temp.fid('actor'),pg_temp.fid('actor') from (values('partition.serial',501),('partition.overflow',10001))v(n,qty)
 cross join lateral generate_series(1,qty)i;
insert into inventory.lots(id,tenant_id,legal_entity_id,product_id,code,expiry_date,created_by,updated_by)
select pg_temp.fid('partition.lot.identity.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('partition.lot'),'PART-LOT-'||i,'2027-01-01',
 pg_temp.fid('actor'),pg_temp.fid('actor') from generate_series(1,501)i;
insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
select pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('partition.lot'),pg_temp.fid('partition.lot.identity.'||i),1,
 pg_temp.fid('actor'),pg_temp.fid('actor') from generate_series(1,501)i;
create function pg_temp.partition_payload(n text,p text) returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(n),'warehouse_id',pg_temp.fid('w'),'product_id',pg_temp.fid(p),'document_date',(clock_timestamp() at time zone 'UTC')::date,
 'reason','Review bounded physical count','offset_account_id',pg_temp.fid('variance-account'))$$;
create function pg_temp.partition_id(n text,i integer) returns uuid language sql as $$select md5(pg_temp.fid(n)::text||':count-partition:'||i)::uuid$$;
create function pg_temp.partition_doc(n text,i integer) returns jsonb language sql as $$
 select api.stock_count_detail(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.partition_id(n,i))$$;
create function pg_temp.partition_page(n text,a integer default 0,l integer default 50) returns jsonb language sql as $$
 select api.stock_count_partitions_page(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(n),a,l)$$;
create function pg_temp.partition_approve(n text,i integer) returns void language plpgsql as $$declare cid uuid:=pg_temp.partition_id(n,i);v bigint;begin
 perform pg_temp.actor('actor');select version into v from inventory.stock_counts where id=cid;
 perform pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',cid,'action','submit'),v);
 perform pg_temp.actor('approver');select version into v from inventory.stock_counts where id=cid;
 perform pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',cid,'decision','approved'),v);
 perform pg_temp.actor('actor');
end $$;
create function pg_temp.partition_post(n text,i integer,k text default null) returns jsonb language sql as $$
 select pg_temp.count_call('post_stock_adjustment',jsonb_build_object('document_id',pg_temp.partition_id(n,i)),
 (select version from inventory.stock_counts where id=pg_temp.partition_id(n,i)),k)$$;

insert into transfer_results select throws_ok($$select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('overflow.group','partition.overflow'))$$,
 '22023','LIMIT_EXCEEDED','10001 identities explicitly reject without truncation');
insert into transfer_results select is((select count(*) from inventory.stock_count_partition_groups where id=pg_temp.fid('overflow.group')),0::bigint,'overflow rolls back group and all drafts');
insert into transfer_results select throws_ok($$select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('bad.size','partition.serial')||'{"partition_size":501}')$$,
 '22023','COUNT_PARTITION_INPUT_INVALID','identity partition size cannot exceed 500');
insert into transfer_results select throws_ok($$select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('bad.cutoff','partition.serial')||'{"cutoff_at":"2020-01-01T00:00:00Z"}')$$,
 '22023','COUNT_PARTITION_INPUT_INVALID','caller cannot forge shared cutoff');
insert into responses values('partition.capture',pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('serial.group','partition.serial'),null,'partition.capture'));
insert into transfer_results select is(pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('serial.group','partition.serial'),null,'partition.capture'),
 (select r from responses where name='partition.capture'),'capture replay returns the exact receipt without duplicate documents');
insert into transfer_results select throws_ok($$select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('serial.group','partition.serial')||'{"reason":"Changed body"}',null,'partition.capture')$$,
 '22023','IDEMPOTENCY_MISMATCH','capture replay rejects changed body');
insert into transfer_results select ok((select not (r->'entity' ? 'items') and not (r->'entity' ? 'identities') from responses where name='partition.capture'),'capture receipt is compact metadata');
insert into transfer_results select is(jsonb_array_length(pg_temp.partition_doc('serial.group',1)#>'{lines,0,identities}'),500,'first serial count contains exactly 500 identities');
insert into transfer_results select is(jsonb_array_length(pg_temp.partition_doc('serial.group',2)#>'{lines,0,identities}'),1,'second serial count includes the remaining identity');
insert into transfer_results select is((pg_temp.partition_doc('serial.group',1)#>>'{lines,0,baseline_quantity}')::numeric,500::numeric,'first baseline is its partition quantity');
insert into transfer_results select is((pg_temp.partition_doc('serial.group',2)#>>'{lines,0,baseline_quantity}')::numeric,1::numeric,'second baseline does not repeat whole-product quantity');
insert into transfer_results select is((select count(distinct cutoff_at) from inventory.stock_counts where id in(pg_temp.partition_id('serial.group',1),pg_temp.partition_id('serial.group',2))),1::bigint,'partitions share exactly one immutable cutoff');
insert into transfer_results select is((select count(*) from inventory.stock_count_partition_identities where tenant_id=pg_temp.fid('t') and group_id=pg_temp.fid('serial.group')),501::bigint,'manifest captures every identity once');
insert into transfer_results select throws_ok($$insert into inventory.stock_count_partition_identities select tenant_id,group_id,identity_id,pg_temp.partition_id('serial.group',2),baseline
 from inventory.stock_count_partition_identities where group_id=pg_temp.fid('serial.group') limit 1$$,'23505',null,'duplicate identity cannot belong to two partitions');
insert into transfer_results select ok(pg_temp.partition_page('serial.group')->>'capture_complete'='true' and pg_temp.partition_page('serial.group')->>'posting_complete'='false','complete capture explicitly differs from completed posting');
insert into transfer_results select is(jsonb_array_length(pg_temp.partition_page('serial.group',0,1)->'items'),1,'document page respects requested bounded limit');
insert into transfer_results select is((pg_temp.partition_page('serial.group',0,1)->>'next_cursor')::integer,1,'page provides explicit continuation ordinal');
insert into transfer_results select is((pg_temp.partition_page('serial.group',1,1)->'items'->0->>'partition_ordinal')::integer,2,'continuation returns remaining partition');
insert into transfer_results select throws_ok($$select pg_temp.partition_page('serial.group',0,51)$$,'22023','COUNT_PARTITION_PAGE_INVALID','document page enforces maximum 50');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('forged.partition')||jsonb_build_object('partition_group_id',pg_temp.fid('serial.group')))$$,
 '22023','COUNT_PARTITION_METADATA_SERVER_ONLY','ordinary upsert cannot claim another group');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',pg_temp.partition_doc('serial.group',1)||jsonb_build_object('partition_ordinal',2),1)$$,
 '22023','COUNT_PARTITION_BASELINE_IMMUTABLE','partition ordinal cannot be changed');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.partition_doc('serial.group',1),'{lines,0,identities}',
 (pg_temp.partition_doc('serial.group',1)#>'{lines,0,identities}')-0),1)$$,'22023','COUNT_IDENTITIES_IMMUTABLE','partition edit cannot silently omit an identity');
insert into transfer_results select throws_ok($$select pg_temp.partition_post('serial.group',1)$$,'55000','COUNT_APPROVAL_REQUIRED','each partition requires its own approval');
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.partition_doc('serial.group',1),'{lines,0,identities,0,counted_quantity}','"0"'),1);
insert into transfer_results select is((pg_temp.partition_doc('serial.group',1)#>>'{lines,0,variance_quantity}')::numeric,(-1)::numeric,'serial edit computes only its captured partition variance');
select pg_temp.partition_approve('serial.group',1);
insert into responses values('partition.post',pg_temp.partition_post('serial.group',1,'partition.post'));
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('partition.serial.bal')),500::numeric,'independent first partition applies one shortage');
-- Replay uses the original expected version as required by the command hash.
insert into transfer_results select is(pg_temp.count_call('post_stock_adjustment',jsonb_build_object('document_id',pg_temp.partition_id('serial.group',1)),4,'partition.post'),
 (select r from responses where name='partition.post'),'partition posting is idempotent');
insert into transfer_results select is(pg_temp.partition_doc('serial.group',2)->>'status','draft','posting a partition does not approve or post its sibling');
insert into transfer_results select is((pg_temp.partition_page('serial.group')->>'posted_partition_count')::integer,1,'group reports partial posting explicitly');
insert into transfer_results select ok(pg_temp.partition_page('serial.group')->>'posting_complete'='false','partially posted group never claims complete');
select pg_temp.partition_approve('serial.group',2);
select pg_temp.partition_post('serial.group',2);
insert into transfer_results select ok(pg_temp.partition_page('serial.group')->>'posting_complete'='true','group completes only after all independent posts');
insert into transfer_results select is((pg_temp.partition_page('serial.group')->>'counted_quantity')::numeric,500::numeric,'group totals include both partitions');
insert into transfer_results select is((pg_temp.partition_page('serial.group')->>'grand_total')::numeric,2::numeric,'group retains exact complete approval value total');
insert into transfer_results select is((select sum(jl.base_debit-jl.base_credit) from finance.journal_lines jl join finance.journal_entries j on j.id=jl.journal_entry_id
 where j.source_id=pg_temp.partition_id('serial.group',1)),0::numeric,'partition shortage journal balances exactly');
insert into transfer_results select throws_ok($$update inventory.stock_count_partition_groups set cutoff_at=clock_timestamp() where id=pg_temp.fid('serial.group')$$,
 '55000','COUNT_PARTITION_BASELINE_IMMUTABLE','shared cutoff is immutable after capture');
insert into transfer_results select throws_ok($$delete from inventory.stock_count_partitions where group_id=pg_temp.fid('serial.group')$$,
 '55000','COUNT_PARTITION_BASELINE_IMMUTABLE','partition membership cannot silently disappear');

-- Lots permit later movement while applying the original cutoff delta to current
-- holdings. A real transfer of the sibling lot must survive first-partition posting.
select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('lot.group','partition.lot'));
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.partition_doc('lot.group',1),'{lines,0,identities,0,counted_quantity}','"0"'),1);
select pg_temp.partition_approve('lot.group',1);
select pg_temp.call(jsonb_set(pg_temp.payload('partition.later','immediate','partition.lot','1'),'{lines,0,lot_id}',
 pg_temp.partition_doc('lot.group',2)#>'{lines,0,identities,0,id}')||jsonb_build_object('document_date',(clock_timestamp() at time zone 'UTC')::date));
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('partition.lot.bal')),500::numeric,'real later movement reduces current holdings after shared cutoff');
select pg_temp.partition_post('lot.group',1);
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('partition.lot.bal')),499::numeric,'partition applies cutoff delta while retaining later movement');
select pg_temp.partition_approve('lot.group',2);
select pg_temp.partition_post('lot.group',2);
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('partition.lot.bal')),499::numeric,'zero sibling variance does not replace current holdings');
insert into transfer_results select is((pg_temp.partition_page('lot.group')->>'baseline_quantity')::numeric,501::numeric,'shared original baseline survives later movement and independent posts');
insert into transfer_results select is((pg_temp.partition_page('lot.group')->>'counted_quantity')::numeric,500::numeric,'group counted total remains physical cutoff total');
insert into transfer_results select is((select carrying_value from inventory.stock_valuations where stock_balance_id=pg_temp.fid('partition.lot.bal')),998::numeric,'current pooled carrying value remains exact after transfer and count');
insert into transfer_results select ok(pg_temp.partition_page('lot.group')->>'posting_complete'='true','lot group completion is explicit');
-- Cancellation keeps the captured document visible and makes incompleteness explicit.
select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('cancelled.group','partition.lot'));
select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.partition_id('cancelled.group',2),'action','cancel','reason','Cannot complete this physical count'),1);
insert into transfer_results select is((pg_temp.partition_page('cancelled.group')->>'cancelled_partition_count')::integer,1,'cancelled partition remains in completeness report');
insert into transfer_results select ok(pg_temp.partition_page('cancelled.group')->>'capture_complete'='true' and pg_temp.partition_page('cancelled.group')->>'posting_complete'='false','cancelled partition never disappears or implies complete posting');
insert into transfer_results select throws_ok($$select api.stock_count_partitions_page(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),pg_temp.fid('serial.group'))$$,
 'P0002','DOCUMENT_NOT_FOUND','partition group read cannot cross branch scope');
select pg_temp.actor('outsider');
set local role authenticated;
insert into transfer_results select is((select count(*) from inventory.stock_count_partition_groups),0::bigint,'partition group RLS hides outsider records');
insert into transfer_results select is((select count(*) from inventory.stock_count_partition_identities),0::bigint,'partition identity RLS hides outsider records');
insert into transfer_results select throws_ok($$select pg_temp.partition_page('serial.group')$$,'42501',null,'outsider cannot read group completeness');
insert into transfer_results select throws_ok($$select pg_temp.count_call('capture_stock_count_partitions',pg_temp.partition_payload('outsider.group','partition.serial'))$$,'42501',null,'outsider cannot capture a partition group');
insert into transfer_results select throws_ok($$insert into inventory.stock_count_partition_groups(id) values(gen_random_uuid())$$,'42501',null,'direct partition writes denied');
reset role;
select pg_temp.actor('actor');
set constraints all immediate;
