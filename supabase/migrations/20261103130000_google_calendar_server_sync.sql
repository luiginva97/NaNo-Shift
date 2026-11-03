-- Sincronizzazione automatica e bidirezionale con Google Calendar (lato server).
-- Il token di aggiornamento Google è cifrato dalla Edge Function con una chiave custodita in Vault.
-- Nessuna di queste funzioni è accessibile a utenti o anonimi: solo service_role (Edge Function).
-- Idempotente.

create schema if not exists private;

do $$
begin
  if not exists(select 1 from vault.secrets where name='nanoshift_google_token_key') then
    perform vault.create_secret(encode(gen_random_bytes(32),'hex'),'nanoshift_google_token_key','Chiave per cifrare i token Google Calendar');
  end if;
end $$;

create or replace function public.google_get_config()
returns table(token_key text, cron_token text)
language sql stable security definer set search_path = ''
as $$
  select (select decrypted_secret from vault.decrypted_secrets where name='nanoshift_google_token_key'),
         (select decrypted_secret from vault.decrypted_secrets where name='nanoshift_push_cron_token');
$$;

create or replace function public.google_save_connection(p_user uuid, p_email text, p_cipher text, p_scope text)
returns void language sql security definer set search_path = ''
as $$
  insert into private.google_calendar_connections(user_id,google_email,refresh_token_ciphertext,granted_scope,sync_enabled,last_sync_error,updated_at)
  values (p_user,p_email,p_cipher,coalesce(p_scope,''),true,null,now())
  on conflict (user_id) do update
    set google_email=excluded.google_email, refresh_token_ciphertext=excluded.refresh_token_ciphertext,
        granted_scope=excluded.granted_scope, sync_enabled=true, last_sync_error=null, updated_at=now();
$$;

create or replace function public.google_get_connection(p_user uuid)
returns table(user_id uuid, google_email text, refresh_token_ciphertext text, sync_enabled boolean, last_sync_at timestamptz, last_sync_error text)
language sql stable security definer set search_path = ''
as $$
  select c.user_id,c.google_email,c.refresh_token_ciphertext,c.sync_enabled,c.last_sync_at,c.last_sync_error
  from private.google_calendar_connections c where c.user_id=p_user;
$$;

create or replace function public.google_list_connections(p_limit integer default 40)
returns table(user_id uuid)
language sql stable security definer set search_path = ''
as $$
  select c.user_id from private.google_calendar_connections c
  where c.sync_enabled order by c.last_sync_at nulls first limit greatest(1,least(coalesce(p_limit,40),200));
$$;

create or replace function public.google_mark_sync(p_user uuid, p_error text, p_disable boolean default false)
returns void language sql security definer set search_path = ''
as $$
  update private.google_calendar_connections
     set last_sync_at = case when p_error is null then now() else last_sync_at end,
         last_sync_error = p_error,
         sync_enabled = case when p_disable then false else sync_enabled end,
         updated_at = now()
   where user_id=p_user;
$$;

create or replace function public.google_delete_connection(p_user uuid)
returns void language sql security definer set search_path = ''
as $$ delete from private.google_calendar_connections where user_id=p_user; $$;

create or replace function public.google_create_state(p_user uuid, p_hash text)
returns void language sql security definer set search_path = ''
as $$
  delete from private.google_calendar_oauth_states where expires_at < now() - interval '1 day';
  insert into private.google_calendar_oauth_states(state_hash,user_id,expires_at) values (p_hash,p_user,now()+interval '10 minutes');
$$;

create or replace function public.google_consume_state(p_hash text)
returns uuid language sql security definer set search_path = ''
as $$
  update private.google_calendar_oauth_states set consumed_at=now()
   where state_hash=p_hash and consumed_at is null and expires_at>now()
  returning user_id;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.google_get_config()','public.google_save_connection(uuid,text,text,text)','public.google_get_connection(uuid)',
    'public.google_list_connections(integer)','public.google_mark_sync(uuid,text,boolean)','public.google_delete_connection(uuid)',
    'public.google_create_state(uuid,text)','public.google_consume_state(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- Sincronizzazione pianificata: 3 volte al giorno (06:00, 12:00, 18:00 UTC = 07/13/19 in inverno, 08/14/20 in estate)
do $$
begin
  if exists(select 1 from cron.job where jobname='nanoshift-google-calendar-sync') then
    perform cron.unschedule('nanoshift-google-calendar-sync');
  end if;
  perform cron.schedule('nanoshift-google-calendar-sync','0 6,12,18 * * *',$job$
    select net.http_post(
      url:='https://mmkdibdomjaxwqfryqcw.supabase.co/functions/v1/nanoshift-google',
      headers:=jsonb_build_object('Content-Type','application/json',
        'x-nanoshift-cron-token',(select decrypted_secret from vault.decrypted_secrets where name='nanoshift_push_cron_token')),
      body:='{"action":"cron"}'::jsonb,
      timeout_milliseconds:=120000);
  $job$);
end $$;
