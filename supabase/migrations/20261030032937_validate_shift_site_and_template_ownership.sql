drop policy if exists shifts_insert_own_or_admin on public.shifts;
create policy shifts_insert_own_or_admin on public.shifts for insert to authenticated
with check (
  ((user_id = (select auth.uid())) or (select public.current_profile_role()) = 'admin')
  and (select public.current_profile_approved())
  and (site_id is null or exists (select 1 from public.work_sites ws where ws.id = shifts.site_id and ws.user_id = shifts.user_id))
  and (template_id is null or exists (select 1 from public.shift_templates st where st.id = shifts.template_id and st.user_id = shifts.user_id))
);

drop policy if exists shifts_update_own_or_admin on public.shifts;
create policy shifts_update_own_or_admin on public.shifts for update to authenticated
using ((user_id = (select auth.uid())) or (select public.current_profile_role()) = 'admin')
with check (
  ((user_id = (select auth.uid())) or (select public.current_profile_role()) = 'admin')
  and (select public.current_profile_approved())
  and (site_id is null or exists (select 1 from public.work_sites ws where ws.id = shifts.site_id and ws.user_id = shifts.user_id))
  and (template_id is null or exists (select 1 from public.shift_templates st where st.id = shifts.template_id and st.user_id = shifts.user_id))
);
