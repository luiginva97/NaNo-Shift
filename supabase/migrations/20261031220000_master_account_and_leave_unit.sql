-- Account master e uscita volontaria dal reparto.
--
-- Master = amministratore che NON è membro di alcun reparto. Vede e gestisce tutti i reparti
-- (disponibilità, turni, membri) senza dover essere inserito in uno di essi.
-- Un amministratore che è anche membro di un reparto continua a comportarsi come un membro normale.

create or replace function private.is_master()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
     and not exists (select 1 from public.unit_members m where m.user_id = (select auth.uid()));
$$;

revoke all on function private.is_master() from public, anon;
grant execute on function private.is_master() to authenticated;

-- Il master è coordinatore implicito di ogni reparto: le policy e le RPC che usano
-- is_unit_coordinator (disponibilità, turni, membri, inviti, pubblicazione) valgono anche per lui.
create or replace function public.is_unit_coordinator(p_unit uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select private.is_master()
      or exists (select 1 from public.unit_members m
                 where m.unit_id = p_unit and m.user_id = (select auth.uid())
                   and m.status = 'active' and m.unit_role = 'coordinator');
$$;

-- units_select usa is_unit_member: il master deve poter leggere i reparti.
drop policy if exists units_select_master on public.units;
create policy units_select_master on public.units for select to authenticated
  using (private.is_master());

-- L'elenco "i miei reparti" per il master contiene tutti i reparti (come coordinatore attivo).
create or replace function public.get_my_units()
returns table(unit_id uuid, name text, unit_role text, status text, join_code text)
language sql
stable
security definer
set search_path to ''
as $$
  select u.id, u.name, 'coordinator'::text, 'active'::text, u.join_code
  from public.units u
  where private.is_master()
  union all
  select u.id, u.name, m.unit_role, m.status,
         case when m.unit_role = 'coordinator' and m.status = 'active' then u.join_code end
  from public.unit_members m join public.units u on u.id = m.unit_id
  where m.user_id = (select auth.uid()) and not private.is_master()
  order by 2;
$$;

-- Uscita volontaria dal reparto: rimuove l'iscrizione e anche disponibilità e turni di reparto
-- della persona (i turni già copiati nel suo calendario personale restano suoi).
-- Una coordinatrice può uscire solo se nel reparto ne resta almeno un'altra.
create or replace function public.leave_unit(p_unit uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  me uuid := (select auth.uid());
  my_role text;
begin
  if me is null then raise exception 'Accesso richiesto'; end if;
  select m.unit_role into my_role from public.unit_members m where m.unit_id = p_unit and m.user_id = me;
  if my_role is null then raise exception 'Non fai parte di questo reparto'; end if;
  if my_role = 'coordinator' and not exists (
       select 1 from public.unit_members m
       where m.unit_id = p_unit and m.unit_role = 'coordinator' and m.status = 'active' and m.user_id <> me) then
    raise exception 'Sei l''unica coordinatrice: nomina prima un''altra coordinatrice';
  end if;
  delete from public.unit_availability where unit_id = p_unit and user_id = me;
  delete from public.unit_shifts where unit_id = p_unit and user_id = me;
  delete from public.unit_members where unit_id = p_unit and user_id = me;
end $$;

revoke all on function public.leave_unit(uuid) from public, anon;
grant execute on function public.leave_unit(uuid) to authenticated;
