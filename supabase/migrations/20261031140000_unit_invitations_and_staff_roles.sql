-- Ruolo operativo nel reparto (Infermiere / OSS) e inviti con link personali.
-- La coordinatrice crea un link per una persona e un ruolo: chi lo apre, dopo l'accesso,
-- entra direttamente nel reparto senza inserire il codice e senza attendere l'approvazione.
-- Il link contiene un token casuale; nel database resta solo il suo hash SHA-256.

alter table public.unit_members add column if not exists staff_role text not null default 'infermiere';
alter table public.unit_members drop constraint if exists unit_members_staff_role_check;
alter table public.unit_members add constraint unit_members_staff_role_check check (staff_role in ('infermiere','oss'));

create table if not exists public.unit_invitations (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  token_hash text not null unique check (char_length(token_hash) = 64),
  staff_role text not null default 'infermiere' check (staff_role in ('infermiere','oss')),
  label text check (label is null or char_length(label) <= 80),
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz
);
create index if not exists unit_invitations_unit_idx on public.unit_invitations(unit_id, created_at desc);

alter table public.unit_invitations enable row level security;
revoke all on public.unit_invitations from anon;

-- Solo la coordinatrice vede gli inviti del reparto; le scritture passano dalle funzioni qui sotto.
drop policy if exists unit_invitations_select on public.unit_invitations;
create policy unit_invitations_select on public.unit_invitations for select to authenticated
  using (public.is_unit_coordinator(unit_id));

