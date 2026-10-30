-- Adds the R (Riposo) shift type and hardens group invitations and member removal.
alter table public.shifts drop constraint if exists shifts_code_check;
alter table public.shifts add constraint shifts_code_check check (code = any (array['M','P','G','N','R']::text[]));

alter table public.shift_templates drop constraint if exists shift_templates_code_check;
alter table public.shift_templates add constraint shift_templates_code_check check (code = any (array['M','P','G','N','R','OTHER']::text[]));

create or replace function public.search_registered_users(p_query text default '')
returns table(user_id uuid, display_name text, email text)
language sql stable security definer set search_path = ''
as $$
  select p.id,
         coalesce(nullif(trim(p.display_name), ''), nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), split_part(u.email, '@', 1)),
         u.email::text
  from auth.users u join public.profiles p on p.id = u.id
  where (select auth.uid()) is not null
    and length(trim(coalesce(p_query,''))) >= 3
    and u.id <> (select auth.uid())
    and u.email_confirmed_at is not null
    and p.approval_status = 'approved' and p.role in ('admin','nurse')
    and coalesce(u.email,'') <> ''
    and (coalesce(p.display_name,'') ilike '%' || trim(p_query) || '%'
      or coalesce(p.first_name,'') ilike '%' || trim(p_query) || '%'
      or coalesce(p.last_name,'') ilike '%' || trim(p_query) || '%'
      or coalesce(u.email,'') ilike '%' || trim(p_query) || '%')
  order by 2 limit 30;
$$;
revoke all on function public.search_registered_users(text) from public;
grant execute on function public.search_registered_users(text) to authenticated;

create or replace function public.respond_to_shift_group_invitation(p_invitation_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare inv public.shift_group_invitations%rowtype; v_email text;
begin
  if (select auth.uid()) is null then raise exception 'Devi accedere per gestire un invito.'; end if;
  select lower(u.email) into v_email from auth.users u
  where u.id = (select auth.uid()) and u.email_confirmed_at is not null;
  if v_email is null then raise exception 'Conferma prima il tuo indirizzo email.'; end if;
  if not exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.approval_status = 'approved' and p.role in ('admin','nurse')) then
    raise exception 'Account non abilitato a entrare nei gruppi.';
  end if;
  select * into inv from public.shift_group_invitations i
  where i.id = p_invitation_id and lower(i.email) = v_email
    and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
  for update;
  if not found then raise exception 'Invito non trovato, già gestito o scaduto.'; end if;
  if p_accept then
    insert into public.shift_group_members(group_id,user_id,member_role)
    values(inv.group_id,(select auth.uid()),'member') on conflict (group_id,user_id) do nothing;
    update public.shift_group_invitations set accepted_at=now() where id=inv.id;
  else
    update public.shift_group_invitations set revoked_at=now() where id=inv.id;
  end if;
  return jsonb_build_object('accepted',p_accept,'group_id',inv.group_id);
end;
$$;
revoke all on function public.respond_to_shift_group_invitation(uuid,boolean) from public;
grant execute on function public.respond_to_shift_group_invitation(uuid,boolean) to authenticated;

create or replace function public.get_my_shift_group_invitations()
returns table(invitation_id uuid, group_id uuid, group_name text, invited_by_name text, created_at timestamptz, expires_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select i.id, i.group_id, g.name, coalesce(nullif(trim(p.display_name),''), 'Un collega'), i.created_at, i.expires_at
  from public.shift_group_invitations i
  join public.shift_groups g on g.id=i.group_id
  left join public.profiles p on p.id=i.invited_by
  join auth.users u on u.id=(select auth.uid())
  where (select auth.uid()) is not null and u.email_confirmed_at is not null
    and lower(i.email)=lower(u.email)
    and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
  order by i.created_at desc;
$$;
revoke all on function public.get_my_shift_group_invitations() from public;
grant execute on function public.get_my_shift_group_invitations() to authenticated;

drop policy if exists shift_group_members_delete_self_or_admin on public.shift_group_members;
create policy shift_group_members_delete_self_or_admin on public.shift_group_members
for delete to authenticated
using (
  (user_id = (select auth.uid()) and member_role <> 'owner')
  or (public.is_group_manager(group_id) and member_role <> 'owner' and user_id <> (select auth.uid()))
);
