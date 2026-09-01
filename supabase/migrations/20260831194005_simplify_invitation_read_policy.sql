-- Managers mutate invitations through validated RPCs; direct invitation reads
-- are needed only by the authenticated invitee. This removes a correlated
-- permission lookup from the RLS hot path.

drop policy invitations_invitee_or_manager_read on core.invitations;
create policy invitations_invitee_read on core.invitations
  for select to authenticated
  using (lower(email) = lower(coalesce((select auth.jwt()->>'email'), '')));
