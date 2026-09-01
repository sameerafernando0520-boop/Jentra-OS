-- Materialize the JWT once per statement. Keeping auth.jwt() itself inside
-- the scalar subquery allows Postgres to use an init plan for invitation reads.

drop policy if exists invitations_invitee_read on core.invitations;
create policy invitations_invitee_read on core.invitations
  for select to authenticated
  using (
    lower(email) = lower(coalesce(((select auth.jwt())->>'email'), ''))
  );
