create extension if not exists pg_cron;

create schema if not exists private;
alter table public.profiles
  add column if not exists tax_code text,
  add column if not exists order_registration_number text,
  add column if not exists blsd_expires_on date,
  add column if not exists order_expires_on date,
  add column if not exists fire_safety_expires_on date,
  add column if not exists medical_fitness_expires_on date,
  add column if not exists cv_path text,
  add column if not exists cv_visible_to_coordinators boolean not null default false;

create table if not exists public.professional_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null check (document_type in ('blsd','order','fire_safety','medical_fitness','cv','other')),
  file_path text not null unique,
  file_name text not null,
  content_type text not null,
  created_at timestamptz not null default now()
);
alter table public.professional_documents enable row level security;

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null,
  title text not null,
  message text not null,
  due_date date,
  days_before integer,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique(user_id, notification_type, due_date, days_before)
);
alter table public.user_notifications enable row level security;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin');
$$;
revoke all on function private.is_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_admin() to authenticated;

drop policy if exists "professional_documents_owner_select" on public.professional_documents;
create policy "professional_documents_owner_select" on public.professional_documents for select to authenticated
using (user_id=(select auth.uid()) or (select private.is_admin()));
drop policy if exists "professional_documents_owner_insert" on public.professional_documents;
create policy "professional_documents_owner_insert" on public.professional_documents for insert to authenticated
with check (user_id=(select auth.uid()));
drop policy if exists "professional_documents_owner_delete" on public.professional_documents;
create policy "professional_documents_owner_delete" on public.professional_documents for delete to authenticated
using (user_id=(select auth.uid()));

drop policy if exists "user_notifications_owner_select" on public.user_notifications;
create policy "user_notifications_owner_select" on public.user_notifications for select to authenticated
using (user_id=(select auth.uid()));
drop policy if exists "user_notifications_owner_update" on public.user_notifications;
create policy "user_notifications_owner_update" on public.user_notifications for update to authenticated
using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('professional-documents','professional-documents',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['application/pdf','image/jpeg','image/png'];

drop policy if exists "professional_docs_upload_own_folder" on storage.objects;
create policy "professional_docs_upload_own_folder" on storage.objects for insert to authenticated
with check(bucket_id='professional-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "professional_docs_read_own_folder" on storage.objects;
create policy "professional_docs_read_own_folder" on storage.objects for select to authenticated
using(bucket_id='professional-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "professional_docs_delete_own_folder" on storage.objects;
create policy "professional_docs_delete_own_folder" on storage.objects for delete to authenticated
using(bucket_id='professional-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);

create or replace function public.generate_professional_expiry_notifications()
returns integer language plpgsql security definer set search_path = ''
as $$
declare inserted_count integer := 0;
begin
 with expiries as (
  select p.id user_id,'blsd'::text kind,p.blsd_expires_on due_date,'BLSD'::text label from public.profiles p where p.blsd_expires_on is not null
  union all select p.id,'order',p.order_expires_on,'Iscrizione all''Ordine' from public.profiles p where p.order_expires_on is not null
  union all select p.id,'fire_safety',p.fire_safety_expires_on,'Corso antincendio' from public.profiles p where p.fire_safety_expires_on is not null
  union all select p.id,'medical_fitness',p.medical_fitness_expires_on,'Idoneità sanitaria' from public.profiles p where p.medical_fitness_expires_on is not null
 ), thresholds as (select * from (values(90),(60),(30),(7),(0)) v(days_before)),
 due as (
  select e.*,t.days_before,(e.due_date-current_date) days_left from expiries e cross join thresholds t
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

do $$
begin
 if not exists(select 1 from cron.job where jobname='nanoshift-professional-expiry-daily') then
  perform cron.schedule('nanoshift-professional-expiry-daily','15 6 * * *','select public.generate_professional_expiry_notifications();');
 end if;
end $$;
