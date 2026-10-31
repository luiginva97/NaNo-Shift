-- Una sottoscrizione browser appartiene a un solo account per volta.
alter table public.push_subscriptions
  drop constraint if exists push_subscriptions_user_id_endpoint_key;
alter table public.push_subscriptions
  add constraint push_subscriptions_endpoint_key unique(endpoint);

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
  on conflict(endpoint) do update
    set user_id=excluded.user_id,p256dh=excluded.p256dh,auth=excluded.auth,updated_at=now();
end $$;
revoke all on function public.save_push_subscription(text,text,text) from public,anon;
grant execute on function public.save_push_subscription(text,text,text) to authenticated;

select cron.alter_job(
  job_id:=(select jobid from cron.job where jobname='nanoshift-push-notifications-daily'),
  schedule:='*/5 * * * *'
);
