-- Una disponibilità confermata dalla coordinatrice non può più essere modificata o eliminata dal personale.
drop policy if exists unit_availability_update_own on public.unit_availability;
create policy unit_availability_update_own on public.unit_availability
for update to authenticated
using (user_id = (select auth.uid()) and review_status <> 'confirmed' and public.is_unit_member(unit_id))
with check (user_id = (select auth.uid()) and review_status = 'pending' and public.is_unit_member(unit_id));

drop policy if exists unit_availability_delete_own on public.unit_availability;
create policy unit_availability_delete_own on public.unit_availability
for delete to authenticated
using (user_id = (select auth.uid()) and review_status <> 'confirmed' and public.is_unit_member(unit_id));
