-- Isola la data di idoneità sanitaria dal profilo ordinario e impedisce l'accesso ai relativi file.
-- In attesa di informativa, base giuridica e retention approvate, i file di idoneità non sono caricabili
-- e la data resta consultabile esclusivamente dall'interessato.

create schema if not exists private;

create table if not exists private.medical_fitness_expiries (
  user_id uuid primary key references auth.users(id) on delete cascade,
  expires_on date,
  updated_at timestamptz not null default now()
);
alter table private.medical_fitness_expiries enable row level security;
drop policy if exists medical_fitness_expiry_owner_select on private.medical_fitness_expiries;
create policy medical_fitness_expiry_owner_select on private.medical_fitness_expiries
  for select to authenticated using (user_id=(select auth.uid()));

insert into private.medical_fitness_expiries(user_id,expires_on)
select id,medical_fitness_expires_on from public.profiles
where medical_fitness_expires_on is not null
on conflict(user_id) do update set expires_on=excluded.expires_on,updated_at=now();

create or replace function public.get_my_medical_fitness_expiry()
returns date language sql stable security definer set search_path = ''
as $$
  select e.expires_on from private.medical_fitness_expiries e
  where e.user_id=(select auth.uid());
$$;

create or replace function public.save_my_medical_fitness_expiry(p_date date)
returns void language plpgsql security definer set search_path = ''
as $$
declare me uuid := (select auth.uid());
begin
  if me is null then raise exception 'Accesso richiesto'; end if;
  if p_date is null then
    delete from private.medical_fitness_expiries where user_id=me;
  else
    insert into private.medical_fitness_expiries(user_id,expires_on,updated_at)
    values(me,p_date,now())
    on conflict(user_id) do update set expires_on=excluded.expires_on,updated_at=now();
  end if;
end $$;

revoke all on function public.get_my_medical_fitness_expiry() from public,anon;
revoke all on function public.save_my_medical_fitness_expiry(date) from public,anon;
grant execute on function public.get_my_medical_fitness_expiry() to authenticated;
grant execute on function public.save_my_medical_fitness_expiry(date) to authenticated;

create or replace function public.generate_professional_expiry_notifications()
returns integer language plpgsql security definer set search_path = ''
as $$
declare inserted_count integer := 0;
begin
 with expiries as (
  select p.id user_id,'blsd'::text kind,p.blsd_expires_on due_date,'BLSD'::text label
    from public.profiles p where p.blsd_expires_on is not null
  union all
  select p.id,'order',p.order_expires_on,'Iscrizione all''Ordine'
    from public.profiles p where p.order_expires_on is not null
  union all
  select p.id,'fire_safety',p.fire_safety_expires_on,'Corso antincendio'
    from public.profiles p where p.fire_safety_expires_on is not null
  union all
  select e.user_id,'medical_fitness',e.expires_on,'Idoneità sanitaria'
    from private.medical_fitness_expiries e where e.expires_on is not null
 ), thresholds as (select * from (values(90),(60),(30),(7),(0)) v(days_before)),
 due as (
  select e.*,t.days_before,(e.due_date-current_date) days_left
  from expiries e cross join thresholds t
  where e.due_date-current_date=t.days_before
 )
 insert into public.user_notifications(user_id,notification_type,title,message,due_date,days_before)
 select user_id,kind,label||case when days_left=0 then ' in scadenza oggi' else ' in scadenza' end,
  case when days_left=0 then label||': la validità scade oggi.'
       else label||': mancano '||days_left||' giorni alla scadenza ('||to_char(due_date,'DD/MM/YYYY')||').' end,
  due_date,days_before
 from due on conflict(user_id,notification_type,due_date,days_before) do nothing;
 get diagnostics inserted_count=row_count;
 return inserted_count;
end $$;
revoke all on function public.generate_professional_expiry_notifications() from public,anon,authenticated;

alter table public.profiles drop column if exists medical_fitness_expires_on;

drop policy if exists professional_documents_owner_select on public.professional_documents;
create policy professional_documents_owner_select on public.professional_documents
  for select to authenticated using (user_id=(select auth.uid()));

drop policy if exists professional_documents_owner_insert on public.professional_documents;
create policy professional_documents_owner_insert on public.professional_documents
  for insert to authenticated with check (
    user_id=(select auth.uid()) and document_type <> 'medical_fitness'
  );

drop policy if exists professional_docs_upload_own_folder on storage.objects;
create policy professional_docs_upload_own_folder on storage.objects
  for insert to authenticated with check (
    bucket_id='professional-documents'
    and (storage.foldername(name))[1]=(select auth.uid())::text
    and coalesce((storage.foldername(name))[2],'') <> 'medical_fitness'
  );
