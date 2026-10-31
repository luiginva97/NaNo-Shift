-- Sezione coordinatrice: reparti, personale, disponibilità e turni assegnati.
-- Le tabelle usano il prefisso coord_ e sono idempotenti.

create table if not exists public.coord_wards (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 100),
  join_code text not null unique,
  coordinator_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.coord_members (
  id uuid primary key default gen_random_uuid(),
  ward_id uuid not null references public.coord_wards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique (ward_id, user_id)
);

create table if not exists public.coord_availability (
  id uuid primary key default gen_random_uuid(),
  ward_id uuid not null references public.coord_wards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  preference text not null default 'free' check (preference in ('free','M','P','G','N','rest','unavailable')),
  confirmed boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (ward_id, user_id, day)
);

create table if not exists public.coord_assignments (
  id uuid primary key default gen_random_uuid(),
  ward_id uuid not null references public.coord_wards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  code text not null check (code in ('M','P','G','N','R')),
  published boolean not null default false,
  unique (ward_id, user_id, day)
);

create index if not exists coord_wards_coordinator_idx on public.coord_wards(coordinator_id);
create index if not exists coord_members_user_idx on public.coord_members(user_id);
create index if not exists coord_availability_ward_day_idx on public.coord_availability(ward_id, day);
create index if not exists coord_assignments_ward_day_idx on public.coord_assignments(ward_id, day);

alter table public.coord_wards enable row level security;
alter table public.coord_members enable row level security;
alter table public.coord_availability enable row level security;
alter table public.coord_assignments enable row level security;

-- Helper SECURITY DEFINER (evitano la ricorsione delle policy).
create or replace function public.coord_is_coordinator(p_ward uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.coord_wards w where w.id = p_ward and w.coordinator_id = (select auth.uid())); $$;

create or replace function public.coord_is_approved_member(p_ward uuid, p_user uuid default null)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.coord_members m
  where m.ward_id = p_ward and m.user_id = coalesce(p_user, (select auth.uid())) and m.status = 'approved'); $$;

revoke all on function public.coord_is_coordinator(uuid) from public, anon;
revoke all on function public.coord_is_approved_member(uuid, uuid) from public, anon;
grant execute on function public.coord_is_coordinator(uuid) to authenticated;
grant execute on function public.coord_is_approved_member(uuid, uuid) to authenticated;

-- Policy: reparti
drop policy if exists coord_wards_select on public.coord_wards;
create policy coord_wards_select on public.coord_wards for select to authenticated
  using (coordinator_id = (select auth.uid()) or public.coord_is_approved_member(id));
drop policy if exists coord_wards_update on public.coord_wards;
create policy coord_wards_update on public.coord_wards for update to authenticated
  using (coordinator_id = (select auth.uid())) with check (coordinator_id = (select auth.uid()));
drop policy if exists coord_wards_delete on public.coord_wards;
create policy coord_wards_delete on public.coord_wards for delete to authenticated
  using (coordinator_id = (select auth.uid()));

-- Policy: personale
drop policy if exists coord_members_select on public.coord_members;
create policy coord_members_select on public.coord_members for select to authenticated
  using (user_id = (select auth.uid()) or public.coord_is_coordinator(ward_id));
drop policy if exists coord_members_update on public.coord_members;
create policy coord_members_update on public.coord_members for update to authenticated
  using (public.coord_is_coordinator(ward_id)) with check (public.coord_is_coordinator(ward_id));
drop policy if exists coord_members_delete on public.coord_members;
create policy coord_members_delete on public.coord_members for delete to authenticated
  using (user_id = (select auth.uid()) or public.coord_is_coordinator(ward_id));

-- Policy: disponibilità (il personale scrive solo tramite coord_save_availability)
drop policy if exists coord_availability_select on public.coord_availability;
create policy coord_availability_select on public.coord_availability for select to authenticated
  using (user_id = (select auth.uid()) or public.coord_is_coordinator(ward_id));
drop policy if exists coord_availability_update on public.coord_availability;
create policy coord_availability_update on public.coord_availability for update to authenticated
  using (public.coord_is_coordinator(ward_id)) with check (public.coord_is_coordinator(ward_id));

-- Policy: turni assegnati (solo la coordinatrice; il personale legge tramite coord_get_schedule)
drop policy if exists coord_assignments_select on public.coord_assignments;
create policy coord_assignments_select on public.coord_assignments for select to authenticated
  using (public.coord_is_coordinator(ward_id));
drop policy if exists coord_assignments_insert on public.coord_assignments;
create policy coord_assignments_insert on public.coord_assignments for insert to authenticated
  with check (public.coord_is_coordinator(ward_id) and public.coord_is_approved_member(ward_id, user_id));
drop policy if exists coord_assignments_update on public.coord_assignments;
create policy coord_assignments_update on public.coord_assignments for update to authenticated
  using (public.coord_is_coordinator(ward_id))
  with check (public.coord_is_coordinator(ward_id) and public.coord_is_approved_member(ward_id, user_id));
drop policy if exists coord_assignments_delete on public.coord_assignments;
create policy coord_assignments_delete on public.coord_assignments for delete to authenticated
  using (public.coord_is_coordinator(ward_id));

