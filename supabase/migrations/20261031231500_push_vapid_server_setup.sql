-- Configurazione VAPID generata e custodita lato server, senza esporre la chiave privata.
create table if not exists private.push_settings (
  id boolean primary key default true check (id),
  vapid_public_key text,
  updated_at timestamptz not null default now()
);
alter table private.push_settings enable row level security;

drop function if exists public.get_push_config();
create or replace function public.get_push_config()
returns table(vapid_private_key text,cron_token text,vapid_public_key text)
language sql security definer set search_path = ''
as $$
  select
    (select decrypted_secret from vault.decrypted_secrets where name='nanoshift_vapid_private'),
    (select decrypted_secret from vault.decrypted_secrets where name='nanoshift_push_cron_token'),
    (select s.vapid_public_key from private.push_settings s where s.id=true);
$$;
revoke all on function public.get_push_config() from public,anon,authenticated;
grant execute on function public.get_push_config() to service_role;

create or replace function public.get_push_public_key()
returns text language sql stable security definer set search_path = ''
as $$
  select s.vapid_public_key from private.push_settings s where s.id=true;
$$;
revoke all on function public.get_push_public_key() from public,anon;
grant execute on function public.get_push_public_key() to authenticated;

create or replace function public.store_push_vapid(p_private text,p_public text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if p_private is null or p_public is null or length(p_private)<40 or length(p_public)<80 then
    raise exception 'Chiavi VAPID non valide';
  end if;
  if exists(select 1 from vault.secrets where name='nanoshift_vapid_private') then
    perform vault.update_secret(
      (select id from vault.secrets where name='nanoshift_vapid_private'),
      p_private,'nanoshift_vapid_private','Chiave privata VAPID generata dal servizio push'
    );
  else
    perform vault.create_secret(p_private,'nanoshift_vapid_private','Chiave privata VAPID generata dal servizio push');
  end if;
  insert into private.push_settings(id,vapid_public_key,updated_at)
  values(true,p_public,now())
  on conflict(id) do update set vapid_public_key=excluded.vapid_public_key,updated_at=now();
end $$;
revoke all on function public.store_push_vapid(text,text) from public,anon,authenticated;
grant execute on function public.store_push_vapid(text,text) to service_role;
