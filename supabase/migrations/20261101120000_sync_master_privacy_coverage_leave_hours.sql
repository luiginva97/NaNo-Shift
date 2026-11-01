-- 1) Riallinea il repository allo stato reale di produzione (privacy Master) e
--    sostituisce gli effetti della migrazione 20261031220000, che reintroduceva
--    la visibilità del Master sui dati dei reparti.
-- 2) Fabbisogno minimo per turno, ore contrattuali, richieste ferie/permessi,
--    rubrica con numero di telefono condiviso solo con consenso.
-- Idempotente: si può rieseguire.

create schema if not exists private;

-- ---------- 1. Privacy Master (stato di produzione) ----------
drop policy if exists "units_select_master" on public.units;

create or replace function public.is_unit_member(p_unit uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select not private.is_master() and exists (
    select 1 from public.unit_members m
    where m.unit_id = p_unit and m.user_id = (select auth.uid()) and m.status = 'active'
  );
$$;

create or replace function public.is_unit_coordinator(p_unit uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select not private.is_master() and exists (
    select 1 from public.unit_members m
    join public.units u on u.id = m.unit_id
    where m.unit_id = p_unit and m.user_id = (select auth.uid())
      and m.status = 'active' and m.unit_role = 'coordinator'
      and u.approval_status = 'approved'
  );
$$;

create or replace function public.get_my_units()
returns table(unit_id uuid, name text, unit_role text, status text, join_code text)
language sql stable security definer set search_path = ''
as $$
  select u.id, u.name, m.unit_role, m.status,
         case when m.unit_role = 'coordinator' and m.status = 'active'
                    and u.approval_status = 'approved' then u.join_code end
  from public.unit_members m
  join public.units u on u.id = m.unit_id
  where m.user_id = (select auth.uid())
    and u.approval_status <> 'rejected'
    and not private.is_master()
  order by u.name;
$$;

create or replace function public.get_unit_roster_with_phone(p_unit uuid)
returns table(user_id uuid, display_name text, unit_role text, status text, staff_role text, phone text)
language sql stable security definer set search_path = ''
as $$
  select m.user_id,
         coalesce(nullif(btrim(p.display_name),''),nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Utente'),
         m.unit_role, m.status, m.staff_role,
         case when public.is_unit_coordinator(p_unit) then p.phone else null end
  from public.unit_members m
  left join public.profiles p on p.id = m.user_id
  where m.unit_id = p_unit
    and (public.is_unit_coordinator(p_unit)
         or (public.is_unit_member(p_unit) and m.status = 'active'))
  order by (m.unit_role = 'coordinator') desc, 2;
$$;

-- ---------- 2. Fabbisogno minimo e ore contrattuali ----------
alter table public.units add column if not exists coverage jsonb not null default '{"M":0,"P":0,"G":0,"N":0}'::jsonb;
alter table public.unit_members add column if not exists weekly_hours numeric(4,1)
  check (weekly_hours is null or (weekly_hours >= 0 and weekly_hours <= 60));

create or replace function public.set_unit_coverage(p_unit uuid, p_coverage jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare k text; v int; r jsonb := '{}'::jsonb;
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  foreach k in array array['M','P','G','N'] loop
    v := coalesce((p_coverage->>k)::int, 0);
    if v < 0 or v > 50 then raise exception 'Valore non valido per il turno %', k; end if;
    r := r || jsonb_build_object(k, v);
  end loop;
  update public.units set coverage = r where id = p_unit;
end $$;

create or replace function public.set_member_hours(p_unit uuid, p_user uuid, p_hours numeric)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  update public.unit_members set weekly_hours = p_hours
  where unit_id = p_unit and user_id = p_user;
end $$;

-- Rubrica del reparto: il telefono è visibile al coordinamento, e ai colleghi
-- solo se la persona ha attivato la condivisione (profiles.feature_preferences.share_phone).
create or replace function public.get_unit_roster_full(p_unit uuid)
returns table(user_id uuid, display_name text, unit_role text, status text, staff_role text,
              phone text, weekly_hours numeric)
language sql stable security definer set search_path = ''
as $$
  select m.user_id,
         coalesce(nullif(btrim(p.display_name),''),nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Utente'),
         m.unit_role, m.status, m.staff_role,
         case when public.is_unit_coordinator(p_unit)
                or (m.user_id = (select auth.uid()))
                or (m.status = 'active' and coalesce((p.feature_preferences->>'share_phone')::boolean,false))
              then nullif(btrim(p.phone),'') end,
         case when public.is_unit_coordinator(p_unit) or m.user_id = (select auth.uid())
              then m.weekly_hours end
  from public.unit_members m
  left join public.profiles p on p.id = m.user_id
  where m.unit_id = p_unit
    and (public.is_unit_coordinator(p_unit)
         or (public.is_unit_member(p_unit) and m.status = 'active'))
  order by (m.unit_role = 'coordinator') desc, 2;
$$;

-- ---------- 3. Ferie e permessi ----------
create table if not exists public.unit_leave_requests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  kind text not null default 'ferie' check (kind in ('ferie','permesso','altro')),
  note text check (note is null or char_length(note) <= 200),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date and end_date - start_date <= 60)
);
create index if not exists unit_leave_requests_unit_idx on public.unit_leave_requests(unit_id, status, start_date);
alter table public.unit_leave_requests enable row level security;

drop policy if exists unit_leave_select on public.unit_leave_requests;
create policy unit_leave_select on public.unit_leave_requests for select to authenticated
using (user_id = (select auth.uid()) or public.is_unit_coordinator(unit_id));

create or replace function public.create_unit_leave(p_unit uuid, p_start date, p_end date, p_kind text, p_note text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.is_unit_member(p_unit) then raise exception 'Non fai parte di questo reparto'; end if;
  insert into public.unit_leave_requests(unit_id,user_id,start_date,end_date,kind,note)
  values (p_unit,(select auth.uid()),p_start,p_end,coalesce(p_kind,'ferie'),nullif(btrim(coalesce(p_note,'')),''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_unit_leave(p_request uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  update public.unit_leave_requests set status='cancelled'
  where id=p_request and user_id=(select auth.uid()) and status='pending';
  if not found then raise exception 'Richiesta non annullabile'; end if;
end $$;

create or replace function public.review_unit_leave(p_request uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.unit_leave_requests%rowtype; d date;
begin
  select * into r from public.unit_leave_requests where id=p_request for update;
  if not found or r.status <> 'pending' then raise exception 'Richiesta non disponibile'; end if;
  if not public.is_unit_coordinator(r.unit_id) then raise exception 'Operazione riservata al coordinamento'; end if;
  update public.unit_leave_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewed_by=(select auth.uid()), reviewed_at=now()
   where id=p_request;
  if p_approve then
    for d in select generate_series(r.start_date, r.end_date, interval '1 day')::date loop
      insert into public.unit_availability(unit_id,user_id,day,choice,note,review_status,updated_at)
      values (r.unit_id,r.user_id,d,'OFF',left(coalesce(r.kind,'ferie'),20),'confirmed',now())
      on conflict (unit_id,user_id,day) do update
        set choice='OFF', note=excluded.note, review_status='confirmed', updated_at=now();
    end loop;
  end if;
  insert into public.user_notifications(user_id,notification_type,title,message,due_date)
  values (r.user_id,'unit_leave_review:'||p_request::text,
          case when p_approve then 'Richiesta approvata' else 'Richiesta non approvata' end,
          case when p_approve then 'La tua richiesta dal '||to_char(r.start_date,'DD/MM')||' al '||to_char(r.end_date,'DD/MM')||' è stata approvata.'
               else 'La tua richiesta dal '||to_char(r.start_date,'DD/MM')||' al '||to_char(r.end_date,'DD/MM')||' non è stata approvata.' end,
          r.start_date)
  on conflict do nothing;
end $$;

-- Avviso al personale quando i turni vengono pubblicati (solo ai membri attivi, senza dati sanitari)
create or replace function public.notify_unit_published(p_unit uuid, p_from date, p_to date)
returns integer language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  insert into public.user_notifications(user_id,notification_type,title,message,due_date)
  select m.user_id,'unit_published:'||p_unit::text||':'||to_char(p_from,'YYYYMMDD')||':'||to_char(now(),'YYYYMMDDHH24MISS'),
         'Turni pubblicati','Sono stati pubblicati i turni dal '||to_char(p_from,'DD/MM')||' al '||to_char(p_to,'DD/MM')||'.',p_from
  from public.unit_members m
  where m.unit_id=p_unit and m.status='active' and m.user_id <> (select auth.uid());
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- Permessi di esecuzione ----------
do $$
declare f text;
begin
  foreach f in array array[
    'public.set_unit_coverage(uuid,jsonb)','public.set_member_hours(uuid,uuid,numeric)',
    'public.get_unit_roster_full(uuid)','public.create_unit_leave(uuid,date,date,text,text)',
    'public.cancel_unit_leave(uuid)','public.review_unit_leave(uuid,boolean)',
    'public.notify_unit_published(uuid,date,date)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
