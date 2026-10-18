-- Naked Heart MCP, part 1 of 2: who may let an AI read the farm, until when, and the locks around it.
-- Part 2 (20261018120100_mcp_views.sql, generated) adds the views the AI reads.
--
-- How a request is served (functions/mcp):
--   1. Claude or ChatGPT sends the person's OAuth token (Supabase Auth OAuth 2.1 server).
--   2. The function checks it with Supabase Auth, then, on its own postgres connection, calls
--      mcp.begin_request(user): no active access row -> nothing; else a request row with the farms
--      per area, valid 2 minutes, and its random id.
--   3. The AI's SQL runs on a second connection that logs in as mcp_reader (not postgres), in a
--      read-only transaction with mcp.request = that id. mcp_reader can read the mcp views and
--      nothing else; the views keep only the request's farms (mcp.farms).
--   4. The call is written to mcp.call_log.
-- The AI's text never runs on the postgres connection, and the request id cannot be guessed, so a
-- query cannot widen its own scope. Access ends when its end date passes or a manager stops it.
--
-- Run on Supabase after: Authentication > OAuth Server enabled. Then set mcp_reader's password
-- (see STATE.md) — it is never in the repo. Safe to run again.

begin;

create schema if not exists mcp;
revoke all on schema mcp from public;
comment on schema mcp is 'Naked Heart MCP: what an outside AI may read (views) and who may let it (access). Not exposed by the API.';

-- The login the MCP function uses for the AI's SQL. No password here: set it once on Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'mcp_reader') then
    create role mcp_reader login noinherit nocreatedb nocreaterole noreplication connection limit 10;
  end if;
end $$;
alter role mcp_reader set statement_timeout = '15s';
alter role mcp_reader set idle_in_transaction_session_timeout = '30s';
alter role mcp_reader set default_transaction_read_only = on;
alter role mcp_reader set search_path = mcp;
grant usage on schema mcp to mcp_reader;
-- mcp_reader is deliberately NOT granted to authenticator: a token whose role is mcp_reader
-- (see the hook below) is refused by the REST API, Storage and Realtime outright.

-- ── Who may let an AI read which farm, and until when ──────────────────────────
create table if not exists mcp.access (
  id          uuid primary key default gen_random_uuid(),
  farm_id     uuid not null references public.farm(id) on delete cascade,
  email       text not null check (email = lower(btrim(email)) and email like '%_@_%'),
  user_id     uuid references auth.users(id) on delete set null,   -- filled at first use
  areas       text[] not null check (cardinality(areas) > 0 and areas <@ array['growing','ipm','money','team']),
  label       text,                                                -- who and why, e.g. "Jane — IPM consultant"
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,                                         -- null = until stopped
  stopped_at  timestamptz,
  stopped_by  uuid,
  given_by    uuid,
  created_at  timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);
create index if not exists mcp_access_email on mcp.access (email);
create index if not exists mcp_access_user on mcp.access (user_id);
create index if not exists mcp_access_farm on mcp.access (farm_id);
comment on table mcp.access is 'One person''s read-only AI access to one farm: the areas (growing, ipm, money, team), from when, until when, or stopped.';

-- One row per MCP call being served: the farms per area of the person, for 2 minutes.
create table if not exists mcp.request (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  client_id   text,
  farms       jsonb not null,        -- {"ipm": [farm ids], "money": [...]}
  orgs        jsonb not null,        -- same, organisations of those farms
  info        jsonb not null,        -- what the person may see, for the describe tool
  expires_at  timestamptz not null default now() + interval '2 minutes'
);

create table if not exists mcp.call_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  email       text,
  client_id   text,
  client_name text,
  farm_ids    uuid[] not null default '{}',
  tool        text not null,
  args        jsonb,
  rows        int,
  ms          int,
  ok          boolean not null,
  error       text
);
create index if not exists mcp_call_log_user on mcp.call_log (user_id, at desc);
create index if not exists mcp_call_log_farms on mcp.call_log using gin (farm_ids);
comment on table mcp.call_log is 'Every tool call an outside AI made: who, which AI, what it asked, how many rows.';

-- The list of views, their areas and what they hold (written by part 2).
create table if not exists mcp.view_area (
  view_name text primary key,
  areas     text[] not null,
  about     text not null,
  sort      int
);

