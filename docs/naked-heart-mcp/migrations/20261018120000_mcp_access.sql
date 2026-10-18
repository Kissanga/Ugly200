-- Naked Heart MCP, part 1 of 2: whose own AI may read the farm, what, until when, and the locks around it.
-- Part 2 (20261018120100_mcp_views.sql, generated) adds the views the AI reads.
--
-- Managed on the team page, like task responsibilities:
--   * a fixed list of AI data families (mcp.data_family), as task_subfamily is for tasks;
--   * defaults per role (mcp.role_default, or the farm's own choice in mcp.role_data), as job_bundle;
--   * per person a click adds a family (mcp.person_data) or takes a role default away
--     (mcp.person_data_off), as worker_responsibility / team_exclusion;
--   * per person the MCP tick and an end date (mcp.person).
--   A new role ai_only: a team member who is only there for their AI — never on the task pages,
--   no planned hours, no Naked Heart login, not in the team data.
--
-- How a request is served (functions/mcp):
--   1. Claude or ChatGPT sends the person's OAuth token (Supabase Auth OAuth 2.1 server).
--   2. The function checks it with Supabase Auth, then, on its own postgres connection, calls
--      mcp.begin_request(user): nobody ticked = nothing; else a request row with the farms per
--      family, valid 2 minutes, and its random id.
--   3. The AI's SQL runs on a second connection that logs in as mcp_reader (not postgres), in a
--      read-only transaction with mcp.request = that id. mcp_reader can read the mcp views and
--      nothing else; the views keep only the request's farms (mcp.farms).
--   4. The call is written to mcp.call_log.
-- The AI's text never runs on the postgres connection, and the request id cannot be guessed, so a
-- query cannot widen its own scope. Access ends at its end date, when the tick is taken off, when
-- the person leaves the team (not active), or when their families are all taken away.
--
-- Run on Supabase after: Authentication > OAuth Server enabled. Then set mcp_reader's password
-- (see STATE.md) — it is never in the repo. Safe to run again.

begin;

create schema if not exists mcp;
revoke all on schema mcp from public;
comment on schema mcp is 'Naked Heart MCP: what a person''s own AI may read (views) and who may (team page). Not exposed by the API.';

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

-- ── The AI-only role ──────────────────────────────────────────────────────────
alter table public.worker drop constraint if exists worker_role_check;
alter table public.worker add constraint worker_role_check check (role = any (array[
  'worker', 'trainee', 'technician', 'office', 'farm_assistant', 'agronomist', 'farm_manager', 'farm_admin', 'ai_only']));
comment on constraint worker_role_check on public.worker is 'ai_only (MCP): in the team only for their own AI — off the task pages, no hours, no Naked Heart login.';

-- An AI-only person never comes into tasks or capacity, whatever the team page sends.
create or replace function mcp.ai_only_worker()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.role = 'ai_only' then
    new.off_tasks := true;
    new.working_days := '{}';
    new.hours_per_day := 0;
    new.employment := 'casual';
  end if;
  return new;
end $$;
drop trigger if exists mcp_ai_only on public.worker;
-- named so it runs before the team_worker_* triggers (before-triggers run in name order)
create trigger mcp_ai_only before insert or update of role, off_tasks, working_days, hours_per_day, employment
  on public.worker for each row execute function mcp.ai_only_worker();

-- ── The fixed list of AI data families ────────────────────────────────────────
create table if not exists mcp.data_family (
  code  text primary key,
  label text not null,
  about text not null,
  sort  int not null
);
insert into mcp.data_family (code, label, about, sort) values
  ('crops',      'Crops & batches',        'crop batches, phases, targets, steady groups, learned phase lengths', 1),
  ('harvest',    'Harvests',               'harvests: quantity, grade, waste, destination', 2),
  ('tasks',      'Tasks & procedures',     'tasks, what they covered, procedures and step results, issues', 3),
  ('water',      'Nutrients & irrigation', 'recipes, irrigation cycles and runs, sump EC / pH / temperature', 4),
  ('climate',    'Climate & sensors',      'sensor readings and limits, devices, camera counts and growth', 5),
  ('pests',      'Pests & disease',        'traps and counts, scouting photos, cases, treatments, IPM library, AI opinions', 6),
  ('equipment',  'Equipment',              'assets, meters, maintenance rules', 7),
  ('purchasing', 'Purchasing & stock',     'items, suppliers, purchase requests and orders, stock', 8),
  ('sales',      'Sales & customers',      'orders, deliveries, customers (no contacts), market and reference prices', 9),
  ('costs',      'Costs',                  'costs, the platform''s AI cost, labour minutes and cost per day without names', 10),
  ('team',       'Team (personal data)',   'names, roles, hourly cost, clock-ins, minutes per person, plans, absences, skills', 11)
on conflict (code) do update set label = excluded.label, about = excluded.about, sort = excluded.sort;

-- What each role gets when the farm has not chosen otherwise.
create table if not exists mcp.role_default (
  role   text not null,
  family text not null references mcp.data_family(code) on delete cascade,
  primary key (role, family)
);
insert into mcp.role_default (role, family)
select r.role, f.code from (values
  ('farm_admin',     '{crops,harvest,tasks,water,climate,pests,equipment,purchasing,sales,costs,team}'::text[]),
  ('farm_manager',   '{crops,harvest,tasks,water,climate,pests,equipment,purchasing,sales,costs,team}'),
  ('farm_assistant', '{crops,harvest,tasks,water,climate,pests}'),
  ('agronomist',     '{crops,harvest,tasks,water,climate,pests}'),
  ('technician',     '{tasks,water,climate,equipment}'),
  ('office',         '{harvest,purchasing,sales,costs}'),
  ('worker',         '{crops,tasks}'),
  ('trainee',        '{crops,tasks}')
  -- ai_only: nothing by default, each person is clicked
) r(role, families), unnest(r.families) fam
join mcp.data_family f on f.code = fam
on conflict do nothing;

-- A farm's own choice for a role (keyed by the home farm, as job_bundle). Once saved, it replaces
-- the default for that role — also when saved empty.
create table if not exists mcp.role_saved (
  farm_id  uuid not null references public.farm(id) on delete cascade,
  role     text not null,
  saved_by uuid,
  saved_at timestamptz not null default now(),
  primary key (farm_id, role)
);
create table if not exists mcp.role_data (
  farm_id uuid not null references public.farm(id) on delete cascade,
  role    text not null,
  family  text not null references mcp.data_family(code) on delete cascade,
  primary key (farm_id, role, family)
);

-- Per person: the MCP tick and its end date; families added beyond the role, role ones taken away.
create table if not exists mcp.person (
  worker_id  uuid primary key references public.worker(id) on delete cascade,
  ai_access  boolean not null default false,
  ai_until   timestamptz,
  changed_by uuid,
  changed_at timestamptz not null default now()
);
create table if not exists mcp.person_data (
  worker_id uuid not null references public.worker(id) on delete cascade,
  family    text not null references mcp.data_family(code) on delete cascade,
  primary key (worker_id, family)
);
create table if not exists mcp.person_data_off (
  worker_id uuid not null references public.worker(id) on delete cascade,
  family    text not null references mcp.data_family(code) on delete cascade,
  primary key (worker_id, family)
);

-- One row per MCP call being served: the farms per family of the person, for 2 minutes.
create table if not exists mcp.request (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  client_id   text,
  farms       jsonb not null,        -- {"pests": [farm ids], "costs": [...]}
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
comment on table mcp.call_log is 'Every tool call a person''s AI made: who, which AI, what it asked, how many rows.';

-- The list of views, their families and what they hold (written by part 2).
create table if not exists mcp.view_area (
  view_name text primary key,
  areas     text[] not null,      -- the data families that show this view
  about     text not null,
  sort      int
);

do $$ declare t text; begin
  foreach t in array array['data_family','role_default','role_saved','role_data','person','person_data',
                           'person_data_off','request','call_log','view_area'] loop
    execute format('alter table mcp.%I enable row level security', t);
    execute format('revoke all on mcp.%I from public, anon, authenticated', t);
  end loop;
end $$;
grant select on mcp.view_area to mcp_reader;
drop policy if exists view_area_read on mcp.view_area;
create policy view_area_read on mcp.view_area for select to mcp_reader using (true);

-- ── What a person's AI may read ───────────────────────────────────────────────
create or replace function mcp.role_families(p_home uuid, p_role text)
returns setof text language sql stable security definer set search_path = '' as $$
  select rd.family from mcp.role_data rd
   where rd.farm_id = p_home and rd.role = p_role
     and exists (select 1 from mcp.role_saved s where s.farm_id = p_home and s.role = p_role)
  union
  select d.family from mcp.role_default d
   where d.role = p_role
     and not exists (select 1 from mcp.role_saved s where s.farm_id = p_home and s.role = p_role)
$$;

-- Role families minus the ones taken away, plus the ones added, in the list's order.
create or replace function mcp.person_families(p_worker uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(f.code order by f.sort), '{}')
    from mcp.data_family f
    join public.worker w on w.id = p_worker
   where (f.code in (select mcp.role_families(app.home_farm(w.farm_id), w.role))
          and not exists (select 1 from mcp.person_data_off o where o.worker_id = w.id and o.family = f.code))
      or exists (select 1 from mcp.person_data a where a.worker_id = w.id and a.family = f.code)
$$;

-- The team members a signed-in person is, whose AI access is in force: by their login, or by the
-- email on the team page when the account's email is confirmed (an AI-only person needs no login
-- set up: they sign in with that email on the consent page).
create or replace function mcp.active_people(p_user uuid)
returns table (worker_id uuid, farm_id uuid, role text, families text[], until timestamptz)
language sql stable security definer set search_path = '' as $$
  select w.id, w.farm_id, w.role, mcp.person_families(w.id), p.ai_until
    from public.worker w
    join mcp.person p on p.worker_id = w.id
   where w.active and p.ai_access and (p.ai_until is null or p.ai_until > now())
     and (w.user_id = p_user
          or (w.user_id is null and w.email is not null
              and lower(btrim(w.email)) = (select lower(u.email) from auth.users u
                                            where u.id = p_user and u.email_confirmed_at is not null
                                              and u.deleted_at is null)))
     and cardinality(mcp.person_families(w.id)) > 0
$$;

revoke all on function mcp.role_families(uuid, text), mcp.person_families(uuid), mcp.active_people(uuid)
  from public, anon, authenticated;

-- ── Opening a request (postgres connection only) ──────────────────────────────
create or replace function mcp.begin_request(p_user uuid, p_client text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_farms jsonb;
  v_orgs jsonb;
  v_info jsonb;
  v_pf jsonb;
begin
  if p_user is null then return null; end if;
  if (select count(*) from mcp.call_log c where c.user_id = p_user and c.at > now() - interval '1 minute') >= 60 then
    raise exception 'Too many requests: at most 60 a minute. Wait a minute and try again.' using errcode = 'P0001';
  end if;

  -- a person's team row covers their farm and its sister units, as on the team page
  select coalesce(jsonb_agg(jsonb_build_object('family', fam, 'farm_id', s, 'until', p.until, 'role', p.role)), '[]')
    into v_pf
    from mcp.active_people(p_user) p
    cross join lateral unnest(p.families) fam
    cross join lateral unnest(app.sisters(p.farm_id)) s;

  select coalesce(jsonb_object_agg(family, ids), '{}'), coalesce(jsonb_object_agg(family, org_ids), '{}')
    into v_farms, v_orgs
    from (select x.family, jsonb_agg(distinct x.farm_id) as ids, jsonb_agg(distinct f.org_id) as org_ids
            from jsonb_to_recordset(v_pf) x(family text, farm_id uuid, until timestamptz, role text)
            join public.farm f on f.id = x.farm_id
           group by x.family) s;
  if v_farms = '{}' then return null; end if;

  select jsonb_agg(jsonb_build_object('farm_id', f.id, 'farm', f.name, 'code', f.code, 'country', f.country,
                                      'currency', f.currency, 'timezone', f.timezone, 'role', g.roles,
                                      'families', g.families, 'until', g.until) order by f.name)
    into v_info
    from (select x.farm_id, array_agg(distinct x.family) as families, max(x.until) as until,
                 string_agg(distinct x.role, ', ') as roles
            from jsonb_to_recordset(v_pf) x(family text, farm_id uuid, until timestamptz, role text)
           group by x.farm_id) g
    join public.farm f on f.id = g.farm_id;

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

create or replace function mcp.farms(p_families text[])
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct x::uuid), '{}')
    from mcp.current_request() r, unnest(p_families) a, jsonb_array_elements_text(coalesce(r.farms -> a, '[]')) x
