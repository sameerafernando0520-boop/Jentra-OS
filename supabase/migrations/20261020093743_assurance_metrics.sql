-- Corporate Audit & Assurance A11: process metrics (blueprint 68 §9, FR-6825).
-- CANDIDATE ONLY. Not installed. Requires A1-A5 and A8 (assurance.member_label).
--
-- api.assurance_metrics measures the audit process over the engagements whose
-- period overlaps [from, to] in one scope, from immutable events and current
-- state. Every duration or rate reports its sample count; with no samples the
-- value is null ("not measured"), never zero. Percentiles are nearest rank
-- (percentile_disc), as assurancePercentile in Dart. Stage times come only
-- from the actions that move an engagement's status (create_engagement,
-- transition, issue_report, reopen_report); review time runs from the latest
-- submission to acceptance, as the Dart reference does.

create function assurance.metric_spread(p_days numeric[]) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'p50', (select round(percentile_disc(0.5) within group (order by d), 2) from unnest(p_days) d),
    'p90', (select round(percentile_disc(0.9) within group (order by d), 2) from unnest(p_days) d),
    'samples', coalesce(cardinality(p_days), 0));
$$;

create function assurance.metric_rate(p_hits bigint, p_samples bigint) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'value', case when coalesce(p_samples, 0) = 0 then null
                  else round(p_hits::numeric / p_samples, 4) end,
    'samples', coalesce(p_samples, 0));
$$;

