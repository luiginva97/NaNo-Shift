-- Contatti WhatsApp tra membri dello stesso reparto e richieste di cambio turno.
create or replace function public.get_unit_roster_with_phone(p_unit uuid)
returns table(user_id uuid, display_name text, unit_role text, status text, staff_role text, phone text)
language sql stable security definer set search_path = ''
as $$
  select m.user_id,
         coalesce(nullif(btrim(p.display_name), ''), nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Utente'),
         m.unit_role, m.status, m.staff_role, p.phone
  from public.unit_members m left join public.profiles p on p.id = m.user_id
  where m.unit_id = p_unit
    and (public.is_unit_coordinator(p_unit) or (public.is_unit_member(p_unit) and m.status = 'active'))
  order by (m.unit_role = 'coordinator') desc, display_name;
$$;
revoke all on function public.get_unit_roster_with_phone(uuid) from public, anon;
grant execute on function public.get_unit_roster_with_phone(uuid) to authenticated;

create table if not exists public.unit_shift_swap_requests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  requester_shift_date date not null,
  target_shift_date date not null,
  message text check (message is null or char_length(message) <= 300),
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint unit_shift_swap_different_people check (requester_id <> target_id),
  constraint unit_shift_swap_different_dates check (requester_shift_date <> target_shift_date)
);
create index if not exists unit_shift_swap_target_idx on public.unit_shift_swap_requests(target_id,status,created_at desc);
create index if not exists unit_shift_swap_requester_idx on public.unit_shift_swap_requests(requester_id,created_at desc);
alter table public.unit_shift_swap_requests enable row level security;
revoke all on public.unit_shift_swap_requests from anon, authenticated;
drop policy if exists unit_shift_swap_select_own on public.unit_shift_swap_requests;
create policy unit_shift_swap_select_own on public.unit_shift_swap_requests for select to authenticated
using (requester_id = (select auth.uid()) or target_id = (select auth.uid()) or public.is_unit_coordinator(unit_id));

create or replace function public.create_unit_shift_swap(p_unit uuid,p_target uuid,p_requester_date date,p_target_date date,p_message text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); v_id uuid;
begin
 if v_uid is null then raise exception 'Accesso richiesto'; end if;
 if v_uid = p_target or p_requester_date = p_target_date then raise exception 'Seleziona un collega e due date diverse'; end if;
 if not public.is_unit_member(p_unit) or not exists(select 1 from public.unit_members m where m.unit_id=p_unit and m.user_id=p_target and m.status='active') then raise exception 'Il collega non appartiene al reparto'; end if;
 if not exists(select 1 from public.unit_shifts s where s.unit_id=p_unit and s.user_id=v_uid and s.shift_date=p_requester_date and s.published=true) then raise exception 'Non trovo un tuo turno pubblicato nella data indicata'; end if;
 if not exists(select 1 from public.unit_shifts s where s.unit_id=p_unit and s.user_id=p_target and s.shift_date=p_target_date and s.published=true) then raise exception 'Non trovo un turno pubblicato del collega nella data indicata'; end if;
 insert into public.unit_shift_swap_requests(unit_id,requester_id,target_id,requester_shift_date,target_shift_date,message)
 values(p_unit,v_uid,p_target,p_requester_date,p_target_date,nullif(btrim(coalesce(p_message,'')),'')) returning id into v_id;
 return v_id;
end $$;

create or replace function public.respond_unit_shift_swap(p_request uuid,p_accept boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.unit_shift_swap_requests%rowtype; a public.unit_shifts%rowtype; b public.unit_shifts%rowtype;
begin
 select * into r from public.unit_shift_swap_requests where id=p_request for update;
 if not found or r.status <> 'pending' then raise exception 'Richiesta non disponibile'; end if;
 if (select auth.uid()) <> r.target_id then raise exception 'Solo il collega destinatario può rispondere'; end if;
 if not p_accept then update public.unit_shift_swap_requests set status='declined',responded_at=now() where id=p_request; return; end if;
 select * into a from public.unit_shifts where unit_id=r.unit_id and user_id=r.requester_id and shift_date=r.requester_shift_date and published=true for update;
 select * into b from public.unit_shifts where unit_id=r.unit_id and user_id=r.target_id and shift_date=r.target_shift_date and published=true for update;
 if a.id is null or b.id is null then raise exception 'Uno dei turni non è più disponibile'; end if;
 update public.unit_shifts set user_id=r.target_id,shift_date=r.requester_shift_date,updated_at=now() where id=a.id;
 update public.unit_shifts set user_id=r.requester_id,shift_date=r.target_shift_date,updated_at=now() where id=b.id;
 update public.unit_shift_swap_requests set status='accepted',responded_at=now() where id=p_request;
end $$;
revoke all on function public.create_unit_shift_swap(uuid,uuid,date,date,text) from public,anon;
revoke all on function public.respond_unit_shift_swap(uuid,boolean) from public,anon;
grant execute on function public.create_unit_shift_swap(uuid,uuid,date,date,text) to authenticated;
grant execute on function public.respond_unit_shift_swap(uuid,boolean) to authenticated;