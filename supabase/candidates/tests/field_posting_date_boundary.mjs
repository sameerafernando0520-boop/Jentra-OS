import assert from 'node:assert/strict';

// Diagnostic regression for an OPEN accounting-date policy conflict. This does
// not replace a production clock or relax a canonical posting-date constraint.
export async function diagnosePostingDateBoundary(db) {
 const {rows}=await db.query(`select instant::text,
  (instant at time zone 'Asia/Colombo')::date::text order_date,
  (instant at time zone 'UTC')::date::text latest_posting_date
  from (values
   ('2026-11-04 18:29:59+00'::timestamptz),
   ('2026-11-04 18:30:00+00'::timestamptz),
   ('2026-11-04 23:59:59+00'::timestamptz),
   ('2026-11-05 00:00:00+00'::timestamptz)
  ) boundary(instant) order by instant`);
 assert.deepEqual(rows.map(({order_date,latest_posting_date})=>[order_date,latest_posting_date]),[
  ['2026-11-04','2026-11-04'],['2026-11-05','2026-11-04'],
  ['2026-11-05','2026-11-04'],['2026-11-05','2026-11-05'],
 ]);
 const definition=async(signature)=>(await db.query('select pg_get_functiondef($1::regprocedure) definition',[signature])).rows[0].definition;
 const order=await definition('field_sales.prepare(uuid,uuid,uuid,uuid,jsonb)');
 const posting=await definition('sales.field_flow_post_canonical(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)');
 assert.match(order,/d:=\(statement_timestamp\(\) at time zone le\.timezone\)::date/);
 assert.match(order,/'order_date',d/);
 assert.match(posting,/if \(v_doc->>'document_date'\)::date>\(clock_timestamp\(\) at time zone 'UTC'\)::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE'/);
 return {
  state:'open',diagnosticChecks:4,timezone:'Asia/Colombo',observations:rows,
  affectedLocalWindow:'00:00 through 05:29:59 Asia/Colombo',
  canonicalFutureDateGuardPreserved:true,utcFixtureIsCompanyAcceptance:false,
  boundary:'Fixed-instant database date projections plus installed isolated function definitions diagnose the conflict. This is not a successful Sri Lanka midnight delivery-posting workflow or authorization to change ledger dates.',
 };
}
