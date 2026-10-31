-- Ricostruzione idempotente dello schema "reparti" già applicato sul database (migrazione unit_planning).
-- Ricavata dallo stato reale del progetto Supabase il 2026-10-31.

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 80),
  join_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.unit_members (
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  unit_role text not null default 'nurse' check (unit_role in ('coordinator','nurse')),
  status text not null default 'pending' check (status in ('pending','active')),
  created_at timestamptz not null default now(),
  primary key (unit_id, user_id)
);

create table if not exists public.unit_availability (
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  choice text not null check (choice in ('ANY','M','P','G','N','R','OFF')),
  note text check (note is null or char_length(note) <= 200),
  review_status text not null default 'pending' check (review_status in ('pending','confirmed','rejected')),
  updated_at timestamptz not null default now(),
  primary key (unit_id, user_id, day)
);

create table if not exists public.unit_shifts (
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  shift_date date not null,
  code text not null check (code in ('M','P','G','N','R')),
  published boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (unit_id, user_id, shift_date)
);

alter table public.units enable row level security;
alter table public.unit_members enable row level security;
alter table public.unit_availability enable row level security;
alter table public.unit_shifts enable row level security;

create or replace function public.is_unit_active_user(p_unit uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.unit_members m where m.unit_id = p_unit and m.user_id = p_user and m.status = 'active'); $$;

create or replace function public.is_unit_coordinator(p_unit uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.unit_members m where m.unit_id = p_unit and m.user_id = (select auth.uid()) and m.status = 'active' and m.unit_role = 'coordinator'); $$;

create or replace function public.is_unit_member(p_unit uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.unit_members m where m.unit_id = p_unit and m.user_id = (select auth.uid()) and m.status = 'active'); $$;

create or replace function public.create_unit(p_name text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.approval_status = 'approved') then
    raise exception 'Profilo non approvato';
  end if;
  insert into public.units (name, created_by) values (btrim(p_name), v_uid) returning id into v_id;
  insert into public.unit_members (unit_id, user_id, unit_role, status) values (v_id, v_uid, 'coordinator', 'active');
  return v_id;
end $$;

create or replace function public.get_my_units()
returns table(unit_id uuid, name text, unit_role text, status text, join_code text)
language sql stable security definer set search_path = ''
as $$
  select u.id, u.name, m.unit_role, m.status,
         case when m.unit_role = 'coordinator' and m.status = 'active' then u.join_code end
  from public.unit_members m join public.units u on u.id = m.unit_id
  where m.user_id = (select auth.uid())
  order by u.name;
$$;