$$;

create or replace function mcp.orgs(p_families text[])
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct x::uuid), '{}')
    from mcp.current_request() r, unnest(p_families) a, jsonb_array_elements_text(coalesce(r.orgs -> a, '[]')) x
   where x is not null and x <> 'null'
$$;

create or replace function mcp.has_area(p_families text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select cardinality(mcp.farms(p_families)) > 0
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
                         where s.id::text = p_id and s.farm_id = any(mcp.farms('{pests}')))
    when 'trap'   then (select t.photo_data from public.trap_reading t
                         where t.id::text = p_id and t.farm_id = any(mcp.farms('{pests}')))
    when 'camera' then (select c.photo_data from public.camera_count c
                         where c.id::text = p_id and c.farm_id = any(mcp.farms('{climate,crops}')))
  end
$$;

revoke all on function mcp.current_request(), mcp.farms(text[]), mcp.orgs(text[]), mcp.has_area(text[]),
                       mcp.my_access(), mcp.photo(text, text) from public, anon, authenticated;
grant execute on function mcp.current_request(), mcp.farms(text[]), mcp.orgs(text[]), mcp.has_area(text[]),
                          mcp.my_access(), mcp.photo(text, text) to mcp_reader;

-- ── Custom access token hook ──────────────────────────────────────────────────
-- Register in Authentication > Hooks > Customize access token: postgres function public.mcp_token_hook.
-- Normal sign-ins (no client_id) are returned untouched. An OAuth token (Claude, ChatGPT…) is
-- refused when the person has no AI access in force, and otherwise gets role mcp_reader, which the
-- REST API, Storage and Realtime refuse: the token is then good only for the MCP function.
create or replace function public.mcp_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_claims jsonb := event -> 'claims';
begin
  if coalesce(v_claims ->> 'client_id', '') = '' then
    return event;
  end if;
  if not exists (select 1 from mcp.active_people((event ->> 'user_id')::uuid)) then
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

