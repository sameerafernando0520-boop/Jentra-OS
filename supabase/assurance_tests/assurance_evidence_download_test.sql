-- Corporate Audit & Assurance A12 reviewer-download candidate tests. Included
-- by build_assurance_candidate.ps1 -Slice A12 after the A11 tests and the A12
-- DDL. Reuses the A7 storage fixtures on engS: evS2 verified and accepted,
-- evT1 verified and then rewritten, evS1 a recorded mismatch.
create temporary table download_tickets(label text primary key, body jsonb);
grant select,insert on download_tickets to authenticated,service_role;
create function pg_temp.dl(ev text, eng text default 'engS') returns jsonb language sql as $$
  select api.assurance_evidence_download_ticket(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),
    pg_temp.aid('tenant.branch'),pg_temp.aid(eng),pg_temp.aid(ev)) $$;
create function pg_temp.redeem(label text, who text) returns jsonb language sql as $$
  select api.assurance_evidence_service_download((select (body->>'ticket_id')::uuid
    from download_tickets where download_tickets.label = redeem.label), pg_temp.aid(who)) $$;

-- Structure.
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid='assurance.evidence_download_tickets'::regclass)
  and not has_table_privilege('authenticated','assurance.evidence_download_tickets','SELECT')
  and not has_table_privilege('service_role','assurance.evidence_download_tickets','SELECT'),
  'download: tickets force RLS with no client or service grants');
select ok(has_function_privilege('authenticated','api.assurance_evidence_download_ticket(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_evidence_download_ticket(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
  and has_function_privilege('service_role','api.assurance_evidence_service_download(uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','api.assurance_evidence_service_download(uuid,uuid)','EXECUTE'),
  'download: tickets are authenticated-only and redemption is service-only');

-- Who may ask, checked before anything is looked up.
select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.dl('evS2')$$,'42501',null,'download: a non-member is refused');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.dl('evS2')$$,'42501',null,'download: a foreign tenant actor is refused');
reset role;select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.dl('evS2','engX')$$,'42501',null,
  'download: an unknown engagement is refused, not reported missing, without authority');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.dl('evS2','engX')$$,'P0002','ASSURANCE_ENGAGEMENT_NOT_FOUND',
  'download: an unknown engagement is not found for a viewer');

-- What may be downloaded: verified uploads only.
select throws_ok($$select pg_temp.dl('evS1')$$,'55000','ASSURANCE_EVIDENCE_UNVERIFIED',
  'download: a recorded mismatch is never downloadable');
select throws_ok($$select pg_temp.dl('evT1')$$,'55000','ASSURANCE_EVIDENCE_UNVERIFIED',
  'download: an object rewritten after verification is not downloadable');
select throws_ok($$select pg_temp.dl('evNone')$$,'P0002','ASSURANCE_EVIDENCE_NOT_FOUND',
  'download: an unknown item is not found');
insert into download_tickets values('reviewer',pg_temp.dl('evS2'));
select ok((select body->>'evidence_id'=pg_temp.aid('evS2')::text and body->>'ticket_id' is not null
    and (body->>'expires_at')::timestamptz <= clock_timestamp()+interval '5 minutes'
  from download_tickets where label='reviewer'),'download: a viewer gets a five-minute ticket for verified evidence');
reset role;select pg_temp.actor('external');set local role authenticated;
insert into download_tickets values('external',pg_temp.dl('evS2'));
select ok((select body->>'ticket_id' is not null from download_tickets where label='external'),
  'download: a current external reviewer may download verified evidence');

-- Redemption: service only, by the human who asked, once.
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.redeem('reviewer','reviewer')$$,'42501',null,
  'download: a human session cannot redeem a ticket');
reset role;select pg_temp.service();set local role service_role;
select throws_ok($$select pg_temp.redeem('reviewer','auditor')$$,'42501','ASSURANCE_TICKET_INVALID',
  'download: a ticket is bound to the human who asked');
select ok((select t->>'evidence_id'=pg_temp.aid('evS2')::text and t->>'bucket'='jentra-assurance-evidence'
    and t->>'object_path'=pg_temp.sref('evS2') and t->>'sha256'=pg_temp.hex('signed bank letter v2')
    and (t->>'byte_size')::bigint=21 from pg_temp.redeem('reviewer','reviewer') t),
  'download: redemption returns the generated path with the recorded digest and size');
select throws_ok($$select pg_temp.redeem('reviewer','reviewer')$$,'42501','ASSURANCE_TICKET_INVALID',
  'download: a ticket is used once');
reset role;
select ok((select consumed_at is not null and user_id=pg_temp.aid('reviewer') from assurance.evidence_download_tickets
  where id=(select (body->>'ticket_id')::uuid from download_tickets where label='reviewer')),
  'download: the redeemed ticket records who downloaded and when');
select throws_ok($$delete from assurance.evidence_download_tickets$$,'55000','ASSURANCE_HISTORY_IMMUTABLE',
  'download: the download log cannot be deleted');
with x as (
  insert into assurance.evidence_download_tickets(tenant_id,engagement_id,evidence_id,user_id,issued_at,expires_at)
  values(pg_temp.aid('tenant'),pg_temp.aid('engS'),pg_temp.aid('evS2'),pg_temp.aid('reviewer'),
    clock_timestamp()-interval '10 minutes',clock_timestamp()-interval '6 minutes') returning id)
insert into download_tickets select 'stale', jsonb_build_object('ticket_id', id) from x;
select pg_temp.service();set local role service_role;
select throws_ok($$select pg_temp.redeem('stale','reviewer')$$,'42501','ASSURANCE_TICKET_INVALID',
  'download: an expired ticket is refused');

-- Access ending between ticket and redemption.
reset role;
update assurance.engagement_team set expires_at=now()-interval '1 second'
 where engagement_id=pg_temp.aid('engS') and user_id=pg_temp.aid('external');
select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select pg_temp.dl('evS2')$$,'42501','ASSURANCE_EXTERNAL_ACCESS_EXPIRED',
  'download: expired external access is refused immediately');
reset role;
update core.memberships set status='suspended' where id=pg_temp.aid('external.m');
select pg_temp.service();set local role service_role;
select throws_ok($$select pg_temp.redeem('external','external')$$,'42501','ASSURANCE_TICKET_INVALID',
  'download: a ticket cannot be redeemed after membership ends');
reset role;
update core.memberships set status='active' where id=pg_temp.aid('external.m');
update assurance.engagement_team set expires_at=now()+interval '30 days'
 where engagement_id=pg_temp.aid('engS') and user_id=pg_temp.aid('external');