alter table mcp.access enable row level security;
alter table mcp.request enable row level security;
alter table mcp.call_log enable row level security;
alter table mcp.view_area enable row level security;
revoke all on mcp.access, mcp.request, mcp.call_log, mcp.view_area from public, anon, authenticated;
grant select on mcp.view_area to mcp_reader;
drop policy if exists view_area_read on mcp.view_area;
create policy view_area_read on mcp.view_area for select to mcp_reader using (true);

-- ── Access rows in force for a person ─────────────────────────────────────────
-- By user id, or by the email the access was given to when the account's email is confirmed
-- (so access can be given before the person has an account).
create or replace function mcp.active_access(p_user uuid)
returns setof mcp.access language sql stable security definer set search_path = '' as $$
  select a.* from mcp.access a
   where a.stopped_at is null and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
     and (a.user_id = p_user
          or (a.user_id is null and a.email = (select lower(u.email) from auth.users u
                                                where u.id = p_user and u.email_confirmed_at is not null
                                                  and u.deleted_at is null)))
$$;
revoke all on function mcp.active_access(uuid) from public, anon, authenticated;

-- ── Opening a request (postgres connection only) ──────────────────────────────
create or replace function mcp.begin_request(p_user uuid, p_client text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_farms jsonb;
  v_orgs jsonb;
  v_info jsonb;
begin
  if p_user is null then return null; end if;
  if (select count(*) from mcp.call_log c where c.user_id = p_user and c.at > now() - interval '1 minute') >= 60 then
    raise exception 'Too many requests: at most 60 a minute. Wait a minute and try again.' using errcode = 'P0001';
  end if;

  update mcp.access a set user_id = p_user
   where a.id in (select x.id from mcp.active_access(p_user) x where x.user_id is null);

  select coalesce(jsonb_object_agg(area, ids), '{}'), coalesce(jsonb_object_agg(area, org_ids), '{}')
    into v_farms, v_orgs
    from (select ar as area, jsonb_agg(distinct x.farm_id) as ids, jsonb_agg(distinct f.org_id) as org_ids
            from mcp.active_access(p_user) x
            join public.farm f on f.id = x.farm_id
            cross join lateral unnest(x.areas) ar
           group by ar) s;
  if v_farms = '{}' then return null; end if;

  select jsonb_agg(jsonb_build_object('farm_id', f.id, 'farm', f.name, 'code', f.code, 'country', f.country,
                                      'currency', f.currency, 'timezone', f.timezone,
                                      'areas', x.areas, 'until', x.ends_at) order by f.name)
    into v_info
    from mcp.active_access(p_user) x join public.farm f on f.id = x.farm_id;

  delete from mcp.request r where r.expires_at < now() - interval '1 hour';
  insert into mcp.request (user_id, client_id, farms, orgs, info)
  values (p_user, p_client, v_farms, v_orgs, v_info)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function mcp.begin_request(uuid, text) from public, anon, authenticated;

-- ── What the views ask (run as mcp_reader, answered from the request) ─────────
create or replace function mcp.current_request()
returns mcp.request language plpgsql stable security definer set search_path = '' as $$
declare
  v_id uuid;
  v_row mcp.request;
begin
  begin
    v_id := nullif(current_setting('mcp.request', true), '')::uuid;
  exception when others then
    return null;
  end;
  if v_id is null then return null; end if;
  select * into v_row from mcp.request r where r.id = v_id and r.expires_at > now();
  return v_row;
end $$;

create or replace function mcp.farms(p_areas text[])
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct x::uuid), '{}')
    from mcp.current_request() r, unnest(p_areas) a, jsonb_array_elements_text(coalesce(r.farms -> a, '[]')) x
$$;

create or replace function mcp.orgs(p_areas text[])
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct x::uuid), '{}')
    from mcp.current_request() r, unnest(p_areas) a, jsonb_array_elements_text(coalesce(r.orgs -> a, '[]')) x
   where x is not null and x <> 'null'
$$;

