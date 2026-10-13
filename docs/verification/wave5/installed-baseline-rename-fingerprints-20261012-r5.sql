-- Read once BEFORE migration order58 and once after installation. Hashes only.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH expected(original_signature,preserved_signature) AS (VALUES
('api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','api.reserve_sales_order_stock_without_negative_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)'),
('sales.flow_post_stock(text,jsonb,uuid,uuid)','sales.flow_post_stock_without_negative_policy(text,jsonb,uuid,uuid)'),
('sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','sales.flow_post_without_negative_policy(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)')
)
SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'functions',(SELECT jsonb_agg(jsonb_build_object('originalSignature',e.original_signature,'preservedSignature',e.preserved_signature,
  'originalPresent',o.oid IS NOT NULL,'preservedPresent',p.oid IS NOT NULL,
  'originalBodyLfSha256',CASE WHEN o.oid IS NOT NULL THEN encode(extensions.digest(replace(o.prosrc,E'\r\n',E'\n'),'sha256'),'hex') END,
  'originalDefinitionSha256',CASE WHEN o.oid IS NOT NULL THEN encode(extensions.digest(pg_get_functiondef(o.oid),'sha256'),'hex') END,
  'preservedBodyLfSha256',CASE WHEN p.oid IS NOT NULL THEN encode(extensions.digest(replace(p.prosrc,E'\r\n',E'\n'),'sha256'),'hex') END,
  'preservedDefinitionSha256',CASE WHEN p.oid IS NOT NULL THEN encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex') END)
  ORDER BY e.original_signature) FROM expected e LEFT JOIN pg_proc o ON o.oid=to_regprocedure(e.original_signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.preserved_signature))
) AS baseline_rename_fingerprints;
ROLLBACK;
