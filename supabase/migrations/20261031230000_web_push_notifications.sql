-- Notifiche push Web Push (nessun invio email). Le credenziali VAPID e il token cron sono custoditi in Supabase Vault.
create extension if not exists pg_net;

alter table public.user_notifications
  add column if not exists push_sent_at timestamptz;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,endpoint),
  check (endpoint like 'https://%'),
  check (char_length(endpoint) <= 2048)
);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon,authenticated;
grant select,insert,delete on public.push_subscriptions to authenticated;
drop policy if exists push_subscriptions_owner_select on public.push_subscriptions;
create policy push_subscriptions_owner_select on public.push_subscriptions
  for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists push_subscriptions_owner_insert on public.push_subscriptions;
create policy push_subscriptions_owner_insert on public.push_subscriptions
  for insert to authenticated with check(user_id=(select auth.uid()));
drop policy if exists push_subscriptions_owner_delete on public.push_subscriptions;
create policy push_subscriptions_owner_delete on public.push_subscriptions
  for delete to authenticated using(user_id=(select auth.uid()));

create or replace function public.save_push_subscription(p_endpoint text,p_p256dh text,p_auth text)
returns void language plpgsql security definer set search_path = ''
as $$
declare me uuid := (select auth.uid());
begin
  if me is null then raise exception 'Accesso richiesto'; end if;
  if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint)>2048
     or coalesce(p_p256dh,'')='' or coalesce(p_auth,'')='' then
    raise exception 'Sottoscrizione push non valida';
  end if;
  insert into public.push_subscriptions(user_id,endpoint,p256dh,auth,updated_at)
  values(me,p_endpoint,p_p256dh,p_auth,now())
  on conflict(user_id,endpoint) do update
    set p256dh=excluded.p256dh,auth=excluded.auth,updated_at=now();
end $$;

create or replace function public.delete_push_subscription(p_endpoint text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then raise exception 'Accesso richiesto'; end if;
  delete from public.push_subscriptions
  where user_id=(select auth.uid()) and endpoint=p_endpoint;
end $$;

revoke all on function public.save_push_subscription(text,text,text) from public,anon;
revoke all on function public.delete_push_subscription(text) from public,anon;
grant execute on function public.save_push_subscription(text,text,text) to authenticated;
grant execute on function public.delete_push_subscription(text) to authenticated;

do $$
begin
  if not exists(select 1 from vault.secrets where name='nanoshift_push_cron_token') then
    perform vault.create_secret(encode(gen_random_bytes(32),'hex'),'nanoshift_push_cron_token','Token interno per il job pianificato delle notifiche push');
  end if;
end $$;

create or replace function public.get_push_config()
returns table(vapid_private_key text,cron_token text)
language sql security definer set search_path = ''
as $$
  select
    (select decrypted_secret from vault.decrypted_secrets where name='nanoshift_vapid_private'),
    (select decrypted_secret from vault.decrypted_secrets where name='nanoshift_push_cron_token');
$$;
revoke all on function public.get_push_config() from public,anon,authenticated;
grant execute on function public.get_push_config() to service_role;

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
 ), thresholds as (select * from (values(90),(60),(30),(7),(1),(0)) v(days_before)),
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
