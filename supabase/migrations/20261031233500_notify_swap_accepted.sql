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
  select m.user_id,'unit_shift_swap_accepted:'||p_request::text,
         'Cambio turno da approvare',
         'Il collega ha accettato una proposta di cambio turno. Apri NaNoShift per approvare o rifiutare.',
         r.requester_shift_date
  from public.unit_members m
  where m.unit_id=r.unit_id and m.unit_role='coordinator' and m.status='active';

  insert into public.user_notifications(user_id,notification_type,title,message,due_date)
  values(r.requester_id,'unit_shift_swap_waiting:'||p_request::text,
         'Cambio turno in attesa','Il collega ha accettato. Il cambio diventerà effettivo dopo l''approvazione della coordinatrice.',r.requester_shift_date);
end $$;
revoke all on function public.respond_unit_shift_swap(uuid,boolean) from public,anon;
grant execute on function public.respond_unit_shift_swap(uuid,boolean) to authenticated;
