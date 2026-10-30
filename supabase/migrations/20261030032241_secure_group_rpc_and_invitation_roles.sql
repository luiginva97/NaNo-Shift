create or replace function public.create_shift_group(p_name text, p_description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_group_id uuid; v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Autenticazione richiesta'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Solo gli utenti approvati possono creare gruppi';
  end if;
  if length(trim(coalesce(p_name,''))) not between 1 and 100 then raise exception 'Nome gruppo non valido'; end if;
  insert into public.shift_groups(name, description, created_by)
  values (trim(p_name), nullif(trim(coalesce(p_description,'')),''), v_user_id)
  returning id into new_group_id;
  insert into public.shift_group_members(group_id,user_id,member_role)
  values (new_group_id,v_user_id,'owner');
  return new_group_id;
end;
$$;
revoke all on function public.create_shift_group(text,text) from public, anon;
grant execute on function public.create_shift_group(text,text) to authenticated;

create or replace function public.accept_shift_group_invitation(p_token_hash text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_email text; v_group_id uuid;
begin
  if v_user_id is null then raise exception 'Accedi prima di accettare un invito'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Il tuo account deve essere approvato come collaboratore prima di entrare in un gruppo';
  end if;
  if p_token_hash is null or length(p_token_hash) <> 64 then raise exception 'Invito non valido'; end if;
  select lower(u.email) into v_email from auth.users u where u.id = v_user_id;
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

revoke all on function public.get_shift_group_members(uuid) from public, anon;
grant execute on function public.get_shift_group_members(uuid) to authenticated;
revoke all on function public.get_group_shared_shifts(uuid,date,date) from public, anon;
grant execute on function public.get_group_shared_shifts(uuid,date,date) to authenticated;
revoke all on function public.get_shared_shifts(date,date) from public, anon;
grant execute on function public.get_shared_shifts(date,date) to authenticated;
revoke all on function public.current_profile_approved() from public, anon;
grant execute on function public.current_profile_approved() to authenticated;
revoke all on function public.current_profile_role() from public, anon;
grant execute on function public.current_profile_role() to authenticated;
