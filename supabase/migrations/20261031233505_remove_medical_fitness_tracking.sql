-- Rimuove la raccolta della data di idoneità sanitaria e ogni relativa notifica.
-- La verifica preliminare ha rilevato zero date, documenti, oggetti Storage e notifiche sanitari.

begin;

delete from public.user_notifications where notification_type = 'medical_fitness';
delete from public.professional_documents where document_type = 'medical_fitness';

drop function if exists public.get_my_medical_fitness_expiry();
drop function if exists public.save_my_medical_fitness_expiry(date);
drop table if exists private.medical_fitness_expiries;

alter table public.professional_documents
  drop constraint if exists professional_documents_document_type_check;
alter table public.professional_documents
  add constraint professional_documents_document_type_check
  check (document_type = any (array['blsd'::text, 'order'::text, 'fire_safety'::text, 'cv'::text, 'other'::text]));

create or replace function public.generate_professional_expiry_notifications()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_count integer := 0;
begin
  with expiries as (
    select p.id as user_id, 'blsd'::text as kind, p.blsd_expires_on as due_date, 'BLSD'::text as label
    from public.profiles p where p.blsd_expires_on is not null
    union all
    select p.id, 'order', p.order_expires_on, 'Iscrizione all''Ordine'
    from public.profiles p where p.order_expires_on is not null
    union all
    select p.id, 'fire_safety', p.fire_safety_expires_on, 'Corso antincendio'
    from public.profiles p where p.fire_safety_expires_on is not null
  ),
  thresholds as (
    select * from (values (90), (60), (30), (7), (0)) v(days_before)
  ),
  due as (
    select e.*, t.days_before, (e.due_date - current_date) as days_left
    from expiries e
    cross join thresholds t
    where e.due_date - current_date = t.days_before
  )
  insert into public.user_notifications(user_id, notification_type, title, message, due_date, days_before)
  select
    user_id,
    kind,
    label || case when days_left = 0 then ' in scadenza oggi' else ' in scadenza' end,
    case
      when days_left = 0 then label || ': la validità scade oggi.'
      else label || ': mancano ' || days_left || ' giorni alla scadenza (' || to_char(due_date, 'DD/MM/YYYY') || ').'
    end,
    due_date,
    days_before
  from due
  on conflict (user_id, notification_type, due_date, days_before) do nothing;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.generate_professional_expiry_notifications() from public, anon, authenticated;

commit;
