create or replace function public.get_shift_group_members(p_group_id uuid)
returns table(user_id uuid, display_name text, member_role text, joined_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.approval_status = 'approved' and p.role in ('admin','nurse')
  ) then raise exception 'Account non abilitato'; end if;
  if not exists (select 1 from public.shift_group_members m where m.group_id = p_group_id and m.user_id = auth.uid()) then
    raise exception 'Non sei membro di questo gruppo';
  end if;
  return query
  select m.user_id, p.display_name, m.member_role, m.joined_at
  from public.shift_group_members m join public.profiles p on p.id = m.user_id
  where m.group_id = p_group_id and p.approval_status = 'approved' and p.role in ('admin','nurse')
  order by case m.member_role when 'owner' then 0 when 'admin' then 1 else 2 end, p.display_name;
end;
$$;
revoke all on function public.get_shift_group_members(uuid) from public, anon;
grant execute on function public.get_shift_group_members(uuid) to authenticated;

create or replace function public.get_group_shared_shifts(p_group_id uuid, p_from date, p_to date)
returns table(group_id uuid, shift_id uuid, owner_id uuid, owner_name text, shift_date date, code text, start_time time, end_time time, site_name text, site_department text)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or p_from is null or p_to is null or p_to < p_from then raise exception 'Richiesta non valida'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Account non abilitato';
  end if;
  if not exists (select 1 from public.shift_group_members m where m.group_id = p_group_id and m.user_id = auth.uid()) then raise exception 'Non sei membro di questo gruppo'; end if;
  return query
  select p_group_id, s.id, s.user_id, p.display_name,
    s.shift_date, case when gs.show_type then s.code else null end,
    case when gs.show_time then s.start_time else null end,
    case when gs.show_time then s.end_time else null end,
    case when gs.show_site then ws.name else null end,
    case when gs.show_site then ws.department else null end
  from public.shifts s
  join public.shift_group_members gm on gm.group_id = p_group_id and gm.user_id = s.user_id
  join public.shift_group_sharing_settings gs on gs.group_id = p_group_id and gs.owner_id = s.user_id
  join public.profiles p on p.id = s.user_id and p.approval_status = 'approved' and p.role in ('admin','nurse')
  left join public.shift_group_sharing_exceptions ex on ex.group_id = p_group_id and ex.shift_id = s.id and ex.owner_id = s.user_id
  left join public.work_sites ws on ws.id = s.site_id and ws.user_id = s.user_id
  where s.shift_date between p_from and p_to
    and (gs.share_enabled or ex.effect = 'include')
    and coalesce(ex.effect, '') <> 'exclude'
  order by s.shift_date, s.start_time;
end;
$$;
revoke all on function public.get_group_shared_shifts(uuid,date,date) from public, anon;
grant execute on function public.get_group_shared_shifts(uuid,date,date) to authenticated;

create or replace function public.accept_shift_group_invitation(p_token_hash text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_email text; v_group_id uuid;
begin
  if v_user_id is null then raise exception 'Accedi prima di accettare un invito'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Il tuo account deve essere approvato come collaboratore prima di entrare in un gruppo';
  end if;
  if p_token_hash is null or length(p_token_hash) <> 64 then raise exception 'Invito non valido'; end if;
  select lower(u.email) into v_email from auth.users u where u.id = v_user_id and u.email_confirmed_at is not null;
  if v_email is null then raise exception 'Conferma prima il tuo indirizzo email'; end if;
  select i.group_id into v_group_id
  from public.shift_group_invitations i
  where i.token_hash = p_token_hash and lower(i.email) = v_email
    and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
  order by i.created_at desc limit 1 for update;
  if v_group_id is null then raise exception 'Invito non valido, scaduto o destinato a un altro indirizzo email'; end if;
  insert into public.shift_group_members(group_id,user_id,member_role)
  values (v_group_id,v_user_id,'member')
  on conflict (group_id,user_id) do nothing;
  update public.shift_group_invitations set accepted_at=now()
  where token_hash=p_token_hash and group_id=v_group_id;
  return v_group_id;
end;
$$;
revoke all on function public.accept_shift_group_invitation(text) from public, anon;
grant execute on function public.accept_shift_group_invitation(text) to authenticated;
