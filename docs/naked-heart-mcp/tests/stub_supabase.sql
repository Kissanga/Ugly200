-- A stand-in for the parts of Supabase the MCP migrations touch, for a throwaway local Postgres.
-- Never run this on Supabase. The public tables come from gen_stub.py (the live column lists).

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator login noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then create role supabase_auth_admin login; end if;
end $$;
grant anon, authenticated, service_role to authenticator;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  email_confirmed_at timestamptz,
  deleted_at timestamptz
);
create table auth.oauth_clients (id uuid primary key default gen_random_uuid(), client_name text);
create table auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  oauth_client_id uuid
);
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''),
                  nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;

-- The Platform's role helpers, as they read on the live database (18 Oct 2026), minus org admins.
create schema app;
grant usage on schema app to authenticated, service_role;
