-- Part A, run as postgres after the stub and both migrations: seed two organisations, four farms
-- (A and A2 are sister units), a team with an AI-only freelancer, an office person and an
-- agronomist; tick, click, change roles, end and stop; the hook; the request rows.
-- Writes the request ids the reader tests need into test_ctx.
\set ON_ERROR_STOP on
set client_min_messages = notice;

create table test_ctx (k text primary key, v text);

create function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$
begin
  if c is not true then raise exception 'FAIL: %', msg; end if;
  raise notice 'PASS %', msg;
end $$;

-- Who is who
insert into public.organisation (id, name) values
  ('00000000-0000-0000-0000-0000000000a1', 'Org A'), ('00000000-0000-0000-0000-0000000000b1', 'Org B');
insert into public.farm (id, org_id, name, code, timezone, currency, sister_group, created_at, shop_key_last4, attributes) values
  ('00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000000a1', 'Farm A', 'FA', 'Africa/Johannesburg', 'ZAR', '00000000-0000-0000-0000-0000000005a1', now() - interval '2 days', '9999', '{"secret":"x"}'),
  ('00000000-0000-0000-0000-00000000fa02', '00000000-0000-0000-0000-0000000000a1', 'Farm A2', 'FA2', 'Africa/Johannesburg', 'ZAR', '00000000-0000-0000-0000-0000000005a1', now() - interval '1 day', null, null),
  ('00000000-0000-0000-0000-00000000f00b', '00000000-0000-0000-0000-0000000000a1', 'Farm B', 'FB', 'Africa/Johannesburg', 'ZAR', null, now(), null, null),
  ('00000000-0000-0000-0000-00000000f00c', '00000000-0000-0000-0000-0000000000b1', 'Farm C', 'FC', 'Africa/Johannesburg', 'ZAR', null, now(), null, null);
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000e1', 'manager@farm.test', now()),
  ('00000000-0000-0000-0000-0000000000e2', 'jane@consult.test', now()),       -- AI-only freelancer, confirmed
  ('00000000-0000-0000-0000-0000000000e3', 'nobody@consult.test', null),      -- AI-only, email not confirmed
  ('00000000-0000-0000-0000-0000000000e4', 'acc@farm.test', now()),           -- office
  ('00000000-0000-0000-0000-0000000000e5', 'agro@farm.test', now()),          -- agronomist
  ('00000000-0000-0000-0000-0000000000e6', 'sipho@farm.test', now());         -- worker, never ticked
insert into public.membership (user_id, org_id, farm_id, role, display_name, active) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000f00a', 'farm_admin', 'Francesco', true),
  -- on Supabase the membership_sisters trigger adds this one (sister unit)
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000fa02', 'farm_admin', 'Francesco', true),
  ('00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000f00a', 'office', 'Office', true);

