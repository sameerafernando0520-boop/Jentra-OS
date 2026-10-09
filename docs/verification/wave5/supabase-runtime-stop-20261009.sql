-- Reviewed stop: disables only this authority and its three recorded jobs.
begin;
update intelligence_control.edge_authorities set enabled=false where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7';
update intelligence_control.runtime_worker_scopes set enabled=false where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7';
select intelligence_control.edge_schedule_tick('health');
commit;
-- No existing account, tenant, function, secret or job is removed. New evidence
-- remains available for review; expiry/disable blocks its worker/receiver paths.
