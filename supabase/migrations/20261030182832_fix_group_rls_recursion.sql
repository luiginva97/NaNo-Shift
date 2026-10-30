-- Break recursive RLS evaluation by checking group membership through SECURITY DEFINER helpers.
create or replace function public.is_group_member(p_group_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (
  select 1 from public.shift_group_members m
  where m.group_id = p_group_id and m.user_id = (select auth.uid())
); $$;

create or replace function public.is_group_manager(p_group_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (
  select 1 from public.shift_group_members m
  where m.group_id = p_group_id and m.user_id = (select auth.uid())
    and m.member_role in ('owner','admin')
); $$;

revoke all on function public.is_group_member(uuid) from public;
revoke all on function public.is_group_manager(uuid) from public;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_manager(uuid) to authenticated;

drop policy if exists shift_group_members_select_members on public.shift_group_members;
create policy shift_group_members_select_members on public.shift_group_members
for select to authenticated using (public.is_group_member(group_id));

drop policy if exists shift_groups_select_member on public.shift_groups;
create policy shift_groups_select_member on public.shift_groups
for select to authenticated using (public.is_group_member(id) or created_by = (select auth.uid()));

drop policy if exists shift_group_invitations_select_member on public.shift_group_invitations;
create policy shift_group_invitations_select_member on public.shift_group_invitations
for select to authenticated using (public.is_group_member(group_id));

drop policy if exists shift_group_invitations_insert_member on public.shift_group_invitations;
create policy shift_group_invitations_insert_member on public.shift_group_invitations
for insert to authenticated with check (invited_by = (select auth.uid()) and public.is_group_member(group_id));

drop policy if exists shift_group_invitations_update_inviter_or_admin on public.shift_group_invitations;
create policy shift_group_invitations_update_inviter_or_admin on public.shift_group_invitations
for update to authenticated using (invited_by = (select auth.uid()) or public.is_group_manager(group_id))
with check (invited_by = (select auth.uid()) or public.is_group_manager(group_id));

drop policy if exists shift_group_members_delete_self_or_admin on public.shift_group_members;
create policy shift_group_members_delete_self_or_admin on public.shift_group_members
for delete to authenticated using (user_id = (select auth.uid()) or public.is_group_manager(group_id));

drop policy if exists shift_group_members_update_admin on public.shift_group_members;
create policy shift_group_members_update_admin on public.shift_group_members
for update to authenticated using (public.is_group_manager(group_id))
with check (public.is_group_manager(group_id));