-- The team of farm A (workers are rows of the team page)
insert into public.worker (id, farm_id, user_id, name, role, email, hourly_cost) values
  ('00000000-0000-0000-0000-0000000060e1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000000e1', 'Francesco', 'farm_admin', 'manager@farm.test', 100),
  ('00000000-0000-0000-0000-0000000060e4', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000000e4', 'Lindi', 'office', 'acc@farm.test', 60),
  ('00000000-0000-0000-0000-0000000060e5', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000000e5', 'Agnes', 'agronomist', 'agro@farm.test', 80),
  ('00000000-0000-0000-0000-0000000060e6', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000000e6', 'Sipho', 'worker', 'sipho@farm.test', 35),
  ('00000000-0000-0000-0000-0000000060a1', '00000000-0000-0000-0000-00000000f00a', null, 'Thabo', 'worker', null, 40);
-- Jane: AI-only, no login set up, only an email; the team page sends her as a normal worker would
insert into public.worker (id, farm_id, user_id, name, role, email, off_tasks, working_days, hours_per_day, employment) values
  ('00000000-0000-0000-0000-0000000060e2', '00000000-0000-0000-0000-00000000f00a', null, 'Jane', 'ai_only', ' Jane@Consult.test ', false, '{1,2,3,4,5}', 8, 'permanent'),
  ('00000000-0000-0000-0000-0000000060e3', '00000000-0000-0000-0000-00000000f00a', null, 'Nobody', 'ai_only', 'nobody@consult.test', false, null, null, 'permanent');

-- Farm data
insert into public.zone (id, farm_id, code, name) values
  ('00000000-0000-0000-0000-0000000020a1', '00000000-0000-0000-0000-00000000f00a', 'Z1', 'Zone 1'),
  ('00000000-0000-0000-0000-0000000020a2', '00000000-0000-0000-0000-00000000fa02', 'Z1', 'Zone 1 A2'),
  ('00000000-0000-0000-0000-0000000020b1', '00000000-0000-0000-0000-00000000f00b', 'Z1', 'Zone 1 B');
insert into public.sticky_trap (id, farm_id, zone_id, code, metres) values
  ('00000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000020a1', 'A1', 4),
  ('00000000-0000-0000-0000-0000000030a2', '00000000-0000-0000-0000-00000000fa02', '00000000-0000-0000-0000-0000000020a2', 'A2-1', 4),
  ('00000000-0000-0000-0000-0000000030b1', '00000000-0000-0000-0000-00000000f00b', '00000000-0000-0000-0000-0000000020b1', 'B1', 4);
insert into public.trap_reading (id, farm_id, trap_id, read_at, total, day_rate, photo_data, created_by) values
  ('00000000-0000-0000-0000-0000000040a1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000030a1', now() - interval '7 days', 12, 1.7, 'data:image/jpeg;base64,QUFB', '00000000-0000-0000-0000-0000000000e1'),
  ('00000000-0000-0000-0000-0000000040a2', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000030a1', now(), 30, 2.6, null, null),
  ('00000000-0000-0000-0000-0000000040a3', '00000000-0000-0000-0000-00000000fa02', '00000000-0000-0000-0000-0000000030a2', now(), 5, 0.7, null, null),
  ('00000000-0000-0000-0000-0000000040b1', '00000000-0000-0000-0000-00000000f00b', '00000000-0000-0000-0000-0000000030b1', now(), 99, 14, 'data:image/jpeg;base64,QkJC', null);
insert into public.scout_observation (id, farm_id, zone_id, note, photo_data) values
  ('00000000-0000-0000-0000-0000000050a1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000020a1', 'whitefly on leaf', 'data:image/jpeg;base64,U0NPVVQ=');
insert into public.cost_entry (farm_id, day, category, amount) values
  ('00000000-0000-0000-0000-00000000f00a', current_date, 'nutrients', 1250.50),
  ('00000000-0000-0000-0000-00000000f00b', current_date, 'nutrients', 99);
insert into public.customer (id, farm_id, name, phone, email, address, channel) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000f00a', 'Green Grocer', '+27 82 000', 'gg@shop.test', '1 Main Rd', 'retail');
insert into public.task (id, farm_id, title, family, zone_id, status) values
  ('00000000-0000-0000-0000-0000000070a1', '00000000-0000-0000-0000-00000000f00a', 'Scouting Z1', 'Agriculture', '00000000-0000-0000-0000-0000000020a1', 'done');
insert into public.task_time (farm_id, task_id, worker_id, started_at, stopped_at) values
  ('00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000070a1', '00000000-0000-0000-0000-0000000060a1', now() - interval '90 minutes', now());
insert into public.task_worker (task_id, worker_id) values
  ('00000000-0000-0000-0000-0000000070a1', '00000000-0000-0000-0000-0000000060a1');
insert into public.crop (id, scope, org_id, farm_id, code, name) values
  (gen_random_uuid(), 'standard', null, null, 'LET', 'Lettuce (standard)'),
  (gen_random_uuid(), 'org', '00000000-0000-0000-0000-0000000000a1', null, 'BAS', 'Basil (org A)'),
  (gen_random_uuid(), 'org', '00000000-0000-0000-0000-0000000000b1', null, 'SEC', 'Secret crop (org B)'),
  (gen_random_uuid(), 'farm', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000f00a', 'MIC', 'Micro (farm A)'),
  (gen_random_uuid(), 'farm', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000f00b', 'OTH', 'Other farm crop');
insert into public.pest_catalog (code, label) values ('WF', 'Whitefly');
insert into auth.oauth_clients (id, client_name) values ('00000000-0000-0000-0000-0000000000c1', 'Claude');
insert into auth.sessions (user_id, oauth_client_id) values
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000e2', null);

create function pg_temp.as_user(p uuid, p_client text default null) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated', 'client_id', p_client)::text, false) $$;
create function pg_temp.fams(p uuid) returns text language sql as $$ select array_to_string(mcp.person_families(p), ',') $$;

-- ── The AI-only role ──
select pg_temp.ok((select off_tasks and working_days = '{}' and hours_per_day = 0 and employment = 'casual'
                     from public.worker where id = '00000000-0000-0000-0000-0000000060e2'),
                  'an AI-only person is forced off the tasks, with no hours, whatever was sent');
set role authenticated;
update public.worker set off_tasks = false, hours_per_day = 6 where id = '00000000-0000-0000-0000-0000000060e2';
reset role;
select pg_temp.ok((select off_tasks and hours_per_day = 0 from public.worker where id = '00000000-0000-0000-0000-0000000060e2'),
                  'and stays off when the team page (as a signed-in user) changes them');
update public.worker set role = 'worker' where id = '00000000-0000-0000-0000-0000000060e3';
update public.worker set role = 'ai_only' where id = '00000000-0000-0000-0000-0000000060e3';
select pg_temp.ok((select off_tasks from public.worker where id = '00000000-0000-0000-0000-0000000060e3'), 'becoming AI-only takes a person off the tasks');
do $$ begin
  insert into public.worker (farm_id, name, role) values ('00000000-0000-0000-0000-00000000f00a', 'X', 'boss');
  raise exception 'FAIL: unknown role accepted';
exception when check_violation then raise notice 'PASS an unknown role is still refused';
end $$;

-- ── Role defaults ──
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e5') = 'crops,harvest,tasks,water,climate,pests', 'agronomist: crops, harvest, tasks, water, climate, pests by default');
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e4') = 'harvest,purchasing,sales,costs', 'office: harvest, purchasing, sales, costs by default');
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e1') = 'crops,harvest,tasks,water,climate,pests,equipment,purchasing,sales,costs,team', 'farm admin: every family');
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e2') = '', 'AI-only: nothing until clicked');

-- ── The manager ticks and clicks ──
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select public.mcp_set_access('00000000-0000-0000-0000-0000000060e2', true, now() + interval '30 days');
select public.mcp_person_family('00000000-0000-0000-0000-0000000060e2', 'pests', true);
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e2') = 'pests', 'click: Jane gets pests');
select public.mcp_set_access('00000000-0000-0000-0000-0000000060e4', true);
select public.mcp_person_family('00000000-0000-0000-0000-0000000060e4', 'team', true);
select public.mcp_person_family('00000000-0000-0000-0000-0000000060e4', 'sales', false);
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e4') = 'harvest,purchasing,costs,team', 'click: office person gets team added and sales taken away');
select pg_temp.ok(exists (select 1 from mcp.person_data_off where worker_id = '00000000-0000-0000-0000-0000000060e4' and family = 'sales'), 'a role family taken away is remembered, so the role does not give it back');
select public.mcp_set_access('00000000-0000-0000-0000-0000000060e5', true);
select public.mcp_set_access('00000000-0000-0000-0000-0000000060e3', true);
select public.mcp_person_family('00000000-0000-0000-0000-0000000060e3', 'pests', true);

-- A role change flows to everybody of that job, and back
select public.mcp_set_role('00000000-0000-0000-0000-00000000f00a', 'agronomist', '{crops,pests}');
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e5') = 'crops,pests', 'the farm''s own agronomist list replaces the default for every agronomist');
select pg_temp.ok((select (public.mcp_team('00000000-0000-0000-0000-00000000fa02') -> 'roles') @> '[{"role":"agronomist","own":true,"families":["crops","pests"]}]'),
                  'the sister unit shows the same role list (kept on the home farm)');
select public.mcp_reset_role('00000000-0000-0000-0000-00000000f00a', 'agronomist');
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e5') = 'crops,harvest,tasks,water,climate,pests', 'reset: back to the standard list');
select public.mcp_set_role('00000000-0000-0000-0000-00000000f00a', 'office', '{}');
select pg_temp.ok(pg_temp.fams('00000000-0000-0000-0000-0000000060e4') = 'team', 'an empty role list is kept as empty; the person''s own additions stay');
select public.mcp_reset_role('00000000-0000-0000-0000-00000000f00a', 'office');

do $$ begin
  perform public.mcp_set_access('00000000-0000-0000-0000-0000000060e5', true, now() - interval '1 day');
  raise exception 'FAIL: past end date accepted';
exception when sqlstate '22023' then raise notice 'PASS a past end date is refused';
end $$;
do $$ begin
  perform public.mcp_person_family('00000000-0000-0000-0000-0000000060e5', 'shopping', true);
  raise exception 'FAIL: unknown family accepted';
exception when sqlstate '22023' then raise notice 'PASS a family outside the list is refused';
end $$;
do $$ begin
  perform public.mcp_set_access('00000000-0000-0000-0000-0000000060a1', true);
  raise exception 'FAIL: ticked a person with no email and no login';
exception when sqlstate '22023' then raise notice 'PASS a person without email or login cannot be ticked (their AI could not sign in)';
end $$;
select pg_temp.ok((public.mcp_team('00000000-0000-0000-0000-00000000f00a') ->> 'may_edit')::boolean, 'mcp_team: the manager may edit');
select pg_temp.ok((select p ->> 'in_force' from jsonb_array_elements(public.mcp_team('00000000-0000-0000-0000-00000000f00a') -> 'people') p
                    where p ->> 'name' = 'Jane') = 'true', 'mcp_team: Jane is in force');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e4');
do $$ begin
  perform public.mcp_set_access('00000000-0000-0000-0000-0000000060e6', true);
  raise exception 'FAIL: office person ticked someone';
exception when insufficient_privilege then raise notice 'PASS who does not manage people cannot tick anyone';
end $$;
select pg_temp.ok(not (public.mcp_team('00000000-0000-0000-0000-00000000f00a') ->> 'may_edit')::boolean, 'mcp_team: the office person may only look');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
do $$ begin
  perform public.mcp_team('00000000-0000-0000-0000-00000000f00a');
  raise exception 'FAIL: AI-only person opened the team';
exception when insufficient_privilege then raise notice 'PASS an AI-only person (no membership) cannot open the team page';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1');
do $$ begin
  perform public.mcp_person_family('00000000-0000-0000-0000-0000000060e2', 'costs', true);
  raise exception 'FAIL: an OAuth (AI) token clicked a family';
exception when insufficient_privilege then raise notice 'PASS an AI token cannot change access, even the manager''s';
end $$;
do $$ begin
  perform public.mcp_team('00000000-0000-0000-0000-00000000f00a');
  raise exception 'FAIL: an OAuth token read the team';
exception when insufficient_privilege then raise notice 'PASS an AI token cannot read the team AI list';
end $$;

-- ── Consent page view of it ──
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select string_agg(farm, ',' order by farm) from public.mcp_my_access()) = 'Farm A,Farm A2', 'mcp_my_access shows Jane her farm and its sister unit');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e3');
select pg_temp.ok((select count(*) from public.mcp_my_access()) = 0, 'an unconfirmed email matches nobody');

-- ── Requests ──
reset request.jwt.claims;
insert into test_ctx values
  ('jane', mcp.begin_request('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c1')::text),
  ('acc', mcp.begin_request('00000000-0000-0000-0000-0000000000e4', null)::text),
  ('random', gen_random_uuid()::text);
select pg_temp.ok((select v from test_ctx where k = 'jane') is not null, 'Jane gets a request through her email');
select pg_temp.ok((select farms -> 'pests' from mcp.request where id = (select v from test_ctx where k = 'jane')::uuid)
                    @> '["00000000-0000-0000-0000-00000000f00a", "00000000-0000-0000-0000-00000000fa02"]'
                  and (select jsonb_object_keys(farms) from mcp.request where id = (select v from test_ctx where k = 'jane')::uuid) = 'pests',
                  'Jane''s request: pests only, on farm A and its sister A2, not B');
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e3', null) is null, 'unconfirmed email gets no request');
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e1', null) is null, 'the manager, never ticked, gets no request (access is explicit)');
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e6', null) is null, 'a worker never ticked gets no request');
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e5', null) is not null, 'the ticked agronomist gets one through the role');

-- An expired request
insert into mcp.request (id, user_id, farms, orgs, info, expires_at)
values ('00000000-0000-0000-0000-00000000dead', '00000000-0000-0000-0000-0000000000e2',
        '{"pests": ["00000000-0000-0000-0000-00000000f00a"]}', '{}', '[]', now() - interval '1 second');
insert into test_ctx values ('expired', '00000000-0000-0000-0000-00000000dead');

-- Rate limit: 60 calls in the last minute
insert into mcp.call_log (user_id, tool, ok) select '00000000-0000-0000-0000-0000000000e5', 'query', true from generate_series(1, 60);
do $$ begin
  perform mcp.begin_request('00000000-0000-0000-0000-0000000000e5', null);
  raise exception 'FAIL: rate limit not applied';
exception when sqlstate 'P0001' then raise notice 'PASS more than 60 calls a minute are refused';
end $$;
delete from mcp.call_log;

-- ── The token hook ──
select pg_temp.ok(public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e1","claims":{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"},"authentication_method":"password"}')
  = '{"user_id":"00000000-0000-0000-0000-0000000000e1","claims":{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"},"authentication_method":"password"}', 'hook: a normal sign-in is untouched');
select pg_temp.ok(public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e2","claims":{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated","client_id":"00000000-0000-0000-0000-0000000000c1"},"authentication_method":"oauth_provider/authorization_code"}') #>> '{claims,role}' = 'mcp_reader', 'hook: an AI token of a ticked person gets role mcp_reader');
select pg_temp.ok((public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e6","claims":{"sub":"00000000-0000-0000-0000-0000000000e6","role":"authenticated","client_id":"c"},"authentication_method":"token_refresh"}') #>> '{error,http_code}') = '403', 'hook: an AI token of a person never ticked is refused');
select pg_temp.ok(public.mcp_token_hook('{"user_id":"not-a-uuid","claims":{"role":"authenticated"},"authentication_method":"password"}') ->> 'user_id' = 'not-a-uuid', 'hook: a malformed normal event is still let through');

-- ── Ending and stopping ──
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update mcp.person set ai_until = now() - interval '1 minute' where worker_id = '00000000-0000-0000-0000-0000000060e5';
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e5', null) is null, 'past the end date the agronomist gets nothing');
select pg_temp.ok((select p ->> 'in_force' from jsonb_array_elements(public.mcp_team('00000000-0000-0000-0000-00000000f00a') -> 'people') p
                    where p ->> 'name' = 'Agnes') = 'false', 'and the team page shows it not in force');
update public.worker set active = false where id = '00000000-0000-0000-0000-0000000060e4';
reset request.jwt.claims;
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e4', null) is null, 'a person who left the team (not active) gets nothing');
update public.worker set active = true where id = '00000000-0000-0000-0000-0000000060e4';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select public.mcp_set_access('00000000-0000-0000-0000-0000000060e2', false);
reset request.jwt.claims;
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e2', null) is null, 'untick: Jane gets no new request');
select pg_temp.ok((select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-0000000000e2' and oauth_client_id is not null) = 0, 'untick signs Jane''s AI out (found through her email)');
select pg_temp.ok((select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-0000000000e2' and oauth_client_id is null) = 1, 'and keeps any other sign-in of hers');
select pg_temp.ok(public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e2","claims":{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated","client_id":"c"},"authentication_method":"token_refresh"}') ? 'error', 'after untick the hook refuses Jane''s refresh');
-- (Jane's request opened before the untick lives out its 2 minutes; the reader tests use it.)

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok(public.mcp_stop_all('00000000-0000-0000-0000-00000000fa02') = 3, 'stop all (from the sister unit) unticks the three still ticked');
select pg_temp.ok(not exists (select 1 from mcp.person where ai_access), 'nobody is ticked any more');
-- tick the office person again for the reader tests
select public.mcp_set_access('00000000-0000-0000-0000-0000000060e4', true);
reset request.jwt.claims;
update test_ctx set v = mcp.begin_request('00000000-0000-0000-0000-0000000000e4', null)::text where k = 'acc';

-- ── Nothing private in any view ──
select pg_temp.ok(not exists (
  select 1 from information_schema.columns
   where table_schema = 'mcp' and table_name in (select view_name from mcp.view_area)
     and column_name in ('photo_data','photo_path','image_path','phone','email','address','contact_person','contact_name',
                         'linkedin_url','photo_url','key_last4','shop_key_last4','user_id','created_by','updated_by',
                         'author','author_name','config','client_id')),
  'no view has a contact, key, photo or account column');
select pg_temp.ok(not exists (
  select 1 from information_schema.columns c join mcp.view_area v on v.view_name = c.table_name
   where c.table_schema = 'mcp' and not ('team' = any(v.areas)) and c.column_name in ('worker_id','done_by','operator_id')),
  'outside the team family no view names a worker');
select pg_temp.ok(not exists (select 1 from mcp.view_area v where not v.areas <@ (select array_agg(code) from mcp.data_family)),
  'every view belongs to families of the fixed list');
select pg_temp.ok((select count(*) from mcp.view_area) = (select count(*) from information_schema.views where table_schema = 'mcp'), 'every view is listed in view_area');
select pg_temp.ok(not exists (select 1 from information_schema.role_table_grants where grantee in ('anon','authenticated','PUBLIC') and table_schema = 'mcp'), 'the API roles have no grant on the mcp schema');
select pg_temp.ok(not has_schema_privilege('authenticated', 'mcp', 'usage'), 'authenticated cannot even see schema mcp');
select pg_temp.ok(not has_table_privilege('mcp_reader', 'public.trap_reading', 'select'), 'mcp_reader has no right on the tables');
select pg_temp.ok(not has_function_privilege('mcp_reader', 'mcp.begin_request(uuid,text)', 'execute'), 'mcp_reader cannot open requests');
select pg_temp.ok(not pg_has_role('authenticator', 'mcp_reader', 'member'), 'authenticator cannot switch to mcp_reader (AI tokens are refused by the REST API)');