create or replace function mcp.has_area(p_areas text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select cardinality(mcp.farms(p_areas)) > 0
$$;

create or replace function mcp.my_access()
returns jsonb language sql stable security definer set search_path = '' as $$
  select r.info from mcp.current_request() r
$$;

-- One photo at a time, only from a farm the request covers: a data: URL (the phone's 640 px copy).
create or replace function mcp.photo(p_kind text, p_id text)
returns text language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'scout'  then (select s.photo_data from public.scout_observation s
                         where s.id::text = p_id and s.farm_id = any(mcp.farms('{ipm}')))
    when 'trap'   then (select t.photo_data from public.trap_reading t
                         where t.id::text = p_id and t.farm_id = any(mcp.farms('{ipm}')))
    when 'camera' then (select c.photo_data from public.camera_count c
                         where c.id::text = p_id and c.farm_id = any(mcp.farms('{growing}')))
  end
$$;

revoke all on function mcp.current_request(), mcp.farms(text[]), mcp.orgs(text[]), mcp.has_area(text[]),
                       mcp.my_access(), mcp.photo(text, text) from public, anon, authenticated;
grant execute on function mcp.current_request(), mcp.farms(text[]), mcp.orgs(text[]), mcp.has_area(text[]),
                          mcp.my_access(), mcp.photo(text, text) to mcp_reader;

-- ── Custom access token hook ──────────────────────────────────────────────────
-- Register in Authentication > Hooks > Customize access token: postgres function public.mcp_token_hook.
-- Normal sign-ins (no client_id) are returned untouched. An OAuth token (Claude, ChatGPT…) is
-- refused when the person has no access in force, and otherwise gets role mcp_reader, which the
-- REST API, Storage and Realtime refuse: the token is then good only for the MCP function.
create or replace function public.mcp_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_claims jsonb := event -> 'claims';
begin
  if coalesce(v_claims ->> 'client_id', '') = '' then
    return event;
  end if;
  if not exists (select 1 from mcp.active_access((event ->> 'user_id')::uuid)) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'This account has no AI access to Naked Heart, or it has ended. Ask the farm manager.'));
  end if;
  return jsonb_build_object('claims', jsonb_set(v_claims, '{role}', '"mcp_reader"'));
exception when others then
  if coalesce(event -> 'claims' ->> 'client_id', '') = '' then
    return event;            -- never block a normal sign-in
  end if;
  return jsonb_build_object('error', jsonb_build_object('http_code', 500,
    'message', 'Naked Heart could not check the AI access. Try again later.'));
end $$;
revoke all on function public.mcp_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.mcp_token_hook(jsonb) to supabase_auth_admin;

-- ── For Naked Heart (managers): give, list, stop ──────────────────────────────
-- A call made with an OAuth token is refused: an AI cannot give itself, or anyone, access.
create or replace function mcp.not_from_ai()
returns void language plpgsql stable set search_path = '' as $$
begin
  if coalesce(auth.jwt() ->> 'client_id', '') <> '' or coalesce(auth.jwt() ->> 'role', '') = 'mcp_reader' then
    raise exception 'Not allowed from an AI connection.' using errcode = '42501';
  end if;
end $$;
revoke all on function mcp.not_from_ai() from public, anon, authenticated;

create or replace function public.mcp_access_give(p_farm uuid, p_email text, p_areas text[],
                                                  p_ends_at timestamptz default null, p_label text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(p_email));
  v_id uuid;
