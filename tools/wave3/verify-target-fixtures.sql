-- Prepared read-only verification for the separately approved isolated scale target.
-- Do not execute on the development/acceptance project. Never touches auth or opening records.
-- Synthetic cohort convention: wave3-scale-*, large tenant subset wave3-scale-large-*.
with cohort as (
 select id,slug from core.tenants where slug like 'wave3-scale-%'
), entity_counts as (
 select t.id,count(e.id) as entities from cohort t left join core.legal_entities e
 on e.tenant_id=t.id group by t.id
), warehouse_counts as (
 select e.id,count(w.id) as warehouses from core.legal_entities e join cohort t
 on t.id=e.tenant_id left join core.warehouses w on w.tenant_id=e.tenant_id
 and w.legal_entity_id=e.id group by e.id
), large_counts as (
 select t.id,count(p.id) as products from cohort t left join inventory.products p
 on p.tenant_id=t.id where t.slug like 'wave3-scale-large-%' group by t.id
)
select jsonb_build_object(
 'tenants',(select count(*) from cohort),
 'legal_entities',(select coalesce(sum(entities),0) from entity_counts),
 'minimum_legal_entities_per_tenant',(select coalesce(min(entities),0) from entity_counts),
 'warehouses',(select coalesce(sum(warehouses),0) from warehouse_counts),
 'minimum_warehouses_per_entity',(select coalesce(min(warehouses),0) from warehouse_counts),
 'large_tenants',(select count(*) from large_counts),
 'products_per_large_tenant',(select coalesce(min(products),0) from large_counts),
 'stock_movements',(select count(*) from inventory.stock_movements m join cohort t on t.id=m.tenant_id),
 'journal_lines',(select count(*) from finance.journal_lines l join cohort t on t.id=l.tenant_id)
) as fixture_counts;