-- ── For the team page ─────────────────────────────────────────────────────────
-- Same rule as the rest of the team page: app.may_manage_people (farm admin, farm manager,
-- franchisee and franchisor admins). A call made with an OAuth token is refused: an AI cannot give
-- itself, or anyone, access.
create or replace function mcp.not_from_ai()
returns void language plpgsql stable set search_path = '' as $$
begin
  if coalesce(auth.jwt() ->> 'client_id', '') <> '' or coalesce(auth.jwt() ->> 'role', '') = 'mcp_reader' then
    raise exception 'Not allowed from an AI connection.' using errcode = '42501';
  end if;
end $$;

create or replace function mcp.check_people(p_farm uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  perform mcp.not_from_ai();
  if not app.may_manage_people(p_farm) then
    raise exception 'Only who manages the people of this FarmBox may change AI access.' using errcode = '42501';
  end if;
end $$;

create or replace function mcp.check_family(p_family text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from mcp.data_family f where f.code = p_family) then
    raise exception 'There is no AI data family called %.', coalesce(p_family, '(empty)') using errcode = '22023';
  end if;
end $$;

-- No AI access left anywhere for this login: sign their AI connections out (refresh tokens end).
create or replace function mcp.sign_out_ai(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_user is not null and not exists (select 1 from mcp.active_people(p_user)) then
    delete from auth.sessions s where s.user_id = p_user and s.oauth_client_id is not null;
  end if;
end $$;

revoke all on function mcp.not_from_ai(), mcp.check_people(uuid), mcp.check_family(text), mcp.sign_out_ai(uuid)
  from public, anon, authenticated;

-- Everything the team page needs to draw the AI part: the families, each role's families, each
-- person's tick, end date and families (with what was added or taken away), and their use.
create or replace function public.mcp_team(p_farm uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_home uuid := app.home_farm(p_farm);
begin
  perform mcp.not_from_ai();
  if not app.can_read_farm(p_farm) then
    raise exception 'not a member of farm %', p_farm using errcode = '42501';
  end if;
  return jsonb_build_object(
    'may_edit', app.may_manage_people(p_farm),
    'families', (select coalesce(jsonb_agg(jsonb_build_object('code', f.code, 'label', f.label, 'about', f.about)
                                           order by f.sort), '[]') from mcp.data_family f),
    'roles', (select coalesce(jsonb_agg(jsonb_build_object(
                       'role', r.role,
                       'own', exists (select 1 from mcp.role_saved s where s.farm_id = v_home and s.role = r.role),
                       'families', (select coalesce(jsonb_agg(f.code order by f.sort), '[]') from mcp.data_family f
                                     where f.code in (select mcp.role_families(v_home, r.role))))
                     order by app.job_rank(r.role)), '[]')
                from unnest(array['farm_admin', 'farm_manager', 'farm_assistant', 'agronomist', 'technician',
                                  'office', 'worker', 'trainee', 'ai_only']) r(role)),
    'people', (select coalesce(jsonb_agg(jsonb_build_object(
                       'worker_id', w.id, 'farm_id', w.farm_id, 'name', w.name, 'surname', w.surname,
                       'role', w.role, 'active', w.active, 'email', w.email, 'has_login', w.user_id is not null,
                       'ai_access', coalesce(p.ai_access, false), 'ai_until', p.ai_until,
                       'in_force', coalesce(p.ai_access, false) and w.active and (p.ai_until is null or p.ai_until > now())
                                   and cardinality(mcp.person_families(w.id)) > 0,
                       'families', to_jsonb(mcp.person_families(w.id)),
                       'added', (select coalesce(jsonb_agg(a.family), '[]') from mcp.person_data a where a.worker_id = w.id),
                       'taken_away', (select coalesce(jsonb_agg(o.family), '[]') from mcp.person_data_off o where o.worker_id = w.id),
                       'last_used', l.last_used, 'calls_30d', coalesce(l.calls, 0), 'ai_names', l.ai_names)
                     order by app.job_rank(w.role), w.name), '[]')
                 from public.worker w
                 left join mcp.person p on p.worker_id = w.id
                 left join lateral (
                   select max(c.at) as last_used, count(*) filter (where c.at > now() - interval '30 days') as calls,
                          array_remove(array_agg(distinct c.client_name), null) as ai_names
                     from mcp.call_log c
                    where c.user_id is not null
                      and c.user_id in (select w.user_id union
                                        select u.id from auth.users u where w.user_id is null
                                           and lower(u.email) = lower(btrim(w.email)))
                      and c.farm_ids && app.sisters(v_home)
                 ) l on true
                where w.farm_id = any (app.sisters(v_home))));
end $$;

-- A role's families for this farm (and its sisters): the clicked list replaces the default.
create or replace function public.mcp_set_role(p_farm uuid, p_role text, p_families text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_home uuid := app.home_farm(p_farm);
  v_f text;
begin
  perform mcp.check_people(p_farm);
  if p_role not in ('farm_admin', 'farm_manager', 'farm_assistant', 'agronomist', 'technician', 'office',
                    'worker', 'trainee', 'ai_only') then
    raise exception 'no such job: %', p_role using errcode = '22023';
  end if;
  foreach v_f in array coalesce(p_families, '{}') loop perform mcp.check_family(v_f); end loop;
  delete from mcp.role_data where farm_id = v_home and role = p_role;
  insert into mcp.role_data (farm_id, role, family)
  select distinct v_home, p_role, f from unnest(coalesce(p_families, '{}')) f;
  insert into mcp.role_saved (farm_id, role, saved_by) values (v_home, p_role, app.uid())
  on conflict (farm_id, role) do update set saved_by = excluded.saved_by, saved_at = now();
  -- people of that job who lost every family lose their AI sessions too
  perform mcp.sign_out_ai(w.user_id) from public.worker w where w.farm_id = any (app.sisters(v_home)) and w.role = p_role;
  return public.mcp_team(p_farm);
end $$;

-- Back to the standard families for a role.
create or replace function public.mcp_reset_role(p_farm uuid, p_role text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_home uuid := app.home_farm(p_farm);
begin
  perform mcp.check_people(p_farm);
  delete from mcp.role_data where farm_id = v_home and role = p_role;
  delete from mcp.role_saved where farm_id = v_home and role = p_role;
  return public.mcp_team(p_farm);
end $$;

-- One click on one family chip of one person: on = they have it, off = they do not.
create or replace function public.mcp_person_family(p_worker uuid, p_family text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  w public.worker;
  v_role_has boolean;
begin
  select * into w from public.worker where id = p_worker;
  if w.id is null then raise exception 'no such person' using errcode = 'P0002'; end if;
  perform mcp.check_people(w.farm_id);
  perform mcp.check_family(p_family);
  v_role_has := p_family in (select mcp.role_families(app.home_farm(w.farm_id), w.role));
  if p_on then
    delete from mcp.person_data_off where worker_id = w.id and family = p_family;
    if not v_role_has then
      insert into mcp.person_data (worker_id, family) values (w.id, p_family) on conflict do nothing;
    end if;
  else
    delete from mcp.person_data where worker_id = w.id and family = p_family;
    if v_role_has then                                  -- or the role would give it back
      insert into mcp.person_data_off (worker_id, family) values (w.id, p_family) on conflict do nothing;
    end if;
    perform mcp.sign_out_ai(w.user_id);
  end if;
  return jsonb_build_object('worker_id', w.id, 'families', to_jsonb(mcp.person_families(w.id)));
end $$;

-- The MCP tick and its end date. Off signs their AI out (when no other team row still gives access).
create or replace function public.mcp_set_access(p_worker uuid, p_on boolean, p_until timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  w public.worker;
begin
  select * into w from public.worker where id = p_worker;
  if w.id is null then raise exception 'no such person' using errcode = 'P0002'; end if;
  perform mcp.check_people(w.farm_id);
  if p_on and p_until is not null and p_until <= now() then
    raise exception 'The end date is already past.' using errcode = '22023';
  end if;
  if p_on and w.user_id is null and coalesce(btrim(w.email), '') = '' then
    raise exception 'Give % an email first: their AI signs in with it.', w.name using errcode = '22023';
  end if;
  insert into mcp.person (worker_id, ai_access, ai_until, changed_by)
  values (w.id, coalesce(p_on, false), case when p_on then p_until end, app.uid())
  on conflict (worker_id) do update
     set ai_access = excluded.ai_access, ai_until = excluded.ai_until,
         changed_by = excluded.changed_by, changed_at = now();
  if not coalesce(p_on, false) then
    perform mcp.sign_out_ai(w.user_id);
    perform mcp.sign_out_ai(u.id) from auth.users u
      where w.user_id is null and lower(u.email) = lower(btrim(w.email));
  end if;
  return jsonb_build_object('worker_id', w.id, 'ai_access', coalesce(p_on, false), 'ai_until', case when p_on then p_until end);
end $$;

-- Untick everybody of this farm and its sisters at once.
create or replace function public.mcp_stop_all(p_farm uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_home uuid := app.home_farm(p_farm);
  n int;
  r record;
begin
  perform mcp.check_people(p_farm);
  update mcp.person p set ai_access = false, changed_by = app.uid(), changed_at = now()
    from public.worker w
   where w.id = p.worker_id and w.farm_id = any (app.sisters(v_home)) and p.ai_access;
  get diagnostics n = row_count;
  for r in select w.user_id, w.email from public.worker w where w.farm_id = any (app.sisters(v_home)) loop
    perform mcp.sign_out_ai(r.user_id);
    perform mcp.sign_out_ai(u.id) from auth.users u where r.user_id is null and lower(u.email) = lower(btrim(r.email));
  end loop;
  return n;
end $$;

-- The last calls on a farm, newest first, for the manager to see what was asked.
create or replace function public.mcp_call_log(p_farm uuid, p_limit int default 100)
returns table (at timestamptz, email text, client_name text, tool text, args jsonb, rows int, ok boolean, error text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform mcp.check_people(p_farm);
  return query
  select c.at, c.email, c.client_name, c.tool, c.args, c.rows, c.ok, c.error
    from mcp.call_log c where c.farm_ids && app.sisters(app.home_farm(p_farm))
   order by c.at desc limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

-- For the consent page: what the signed-in person's AI may read.
create or replace function public.mcp_my_access()
returns table (farm_id uuid, farm text, families text[], ends_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select f.id, f.name, (select array_agg(distinct x) from unnest(p.families) x), p.until
    from mcp.active_people(auth.uid()) p
    cross join lateral unnest(app.sisters(p.farm_id)) s
    join public.farm f on f.id = s
   order by f.name
$$;

revoke all on function public.mcp_team(uuid), public.mcp_set_role(uuid, text, text[]), public.mcp_reset_role(uuid, text),
                       public.mcp_person_family(uuid, text, boolean), public.mcp_set_access(uuid, boolean, timestamptz),
                       public.mcp_stop_all(uuid), public.mcp_call_log(uuid, int), public.mcp_my_access() from public, anon;
grant execute on function public.mcp_team(uuid), public.mcp_set_role(uuid, text, text[]), public.mcp_reset_role(uuid, text),
                          public.mcp_person_family(uuid, text, boolean), public.mcp_set_access(uuid, boolean, timestamptz),
                          public.mcp_stop_all(uuid), public.mcp_call_log(uuid, int), public.mcp_my_access() to authenticated;

commit;
