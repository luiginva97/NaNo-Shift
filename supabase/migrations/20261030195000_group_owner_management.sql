-- Allow only the group creator to rename or delete their group.
drop policy if exists shift_groups_update_admin on public.shift_groups;
drop policy if exists shift_groups_update_owner on public.shift_groups;
create policy shift_groups_update_owner on public.shift_groups
for update to authenticated
using (created_by = (select auth.uid()))
with check (created_by = (select auth.uid()));

drop policy if exists shift_groups_delete_owner on public.shift_groups;
create policy shift_groups_delete_owner on public.shift_groups
for delete to authenticated
using (created_by = (select auth.uid()));