create function api.assurance_metrics(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_engs uuid[];
  v_stage jsonb := '{}'::jsonb;
  v_s text;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception using errcode = '22023', message = 'ASSURANCE_RANGE_INVALID';
  end if;
  select coalesce(array_agg(e.id), '{}') into v_engs from assurance.engagements e
   where e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id
     and e.period_start <= p_to and e.period_end >= p_from;

  -- Time in each engagement stage: first entry to first exit.
  foreach v_s in array array['planning','fieldwork','reporting'] loop
    v_stage := v_stage || jsonb_build_object('stage_' || v_s || '_days', assurance.metric_spread((
      select array_agg(round(extract(epoch from (x.left_at - x.entered_at)) / 86400.0, 2))
        from (select ev.engagement_id,
                     min(ev.occurred_at) filter (where ev.to_status = v_s) entered_at,
                     min(ev.occurred_at) filter (where ev.from_status = v_s and ev.to_status <> v_s) left_at
                from assurance.events ev
               where ev.engagement_id = any (v_engs)
                 and ev.action in ('create_engagement','transition','issue_report','reopen_report')
               group by ev.engagement_id) x
       where x.entered_at is not null and x.left_at is not null and x.left_at >= x.entered_at)));
  end loop;

  return jsonb_build_object('from', p_from, 'to', p_to, 'engagements', cardinality(v_engs),
    'metrics', v_stage || jsonb_build_object(
      'evidence_waiting_days', assurance.metric_spread((
        select array_agg(round(extract(epoch from (s.first_submit - r.opened)) / 86400.0, 2))
          from (select ev.aggregate_id, min(ev.occurred_at) opened from assurance.events ev
                 where ev.engagement_id = any (v_engs) and ev.action = 'request_evidence'
                 group by ev.aggregate_id) r
          join (select ev.aggregate_id, min(ev.occurred_at) first_submit from assurance.events ev
                 where ev.engagement_id = any (v_engs)
                   and ev.action in ('submit_evidence','collect_system_evidence')
                 group by ev.aggregate_id) s on s.aggregate_id = r.aggregate_id)),
      'evidence_review_days', assurance.metric_spread((
        select array_agg(round(extract(epoch from (a.accepted - (
                   select max(ev.occurred_at) from assurance.events ev
                    where ev.engagement_id = any (v_engs) and ev.aggregate_id = a.aggregate_id
                      and ev.action in ('submit_evidence','collect_system_evidence')
                      and ev.occurred_at <= a.accepted))) / 86400.0, 2))
          from (select ev.aggregate_id, min(ev.occurred_at) accepted from assurance.events ev
                 where ev.engagement_id = any (v_engs) and ev.action = 'review_evidence'
                   and ev.to_status = 'accepted'
                 group by ev.aggregate_id) a)),
      'evidence_first_time_right', (
        select assurance.metric_rate(count(*) filter (where r.rework_count = 0), count(*))
          from assurance.evidence_requests r
         where r.engagement_id = any (v_engs) and r.status = 'accepted'),
      'request_ageing', (
        select jsonb_build_object(
          'd0_7', count(*) filter (where current_date - (r.requested_at at time zone 'UTC')::date <= 7),
          'd8_30', count(*) filter (where current_date - (r.requested_at at time zone 'UTC')::date between 8 and 30),
          'd31_plus', count(*) filter (where current_date - (r.requested_at at time zone 'UTC')::date > 30),
          'samples', count(*))
          from assurance.evidence_requests r
         where r.engagement_id = any (v_engs) and r.status = 'open'),
      'test_completion', (
        select assurance.metric_rate(count(*) filter (where p.status = 'reviewed'), count(*))
          from assurance.test_procedures p where p.engagement_id = any (v_engs)),
      'control_coverage', (
        select assurance.metric_rate(
                 count(*) filter (where exists (select 1 from assurance.test_procedures p
                   where p.control_id = c.id and p.status = 'reviewed')), count(*))
          from assurance.engagement_controls c where c.engagement_id = any (v_engs)),
      'retest_pass_rate', (
        select assurance.metric_rate(count(*) filter (where t.result = 'pass'), count(*))
          from assurance.retests t join assurance.findings f on f.id = t.finding_id
         where f.engagement_id = any (v_engs)),
      'recurrence', (
        select assurance.metric_rate(
                 (select count(*) from assurance.events ev
                   where ev.engagement_id = any (v_engs) and ev.action = 'reopen_finding'),
                 count(*))
          from assurance.findings f where f.engagement_id = any (v_engs)),
      'finding_ageing_days', (
        select jsonb_object_agg(s.severity, jsonb_build_object(
                 'value', (select round(avg(current_date - (f.issued_at at time zone 'UTC')::date), 2)
                             from assurance.findings f
                            where f.engagement_id = any (v_engs) and f.severity = s.severity
                              and f.status not in ('closed','risk_accepted')),
                 'samples', (select count(*) from assurance.findings f
                              where f.engagement_id = any (v_engs) and f.severity = s.severity
                                and f.status not in ('closed','risk_accepted'))))
          from unnest(array['low','medium','high','critical']) s(severity)),
      'overdue_remediation', jsonb_build_object('value', (
        select count(*) from assurance.findings f
         where f.engagement_id = any (v_engs) and f.status = 'remediating'
           and f.response_due < current_date)),
      'open_high_risk_findings', jsonb_build_object('value', (
        select count(*) from assurance.findings f
         where f.engagement_id = any (v_engs) and f.severity in ('high','critical')
           and f.status not in ('closed','risk_accepted'))),
      'report_issuance_days', assurance.metric_spread((
        select array_agg(round(extract(epoch from (x.issued - x.reporting)) / 86400.0, 2))
          from (select ev.engagement_id,
                       min(ev.occurred_at) filter (where ev.action = 'transition' and ev.to_status = 'reporting') reporting,
                       min(ev.occurred_at) filter (where ev.action = 'issue_report') issued
                  from assurance.events ev where ev.engagement_id = any (v_engs)
                 group by ev.engagement_id) x
         where x.reporting is not null and x.issued is not null and x.issued >= x.reporting)),
      'workload', coalesce((
        select jsonb_agg(jsonb_build_object('label', w.label, 'open_requests', w.requests,
                 'open_findings', w.findings) order by w.requests + w.findings desc, w.label)
          from (select assurance.member_label(p_tenant_id, m.id) label,
                       count(*) filter (where o.kind = 'request') requests,
                       count(*) filter (where o.kind = 'finding') findings
                  from (select r.owner_id, 'request' kind from assurance.evidence_requests r
                         where r.engagement_id = any (v_engs) and r.status = 'open'
                        union all
                        select f.owner_id, 'finding' from assurance.findings f
                         where f.engagement_id = any (v_engs) and f.status in ('issued','remediating')) o
                  join core.memberships m on m.tenant_id = p_tenant_id and m.user_id = o.owner_id
                 group by m.id
                 order by count(*) desc, 1
                 limit 10) w), '[]'::jsonb)));
end $$;

revoke all on function assurance.metric_spread(numeric[]) from public, anon, authenticated, service_role;
revoke all on function assurance.metric_rate(bigint, bigint) from public, anon, authenticated, service_role;
revoke all on function api.assurance_metrics(uuid, uuid, uuid, date, date) from public, anon, service_role;
grant execute on function api.assurance_metrics(uuid, uuid, uuid, date, date) to authenticated;
