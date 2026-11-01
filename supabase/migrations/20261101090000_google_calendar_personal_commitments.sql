create table if not exists public.personal_commitments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 200),
  description text,
  location text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  source text not null default 'nanoshift' check (source in ('nanoshift','google')),
  google_calendar_id text,
  google_event_id text,
  google_etag text,
  google_updated_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint personal_commitments_valid_range check (ends_at > starts_at),
  constraint personal_commitments_google_identity check (
    (google_event_id is null and google_calendar_id is null)
    or (google_event_id is not null and google_calendar_id is not null)
  )
);
create unique index if not exists personal_commitments_google_event_uidx
  on public.personal_commitments(user_id, google_calendar_id, google_event_id)
  where google_event_id is not null;
create index if not exists personal_commitments_user_start_idx
  on public.personal_commitments(user_id, starts_at)
  where deleted_at is null;
alter table public.personal_commitments enable row level security;
revoke all on public.personal_commitments from anon;
grant select, insert, update, delete on public.personal_commitments to authenticated;
drop policy if exists personal_commitments_select_own on public.personal_commitments;
create policy personal_commitments_select_own on public.personal_commitments
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists personal_commitments_insert_own on public.personal_commitments;
create policy personal_commitments_insert_own on public.personal_commitments
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists personal_commitments_update_own on public.personal_commitments;
create policy personal_commitments_update_own on public.personal_commitments
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists personal_commitments_delete_own on public.personal_commitments;
create policy personal_commitments_delete_own on public.personal_commitments
  for delete to authenticated using ((select auth.uid()) = user_id);

create table if not exists private.google_calendar_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  google_email text,
  refresh_token_ciphertext text not null,
  granted_scope text not null,
  sync_token text,
  sync_enabled boolean not null default true,
  last_sync_at timestamptz,
  last_sync_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.google_calendar_connections enable row level security;
revoke all on private.google_calendar_connections from public, anon, authenticated;
grant all on private.google_calendar_connections to service_role;

create table if not exists private.google_calendar_oauth_states (
  state_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table private.google_calendar_oauth_states enable row level security;
revoke all on private.google_calendar_oauth_states from public, anon, authenticated;
grant all on private.google_calendar_oauth_states to service_role;

comment on table public.personal_commitments is 'Personal appointments, separate from work shifts and unit planning. Google Calendar sync is per user.';
comment on table private.google_calendar_connections is 'Server-only Google OAuth connection metadata. Refresh tokens are encrypted by the Edge Function before storage.';
comment on table private.google_calendar_oauth_states is 'Single-use OAuth state values for Google Calendar authorization.';
