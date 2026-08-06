-- Cover every Phase 1 foreign key with an index whose leading columns match
-- the foreign-key column order. This keeps parent updates/deletes and tenant
-- scoped joins predictable as membership volume grows.

create index company_member_branches_company_branch_idx
  on public.company_member_branches(company_id, branch_id);

create index company_memberships_invited_by_idx
  on public.company_memberships(invited_by);

create index company_memberships_company_role_idx
  on public.company_memberships(company_id, role_id);

create index profiles_default_company_idx
  on public.profiles(default_company_id);

create index role_permissions_permission_code_idx
  on public.role_permissions(permission_code);
