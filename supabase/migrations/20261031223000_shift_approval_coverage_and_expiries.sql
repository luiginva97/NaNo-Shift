-- Approvazione della coordinatrice per i cambi turno, riepilogo copertura e scadenze documentali.
-- I file restano sempre privati: la RPC scadenze restituisce esclusivamente tipo e data,
-- escludendo l'idoneità sanitaria fino alla definizione dell'informativa e della base giuridica.

alter table public.unit_shift_swap_requests
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz;

do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.unit_shift_swap_requests'::regclass
      and contype='c' and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.unit_shift_swap_requests drop constraint %I',c.conname);
  end loop;
end $$;

alter table public.unit_shift_swap_requests
  add constraint unit_shift_swap_requests_status_check
  check (status in ('pending','pending_approval','accepted','declined','cancelled'));

create or replace function public.create_unit_shift_swap(
  p_unit uuid,p_target uuid,p_requester_date date,p_target_date date,p_message text default null
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_requester text;
  v_target text;
  v_message text;
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  if v_uid = p_target or p_requester_date = p_target_date then
    raise exception 'Seleziona un collega e due date diverse';
  end if;
  if not public.is_unit_member(p_unit)
     or not exists(select 1 from public.unit_members m where m.unit_id=p_unit and m.user_id=v_uid and m.status='active')
     or not exists(select 1 from public.unit_members m where m.unit_id=p_unit and m.user_id=p_target and m.status='active') then
    raise exception 'Entrambe le persone devono essere membri attivi del reparto';
  end if;
  if not exists(select 1 from public.unit_shifts s where s.unit_id=p_unit and s.user_id=v_uid and s.shift_date=p_requester_date and s.published=true) then
    raise exception 'Non trovo un tuo turno pubblicato nella data indicata';
  end if;
  if not exists(select 1 from public.unit_shifts s where s.unit_id=p_unit and s.user_id=p_target and s.shift_date=p_target_date and s.published=true) then
    raise exception 'Non trovo un turno pubblicato del collega nella data indicata';
  end if;

  select coalesce(nullif(btrim(p.display_name),''),nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Collega')
    into v_requester from public.profiles p where p.id=v_uid;
  select coalesce(nullif(btrim(p.display_name),''),nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Collega')
    into v_target from public.profiles p where p.id=p_target;

  insert into public.unit_shift_swap_requests(unit_id,requester_id,target_id,requester_shift_date,target_shift_date,message)
  values(p_unit,v_uid,p_target,p_requester_date,p_target_date,nullif(btrim(coalesce(p_message,'')),''))
  returning id into v_id;

  v_message := v_requester||' propone a '||v_target||' uno scambio: '||
    to_char(p_requester_date,'DD/MM/YYYY')||' ↔ '||to_char(p_target_date,'DD/MM/YYYY')||
    '. In attesa della risposta del collega.';

  insert into public.user_notifications(user_id,notification_type,title,message,due_date)
  select m.user_id,'unit_shift_swap_request:'||v_id::text,
         'Nuova richiesta di cambio turno',v_message,p_requester_date
  from public.unit_members m
  where m.unit_id=p_unit and m.unit_role='coordinator' and m.status='active';

  return v_id;
end $$;

create or replace function public.respond_unit_shift_swap(p_request uuid,p_accept boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.unit_shift_swap_requests%rowtype;
begin
  select * into r from public.unit_shift_swap_requests where id=p_request for update;
  if not found or r.status <> 'pending' then raise exception 'Richiesta non disponibile'; end if;
  if (select auth.uid()) <> r.target_id then raise exception 'Solo il collega destinatario può rispondere'; end if;

  if not p_accept then
    update public.unit_shift_swap_requests set status='declined',responded_at=now() where id=p_request;
    update public.user_notifications
       set title='Richiesta di cambio turno rifiutata',
           message=message||' Il collega ha rifiutato la proposta.'
     where notification_type='unit_shift_swap_request:'||p_request::text;
    insert into public.user_notifications(user_id,notification_type,title,message,due_date)
    values(r.requester_id,'unit_shift_swap_declined:'||p_request::text,
           'Cambio turno rifiutato','Il collega ha rifiutato la tua proposta di cambio turno.',r.requester_shift_date);
    return;
  end if;

  update public.unit_shift_swap_requests
     set status='pending_approval',responded_at=now()
   where id=p_request;

  update public.user_notifications
     set title='Cambio turno da approvare',
         message=message||' Il collega ha accettato: serve ora l''approvazione della coordinatrice.'
   where notification_type='unit_shift_swap_request:'||p_request::text;
  insert into public.user_notifications(user_id,notification_type,title,message,due_date)
  values(r.requester_id,'unit_shift_swap_waiting:'||p_request::text,
         'Cambio turno in attesa','Il collega ha accettato. Il cambio diventerà effettivo dopo l''approvazione della coordinatrice.',r.requester_shift_date);
end $$;

create or replace function public.review_unit_shift_swap(p_request uuid,p_approve boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  r public.unit_shift_swap_requests%rowtype;
  a public.unit_shifts%rowtype;
  b public.unit_shifts%rowtype;
  v_uid uuid := (select auth.uid());
  v_msg text;
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  select * into r from public.unit_shift_swap_requests where id=p_request for update;
  if not found or r.status <> 'pending_approval' then raise exception 'Richiesta non disponibile o già gestita'; end if;
  if not public.is_unit_coordinator(r.unit_id) then raise exception 'Solo la coordinatrice può approvare il cambio turno'; end if;

  if not p_approve then
    update public.unit_shift_swap_requests
       set status='declined',approved_by=v_uid,approved_at=now()
     where id=p_request;
    v_msg := 'La coordinatrice ha rifiutato lo scambio. I turni non sono stati modificati.';
  else
    select * into a from public.unit_shifts
     where unit_id=r.unit_id and user_id=r.requester_id and shift_date=r.requester_shift_date and published=true
     for update;
    select * into b from public.unit_shifts
     where unit_id=r.unit_id and user_id=r.target_id and shift_date=r.target_shift_date and published=true
     for update;
    if a.unit_id is null or b.unit_id is null then
      raise exception 'Uno dei turni non è più disponibile o non è più pubblicato';
    end if;
    if exists(select 1 from public.unit_shifts s where s.unit_id=r.unit_id and s.user_id=r.target_id and s.shift_date=r.requester_shift_date)
       or exists(select 1 from public.unit_shifts s where s.unit_id=r.unit_id and s.user_id=r.requester_id and s.shift_date=r.target_shift_date) then
      raise exception 'Uno dei colleghi ha già un altro turno in una delle date: impossibile completare lo scambio';
    end if;

    update public.unit_shifts
       set user_id=r.target_id,updated_at=now()
     where unit_id=r.unit_id and user_id=r.requester_id and shift_date=r.requester_shift_date;
    update public.unit_shifts
       set user_id=r.requester_id,updated_at=now()
     where unit_id=r.unit_id and user_id=r.target_id and shift_date=r.target_shift_date;

    update public.unit_shift_swap_requests
       set status='accepted',approved_by=v_uid,approved_at=now()
     where id=p_request;
    v_msg := 'La coordinatrice ha approvato lo scambio: i turni sono stati aggiornati.';
  end if;

  insert into public.user_notifications(user_id,notification_type,title,message,due_date)
  values
    (r.requester_id,'unit_shift_swap_review:'||p_request::text||':'||r.requester_id::text,
     case when p_approve then 'Cambio turno approvato' else 'Cambio turno rifiutato' end,v_msg,r.requester_shift_date),
    (r.target_id,'unit_shift_swap_review:'||p_request::text||':'||r.target_id::text,
     case when p_approve then 'Cambio turno approvato' else 'Cambio turno rifiutato' end,v_msg,r.target_shift_date);
end $$;

revoke all on function public.create_unit_shift_swap(uuid,uuid,date,date,text) from public,anon;
revoke all on function public.respond_unit_shift_swap(uuid,boolean) from public,anon;
revoke all on function public.review_unit_shift_swap(uuid,boolean) from public,anon;
grant execute on function public.create_unit_shift_swap(uuid,uuid,date,date,text) to authenticated;
grant execute on function public.respond_unit_shift_swap(uuid,boolean) to authenticated;
grant execute on function public.review_unit_shift_swap(uuid,boolean) to authenticated;

create or replace function public.get_unit_document_expiries(p_unit uuid)
returns table(user_id uuid,display_name text,document_type text,due_date date)
language sql stable security definer set search_path = ''
as $$
  select p.id,
         coalesce(nullif(btrim(p.display_name),''),nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Utente'),
         e.document_type,e.due_date
  from public.unit_members m
  join public.profiles p on p.id=m.user_id
  cross join lateral (
    values
      ('BLSD'::text,p.blsd_expires_on),
      ('Iscrizione Ordine'::text,p.order_expires_on),
      ('Antincendio'::text,p.fire_safety_expires_on)
  ) as e(document_type,due_date)
  where m.unit_id=p_unit and m.status='active'
    and public.is_unit_coordinator(p_unit)
    and e.due_date is not null
    and e.due_date <= current_date + 90
  order by e.due_date,display_name;
$$;
revoke all on function public.get_unit_document_expiries(uuid) from public,anon;
grant execute on function public.get_unit_document_expiries(uuid) to authenticated;