begin
  perform mcp.not_from_ai();
  if not app.is_farm_manager(p_farm) then
    raise exception 'Only a manager of this farm can give AI access.' using errcode = '42501';
  end if;
  if p_ends_at is not null and p_ends_at <= now() then
    raise exception 'The end date is already past.' using errcode = '22023';
  end if;
  -- One access per person and farm: giving again replaces the one in force.
  update mcp.access set stopped_at = now(), stopped_by = app.uid()
   where farm_id = p_farm and email = v_email and stopped_at is null
     and (ends_at is null or ends_at > now());
  insert into mcp.access (farm_id, email, user_id, areas, label, ends_at, given_by)
  values (p_farm, v_email,
          (select u.id from auth.users u where lower(u.email) = v_email and u.email_confirmed_at is not null
            and u.deleted_at is null limit 1),
          (select array_agg(distinct a order by a) from unnest(p_areas) a),
          nullif(btrim(p_label), ''), p_ends_at, app.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.mcp_access_stop(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row mcp.access;
begin
  perform mcp.not_from_ai();
  select * into v_row from mcp.access where id = p_id;
  if v_row.id is null or not app.is_farm_manager(v_row.farm_id) then
    raise exception 'Only a manager of this farm can stop this access.' using errcode = '42501';
  end if;
  update mcp.access set stopped_at = now(), stopped_by = app.uid() where id = p_id and stopped_at is null;
  -- No access left anywhere: sign the person's AI connections out too (their refresh tokens end).
  if v_row.user_id is not null and not exists (select 1 from mcp.active_access(v_row.user_id)) then
    delete from auth.sessions s where s.user_id = v_row.user_id and s.oauth_client_id is not null;
  end if;
end $$;

create or replace function public.mcp_access_stop_all(p_farm uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_ids uuid[];
  v_id uuid;
begin
  perform mcp.not_from_ai();
  if not app.is_farm_manager(p_farm) then
    raise exception 'Only a manager of this farm can stop AI access.' using errcode = '42501';
  end if;
  select coalesce(array_agg(id), '{}') into v_ids from mcp.access
   where farm_id = p_farm and stopped_at is null and (ends_at is null or ends_at > now());
  foreach v_id in array v_ids loop
    perform public.mcp_access_stop(v_id);
  end loop;
  return cardinality(v_ids);
end $$;

create or replace function public.mcp_access_list(p_farm uuid)
returns table (id uuid, email text, label text, areas text[], starts_at timestamptz, ends_at timestamptz,
               stopped_at timestamptz, state text, given_by text, last_used timestamptz, calls_30d int,
               ai_names text[])
language plpgsql stable security definer set search_path = '' as $$
begin
  perform mcp.not_from_ai();
  if not app.is_farm_manager(p_farm) then
    raise exception 'Only a manager of this farm can see AI access.' using errcode = '42501';
  end if;
  return query
  select a.id, a.email, a.label, a.areas, a.starts_at, a.ends_at, a.stopped_at,
         case when a.stopped_at is not null then 'stopped'
              when a.ends_at is not null and a.ends_at <= now() then 'ended'
              when a.starts_at > now() then 'not yet'
              else 'active' end,
         (select m.display_name from public.membership m where m.user_id = a.given_by
           and m.display_name is not null limit 1),
         l.last_used, coalesce(l.calls, 0)::int, l.ai_names
    from mcp.access a
    left join lateral (
      select max(c.at) as last_used, count(*) filter (where c.at > now() - interval '30 days') as calls,
             array_remove(array_agg(distinct c.client_name), null) as ai_names
        from mcp.call_log c
       where a.user_id is not null and c.user_id = a.user_id and p_farm = any(c.farm_ids)
    ) l on true
   where a.farm_id = p_farm
   order by (a.stopped_at is null and (a.ends_at is null or a.ends_at > now())) desc, a.created_at desc;
end $$;

-- The last calls on a farm, newest first, for the manager to see what was asked.
create or replace function public.mcp_call_log(p_farm uuid, p_limit int default 100)
returns table (at timestamptz, email text, client_name text, tool text, args jsonb, rows int, ok boolean, error text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform mcp.not_from_ai();
  if not app.is_farm_manager(p_farm) then
    raise exception 'Only a manager of this farm can see the AI calls.' using errcode = '42501';
  end if;
  return query
  select c.at, c.email, c.client_name, c.tool, c.args, c.rows, c.ok, c.error
    from mcp.call_log c where p_farm = any(c.farm_ids)
   order by c.at desc limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

-- For the consent page: what the signed-in person may let an AI read.
create or replace function public.mcp_my_access()
returns table (farm_id uuid, farm text, areas text[], ends_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.farm_id, f.name, a.areas, a.ends_at
    from mcp.active_access(auth.uid()) a join public.farm f on f.id = a.farm_id
   order by f.name
$$;

revoke all on function public.mcp_access_give(uuid, text, text[], timestamptz, text), public.mcp_access_stop(uuid),
                       public.mcp_access_stop_all(uuid), public.mcp_access_list(uuid),
                       public.mcp_call_log(uuid, int), public.mcp_my_access() from public, anon;
grant execute on function public.mcp_access_give(uuid, text, text[], timestamptz, text), public.mcp_access_stop(uuid),
                          public.mcp_access_stop_all(uuid), public.mcp_access_list(uuid),
                          public.mcp_call_log(uuid, int), public.mcp_my_access() to authenticated;

commit;