-- Crea un invito (il token viene generato dal browser, qui arriva solo l'hash).
create or replace function public.create_unit_invitation(p_unit uuid, p_token_hash text, p_staff_role text default 'infermiere', p_label text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Accesso richiesto'; end if;
  if not public.is_unit_coordinator(p_unit) then raise exception 'Solo la coordinatrice può invitare'; end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then raise exception 'Invito non valido'; end if;
  if p_staff_role not in ('infermiere','oss') then raise exception 'Ruolo non valido'; end if;
  insert into public.unit_invitations(unit_id, token_hash, staff_role, label, created_by)
  values (p_unit, p_token_hash, p_staff_role, nullif(btrim(coalesce(p_label,'')), ''), (select auth.uid()))
  returning id into v_id;
  return v_id;
end $$;

-- Revoca un invito non ancora usato.
create or replace function public.revoke_unit_invitation(p_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_unit uuid;
begin
  select i.unit_id into v_unit from public.unit_invitations i where i.id = p_id;
  if v_unit is null or not public.is_unit_coordinator(v_unit) then raise exception 'Invito non trovato'; end if;
  update public.unit_invitations set revoked_at = now() where id = p_id and accepted_at is null and revoked_at is null;
end $$;

-- Anteprima per chi apre il link: reparto e ruolo, senza entrare.
create or replace function public.preview_unit_invitation(p_token_hash text)
returns table(unit_name text, staff_role text, already_member boolean)
language sql stable security definer set search_path = ''
as $$
  select u.name, i.staff_role,
         exists (select 1 from public.unit_members m where m.unit_id = i.unit_id and m.user_id = (select auth.uid()) and m.status = 'active')
  from public.unit_invitations i join public.units u on u.id = i.unit_id
  where (select auth.uid()) is not null
    and i.token_hash = p_token_hash and i.accepted_at is null and i.revoked_at is null and i.expires_at > now();
$$;

-- Accetta l'invito: entra subito nel reparto con il ruolo indicato dalla coordinatrice.
create or replace function public.accept_unit_invitation(p_token_hash text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); inv public.unit_invitations%rowtype;
begin
  if v_uid is null then raise exception 'Accedi prima di accettare un invito'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.approval_status = 'approved') then
    raise exception 'Il tuo account non è ancora abilitato';
  end if;
  if p_token_hash is null or char_length(p_token_hash) <> 64 then raise exception 'Invito non valido'; end if;
  select * into inv from public.unit_invitations i
   where i.token_hash = p_token_hash and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
   for update;
  if not found then raise exception 'Invito non valido, scaduto o già usato'; end if;
  if exists (select 1 from public.unit_members m where m.unit_id = inv.unit_id and m.user_id = v_uid and (m.status = 'active' or m.unit_role = 'coordinator')) then
    raise exception 'Fai già parte di questo reparto';
  end if;
  insert into public.unit_members(unit_id, user_id, unit_role, status, staff_role)
  values (inv.unit_id, v_uid, 'nurse', 'active', inv.staff_role)
  on conflict (unit_id, user_id) do update set status = 'active', staff_role = excluded.staff_role
    where public.unit_members.unit_role = 'nurse';
  update public.unit_invitations set accepted_by = v_uid, accepted_at = now() where id = inv.id;
  return inv.unit_id;
end $$;

-- Ingresso con codice: ora indica anche il ruolo (resta in attesa di approvazione).
drop function if exists public.request_join_unit(text);
create or replace function public.request_join_unit(p_code text, p_staff_role text default 'infermiere')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_unit uuid;
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  if p_staff_role not in ('infermiere','oss') then raise exception 'Ruolo non valido'; end if;
  select u.id into v_unit from public.units u where u.join_code = upper(btrim(p_code));
  if v_unit is null then raise exception 'Codice reparto non valido'; end if;
  if exists (select 1 from public.unit_members m where m.unit_id = v_unit and m.user_id = v_uid) then
    raise exception 'Hai già richiesto o ottenuto l''accesso a questo reparto';
  end if;
  insert into public.unit_members (unit_id, user_id, unit_role, status, staff_role) values (v_unit, v_uid, 'nurse', 'pending', p_staff_role);
  return v_unit;
end $$;

-- Elenco del reparto con il ruolo (infermiere / OSS).
drop function if exists public.get_unit_roster(uuid);
create or replace function public.get_unit_roster(p_unit uuid)
returns table(user_id uuid, display_name text, unit_role text, status text, staff_role text)
language sql stable security definer set search_path = ''
as $$
  select m.user_id,
         coalesce(nullif(btrim(p.display_name), ''), nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Utente') as display_name,
         m.unit_role, m.status, m.staff_role
  from public.unit_members m left join public.profiles p on p.id = m.user_id
  where m.unit_id = p_unit
    and (public.is_unit_coordinator(p_unit) or (public.is_unit_member(p_unit) and m.status = 'active'))
  order by (m.unit_role = 'coordinator') desc, display_name;
$$;

-- Come prima, più il cambio di ruolo (role_infermiere / role_oss).
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
  elsif p_action in ('role_infermiere', 'role_oss') then
    update public.unit_members set staff_role = substr(p_action, 6) where unit_id = p_unit and user_id = p_user;
  elsif p_action in ('reject', 'remove') then
    if p_user = (select auth.uid()) then raise exception 'Non puoi rimuovere te stessa'; end if;
    delete from public.unit_members where unit_id = p_unit and user_id = p_user;
    delete from public.unit_shifts where unit_id = p_unit and user_id = p_user;
    delete from public.unit_availability where unit_id = p_unit and user_id = p_user;
  else
    raise exception 'Azione non valida';
  end if;
end $$;

revoke all on function public.create_unit_invitation(uuid, text, text, text) from public, anon;
revoke all on function public.revoke_unit_invitation(uuid) from public, anon;
revoke all on function public.preview_unit_invitation(text) from public, anon;
revoke all on function public.accept_unit_invitation(text) from public, anon;
revoke all on function public.request_join_unit(text, text) from public, anon;
revoke all on function public.get_unit_roster(uuid) from public, anon;
grant execute on function public.create_unit_invitation(uuid, text, text, text) to authenticated;
grant execute on function public.revoke_unit_invitation(uuid) to authenticated;
grant execute on function public.preview_unit_invitation(text) to authenticated;
grant execute on function public.accept_unit_invitation(text) to authenticated;
grant execute on function public.request_join_unit(text, text) to authenticated;
grant execute on function public.get_unit_roster(uuid) to authenticated;
