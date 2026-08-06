begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(10);

-- 1. Table existence checks
select has_table('public', 'tax_rates', 'tax_rates table exists');
select has_table('public', 'stock_transfers', 'stock_transfers table exists');
select has_table('public', 'stock_transfer_items', 'stock_transfer_items table exists');
select has_table('public', 'party_contacts', 'party_contacts table exists');
select has_table('public', 'party_addresses', 'party_addresses table exists');
select has_table('public', 'leads', 'leads table exists');
select has_table('public', 'activities', 'activities table exists');
select has_table('public', 'attachments', 'attachments table exists');

-- 2. RPC function existence
select has_function('public', 'post_stock_transfer', ARRAY['uuid', 'uuid', 'uuid', 'jsonb', 'text'], 'post_stock_transfer RPC exists');
select has_function('public', 'convert_lead_to_party', ARRAY['uuid', 'uuid', 'text'], 'convert_lead_to_party RPC exists');

select * from finish();

rollback;
