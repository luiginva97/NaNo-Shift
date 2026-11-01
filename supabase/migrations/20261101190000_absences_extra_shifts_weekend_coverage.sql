-- Assenze a più giorni (barre rosse nel piano), turni in altri reparti / extra,
-- fabbisogno diverso per weekend, turno combinato (es. MN) e nota per cella.
-- Privacy: le assenze registrano solo il tipo generico (ferie, permesso, assenza):
-- niente motivi sanitari. Visibili solo al coordinamento e alla persona interessata.
-- Idempotente.

-- ---------- Nota e secondo turno nella stessa giornata ----------
alter table public.unit_shifts add column if not exists code2 text;
alter table public.unit_shifts add column if not exists note text;
alter table public.unit_shifts drop constraint if exists unit_shifts_code2_check;
alter table public.unit_shifts add constraint unit_shifts_code2_check
  check (code2 is null or (code2 in ('M','P','G','N') and code2 <> code));
alter table public.unit_shifts drop constraint if exists unit_shifts_note_check;
alter table public.unit_shifts add constraint unit_shifts_note_check
  check (note is null or char_length(note) <= 30);

-- ---------- Fabbisogno weekend ----------
alter table public.units add column if not exists coverage_we jsonb not null default '{"M":0,"P":0,"G":0,"N":0}'::jsonb;

create or replace function public.set_unit_coverage_we(p_unit uuid, p_coverage jsonb)
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
  update public.units set coverage_we = r where id = p_unit;
end $$;

-- ---------- Assenze ----------
create table if not exists public.unit_absences (
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('ferie','permesso','assenza')),
  note text check (note is null or char_length(note) <= 60),
  created_by uuid references auth.users(id) on delete set null,
  primary key (unit_id, user_id, day)
);
alter table public.unit_absences enable row level security;
drop policy if exists unit_absences_select on public.unit_absences;
create policy unit_absences_select on public.unit_absences for select to authenticated
using (user_id = (select auth.uid()) or public.is_unit_coordinator(unit_id));

create or replace function public.set_unit_absence(p_unit uuid, p_user uuid, p_start date, p_end date, p_kind text, p_note text default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  if p_end < p_start or p_end - p_start > 92 then raise exception 'Intervallo di date non valido'; end if;
  if not exists (select 1 from public.unit_members m where m.unit_id=p_unit and m.user_id=p_user and m.status='active') then
    raise exception 'La persona non fa parte del reparto';
  end if;
  insert into public.unit_absences(unit_id,user_id,day,kind,note,created_by)
  select p_unit,p_user,d::date,p_kind,nullif(btrim(coalesce(p_note,'')),''),(select auth.uid())
  from generate_series(p_start,p_end,interval '1 day') d
  on conflict (unit_id,user_id,day) do update set kind=excluded.kind, note=excluded.note, created_by=excluded.created_by;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.clear_unit_absence(p_unit uuid, p_user uuid, p_start date, p_end date)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  delete from public.unit_absences where unit_id=p_unit and user_id=p_user and day between p_start and p_end;
end $$;

-- L'approvazione di ferie/permessi crea anche l'assenza nel piano
create or replace function public.review_unit_leave(p_request uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.unit_leave_requests%rowtype; d date; v_kind text;
begin
  select * into r from public.unit_leave_requests where id=p_request for update;
  if not found or r.status <> 'pending' then raise exception 'Richiesta non disponibile'; end if;
  if not public.is_unit_coordinator(r.unit_id) then raise exception 'Operazione riservata al coordinamento'; end if;
  update public.unit_leave_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewed_by=(select auth.uid()), reviewed_at=now()
   where id=p_request;
  if p_approve then
    v_kind := case r.kind when 'ferie' then 'ferie' when 'permesso' then 'permesso' else 'assenza' end;
    for d in select generate_series(r.start_date, r.end_date, interval '1 day')::date loop
      insert into public.unit_availability(unit_id,user_id,day,choice,note,review_status,updated_at)
      values (r.unit_id,r.user_id,d,'OFF',left(coalesce(r.kind,'ferie'),20),'confirmed',now())
      on conflict (unit_id,user_id,day) do update
        set choice='OFF', note=excluded.note, review_status='confirmed', updated_at=now();
      insert into public.unit_absences(unit_id,user_id,day,kind,created_by)
      values (r.unit_id,r.user_id,d,v_kind,(select auth.uid()))
      on conflict (unit_id,user_id,day) do update set kind=excluded.kind;
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

-- ---------- Turni in altri reparti / extra ----------
create table if not exists public.unit_extra_shifts (
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  shift_date date not null,
  label text not null check (char_length(btrim(label)) between 1 and 20),
  code text not null default '' check (char_length(code) <= 6),
  hours numeric(4,1) not null default 0 check (hours >= 0 and hours <= 24),
  primary key (unit_id, user_id, shift_date, label)
);
alter table public.unit_extra_shifts enable row level security;
drop policy if exists unit_extra_select on public.unit_extra_shifts;
create policy unit_extra_select on public.unit_extra_shifts for select to authenticated
using (user_id = (select auth.uid()) or public.is_unit_coordinator(unit_id));

create or replace function public.set_unit_extra_shift(p_unit uuid, p_user uuid, p_day date, p_label text, p_code text, p_hours numeric)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  if not exists (select 1 from public.unit_members m where m.unit_id=p_unit and m.user_id=p_user and m.status='active') then
    raise exception 'La persona non fa parte del reparto';
  end if;
  insert into public.unit_extra_shifts(unit_id,user_id,shift_date,label,code,hours)
  values (p_unit,p_user,p_day,upper(btrim(p_label)),upper(btrim(coalesce(p_code,''))),coalesce(p_hours,0))
  on conflict (unit_id,user_id,shift_date,label) do update set code=excluded.code, hours=excluded.hours;
end $$;

create or replace function public.clear_unit_extra_shift(p_unit uuid, p_user uuid, p_day date, p_label text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_unit_coordinator(p_unit) then raise exception 'Operazione riservata al coordinamento'; end if;
  delete from public.unit_extra_shifts where unit_id=p_unit and user_id=p_user and shift_date=p_day and label=upper(btrim(p_label));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.set_unit_coverage_we(uuid,jsonb)','public.set_unit_absence(uuid,uuid,date,date,text,text)',
    'public.clear_unit_absence(uuid,uuid,date,date)','public.review_unit_leave(uuid,boolean)',
    'public.set_unit_extra_shift(uuid,uuid,date,text,text,numeric)','public.clear_unit_extra_shift(uuid,uuid,date,text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