create or replace function public.get_unit_roster(p_unit uuid)
returns table(user_id uuid, display_name text, unit_role text, status text)
language sql stable security definer set search_path = ''
as $$
  select m.user_id,
         coalesce(nullif(btrim(p.display_name), ''), nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Utente') as display_name,
         m.unit_role, m.status
  from public.unit_members m left join public.profiles p on p.id = m.user_id
  where m.unit_id = p_unit
    and (public.is_unit_coordinator(p_unit) or (public.is_unit_member(p_unit) and m.status = 'active'))
  order by (m.unit_role = 'coordinator') desc, display_name;
$$;

create or replace function public.publish_unit_shifts(p_unit uuid, p_from date, p_to date, p_published boolean)
returns integer language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Solo la coordinatrice può farlo'; end if;
  update public.unit_shifts set published = p_published, updated_at = now()
   where unit_id = p_unit and shift_date >= p_from and shift_date <= p_to;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.request_join_unit(p_code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_unit uuid;
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  select u.id into v_unit from public.units u where u.join_code = upper(btrim(p_code));
  if v_unit is null then raise exception 'Codice reparto non valido'; end if;
  if exists (select 1 from public.unit_members m where m.unit_id = v_unit and m.user_id = v_uid) then
    raise exception 'Hai già richiesto o ottenuto l''accesso a questo reparto';
  end if;
  insert into public.unit_members (unit_id, user_id, unit_role, status) values (v_unit, v_uid, 'nurse', 'pending');
  return v_unit;
end $$;

create or replace function public.review_unit_availability(p_unit uuid, p_user uuid, p_from date, p_to date, p_status text)
returns integer language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Solo la coordinatrice può farlo'; end if;
  if p_status not in ('pending', 'confirmed', 'rejected') then raise exception 'Stato non valido'; end if;
  update public.unit_availability set review_status = p_status
   where unit_id = p_unit and user_id = p_user and day >= p_from and day <= p_to;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.review_unit_member(p_unit uuid, p_user uuid, p_action text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Solo la coordinatrice può farlo'; end if;
  if p_action = 'approve' then
    update public.unit_members set status = 'active' where unit_id = p_unit and user_id = p_user;
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

-- Policy
drop policy if exists units_select on public.units;
create policy units_select on public.units for select to authenticated using (public.is_unit_member(id));
drop policy if exists units_update_coordinator on public.units;
create policy units_update_coordinator on public.units for update to authenticated
  using (public.is_unit_coordinator(id)) with check (public.is_unit_coordinator(id));
drop policy if exists units_delete_coordinator on public.units;
create policy units_delete_coordinator on public.units for delete to authenticated
  using (public.is_unit_coordinator(id) and created_by = (select auth.uid()));

drop policy if exists unit_members_select on public.unit_members;
create policy unit_members_select on public.unit_members for select to authenticated
  using (user_id = (select auth.uid()) or public.is_unit_coordinator(unit_id));
drop policy if exists unit_members_leave on public.unit_members;
create policy unit_members_leave on public.unit_members for delete to authenticated
  using (user_id = (select auth.uid()) and unit_role = 'nurse');

drop policy if exists unit_availability_select on public.unit_availability;
create policy unit_availability_select on public.unit_availability for select to authenticated
  using (user_id = (select auth.uid()) or public.is_unit_coordinator(unit_id));
drop policy if exists unit_availability_insert_own on public.unit_availability;
create policy unit_availability_insert_own on public.unit_availability for insert to authenticated
  with check (user_id = (select auth.uid()) and review_status = 'pending' and public.is_unit_member(unit_id));
drop policy if exists unit_availability_update_own on public.unit_availability;
create policy unit_availability_update_own on public.unit_availability for update to authenticated
  using (user_id = (select auth.uid()) and public.is_unit_member(unit_id))
  with check (user_id = (select auth.uid()) and review_status = 'pending' and public.is_unit_member(unit_id));
drop policy if exists unit_availability_delete_own on public.unit_availability;
create policy unit_availability_delete_own on public.unit_availability for delete to authenticated
  using (user_id = (select auth.uid()) and public.is_unit_member(unit_id));

drop policy if exists unit_shifts_select on public.unit_shifts;
create policy unit_shifts_select on public.unit_shifts for select to authenticated
  using (public.is_unit_coordinator(unit_id) or (published and public.is_unit_member(unit_id)));
drop policy if exists unit_shifts_insert_coordinator on public.unit_shifts;
create policy unit_shifts_insert_coordinator on public.unit_shifts for insert to authenticated
  with check (public.is_unit_coordinator(unit_id) and public.is_unit_active_user(unit_id, user_id));
drop policy if exists unit_shifts_update_coordinator on public.unit_shifts;
create policy unit_shifts_update_coordinator on public.unit_shifts for update to authenticated
  using (public.is_unit_coordinator(unit_id))
  with check (public.is_unit_coordinator(unit_id) and public.is_unit_active_user(unit_id, user_id));
drop policy if exists unit_shifts_delete_coordinator on public.unit_shifts;
create policy unit_shifts_delete_coordinator on public.unit_shifts for delete to authenticated
  using (public.is_unit_coordinator(unit_id));