-- Crea un reparto e restituisce id e codice di ingresso.
create or replace function public.coord_create_ward(p_name text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := (select auth.uid()); v_code text; v_id uuid; v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  if v_user is null then raise exception 'Autenticazione richiesta'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Solo gli utenti approvati possono creare un reparto';
  end if;
  if length(trim(coalesce(p_name,''))) not between 1 and 100 then raise exception 'Nome reparto non valido'; end if;
  loop
    v_code := '';
    for i in 1..6 loop v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1); end loop;
    exit when not exists (select 1 from public.coord_wards w where w.join_code = v_code);
  end loop;
  insert into public.coord_wards(name, join_code, coordinator_id) values (trim(p_name), v_code, v_user) returning id into v_id;
  return jsonb_build_object('id', v_id, 'join_code', v_code);
end;
$$;

-- Richiesta di ingresso con il codice del reparto.
create or replace function public.coord_request_join(p_code text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := (select auth.uid()); v_ward public.coord_wards%rowtype; v_name text; v_status text;
begin
  if v_user is null then raise exception 'Autenticazione richiesta'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Il tuo account deve essere approvato';
  end if;
  select * into v_ward from public.coord_wards w where w.join_code = upper(trim(coalesce(p_code,'')));
  if not found then raise exception 'Codice reparto non valido'; end if;
  if v_ward.coordinator_id = v_user then raise exception 'Sei la coordinatrice di questo reparto'; end if;
  select coalesce(nullif(trim(p.display_name), ''), nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), split_part(u.email, '@', 1))
    into v_name from public.profiles p join auth.users u on u.id = p.id where p.id = v_user;
  insert into public.coord_members(ward_id, user_id, display_name) values (v_ward.id, v_user, coalesce(v_name, 'Collega'))
  on conflict (ward_id, user_id) do nothing;
  select m.status into v_status from public.coord_members m where m.ward_id = v_ward.id and m.user_id = v_user;
  return jsonb_build_object('ward_id', v_ward.id, 'ward_name', v_ward.name, 'status', v_status);
end;
$$;

-- Reparti a cui l'utente ha chiesto di entrare (anche in attesa).
create or replace function public.coord_my_memberships()
returns table(ward_id uuid, ward_name text, status text)
language sql stable security definer set search_path = ''
as $$
  select m.ward_id, w.name, m.status
  from public.coord_members m join public.coord_wards w on w.id = m.ward_id
  where m.user_id = (select auth.uid())
  order by w.name;
$$;

-- Salvataggio disponibilità: salta i giorni già confermati dalla coordinatrice.
create or replace function public.coord_save_availability(p_ward uuid, p_rows jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := (select auth.uid()); r jsonb; n integer := 0; v_day date; v_pref text;
begin
  if v_user is null then raise exception 'Autenticazione richiesta'; end if;
  if not public.coord_is_approved_member(p_ward, v_user) then raise exception 'Non fai parte di questo reparto'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 400 then raise exception 'Richiesta non valida'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_day := (r->>'day')::date; v_pref := r->>'preference';
    if v_pref not in ('free','M','P','G','N','rest','unavailable') then raise exception 'Preferenza non valida'; end if;
    if v_day < current_date - 31 or v_day > current_date + 550 then continue; end if;
    insert into public.coord_availability(ward_id, user_id, day, preference, updated_at)
    values (p_ward, v_user, v_day, v_pref, now())
    on conflict (ward_id, user_id, day) do update set preference = excluded.preference, updated_at = now()
    where public.coord_availability.confirmed = false;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Calendario del reparto: la coordinatrice vede tutto, il personale solo i turni pubblicati.
create or replace function public.coord_get_schedule(p_ward uuid, p_from date, p_to date)
returns table(user_id uuid, display_name text, day date, code text)
language plpgsql stable security definer set search_path = ''
as $$
declare v_user uuid := (select auth.uid()); v_coord boolean;
begin
  if v_user is null then raise exception 'Autenticazione richiesta'; end if;
  v_coord := public.coord_is_coordinator(p_ward);
  if not v_coord and not public.coord_is_approved_member(p_ward, v_user) then raise exception 'Non fai parte di questo reparto'; end if;
  return query
  select a.user_id, m.display_name, a.day, a.code
  from public.coord_assignments a
  join public.coord_members m on m.ward_id = a.ward_id and m.user_id = a.user_id and m.status = 'approved'
  where a.ward_id = p_ward and a.day between p_from and p_to and (v_coord or a.published)
  order by m.display_name, a.day;
end;
$$;

-- Elenco del personale approvato visibile ai colleghi dello stesso reparto (solo nomi).
create or replace function public.coord_ward_staff(p_ward uuid)
returns table(user_id uuid, display_name text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Autenticazione richiesta'; end if;
  if not public.coord_is_coordinator(p_ward) and not public.coord_is_approved_member(p_ward) then
    raise exception 'Non fai parte di questo reparto';
  end if;
  return query select m.user_id, m.display_name from public.coord_members m
    where m.ward_id = p_ward and m.status = 'approved' order by m.display_name;
end;
$$;

revoke all on function public.coord_create_ward(text) from public, anon;
revoke all on function public.coord_request_join(text) from public, anon;
revoke all on function public.coord_my_memberships() from public, anon;
revoke all on function public.coord_save_availability(uuid, jsonb) from public, anon;
revoke all on function public.coord_get_schedule(uuid, date, date) from public, anon;
revoke all on function public.coord_ward_staff(uuid) from public, anon;
grant execute on function public.coord_create_ward(text) to authenticated;
grant execute on function public.coord_request_join(text) to authenticated;
grant execute on function public.coord_my_memberships() to authenticated;
grant execute on function public.coord_save_availability(uuid, jsonb) to authenticated;
grant execute on function public.coord_get_schedule(uuid, date, date) to authenticated;
grant execute on function public.coord_ward_staff(uuid) to authenticated;
