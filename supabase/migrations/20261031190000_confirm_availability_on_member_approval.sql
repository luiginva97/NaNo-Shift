-- Conferma le disponibilità già inserite quando la coordinatrice approva l'ingresso.
-- Blocca inoltre la modifica/eliminazione delle disponibilità già confermate.
create or replace function public.review_unit_member(p_unit uuid, p_user uuid, p_action text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Solo la coordinatrice può farlo'; end if;
  if p_action = 'approve' then
    update public.unit_members set status = 'active'
      where unit_id = p_unit and user_id = p_user and unit_role = 'nurse';
    update public.unit_availability set review_status = 'confirmed', updated_at = now()
      where unit_id = p_unit and user_id = p_user and review_status <> 'confirmed';
  elsif p_action = 'promote' then
    update public.unit_members set unit_role = 'coordinator', status = 'active' where unit_id = p_unit and user_id = p_user;
  elsif p_action in ('reject', 'remove') then
    if p_user = (select auth.uid()) then raise exception 'Non puoi rimuovere te stessa'; end if;
    delete from public.unit_members where unit_id = p_unit and user_id = p_user;
    delete from public.unit_shifts where unit_id = p_unit and user_id = p_user;
    delete from public.unit_availability where unit_id = p_unit and user_id = p_user;
  else
    raise exception 'Azione non valida';
  end if;
end $$;

drop policy if exists unit_availability_update_own on public.unit_availability;
create policy unit_availability_update_own on public.unit_availability
for update to authenticated
using (user_id = (select auth.uid()) and review_status <> 'confirmed' and public.is_unit_member(unit_id))
with check (user_id = (select auth.uid()) and review_status = 'pending' and public.is_unit_member(unit_id));

drop policy if exists unit_availability_delete_own on public.unit_availability;
create policy unit_availability_delete_own on public.unit_availability
for delete to authenticated
using (user_id = (select auth.uid()) and review_status <> 'confirmed' and public.is_unit_member(unit_id));
