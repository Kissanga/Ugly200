-- Part A, run as postgres after the stub and both migrations: seed two organisations, three farms,
-- a manager, two outside people; give, refuse, end and stop access; the hook; the request rows.
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
insert into public.farm (id, org_id, name, code, timezone, currency, shop_key_last4, attributes) values
  ('00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000000a1', 'Farm A', 'FA', 'Africa/Johannesburg', 'ZAR', '9999', '{"secret":"x"}'),
  ('00000000-0000-0000-0000-00000000f00b', '00000000-0000-0000-0000-0000000000a1', 'Farm B', 'FB', 'Africa/Johannesburg', 'ZAR', null, null),
  ('00000000-0000-0000-0000-00000000f00c', '00000000-0000-0000-0000-0000000000b1', 'Farm C', 'FC', 'Africa/Johannesburg', 'ZAR', null, null);
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000e1', 'manager@farm.test', now()),
  ('00000000-0000-0000-0000-0000000000e2', 'jane@consult.test', now()),       -- outside, confirmed
  ('00000000-0000-0000-0000-0000000000e3', 'nobody@consult.test', null),      -- outside, not confirmed
  ('00000000-0000-0000-0000-0000000000e4', 'acc@books.test', now());          -- outside accountant
insert into public.membership (user_id, org_id, farm_id, role, display_name, active) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000f00a', 'farm_admin', 'Francesco', true);

-- Farm data
insert into public.zone (id, farm_id, code, name) values
  ('00000000-0000-0000-0000-0000000020a1', '00000000-0000-0000-0000-00000000f00a', 'Z1', 'Zone 1'),
  ('00000000-0000-0000-0000-0000000020b1', '00000000-0000-0000-0000-00000000f00b', 'Z1', 'Zone 1 B');
insert into public.sticky_trap (id, farm_id, zone_id, code, metres) values
  ('00000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000020a1', 'A1', 4),
  ('00000000-0000-0000-0000-0000000030b1', '00000000-0000-0000-0000-00000000f00b', '00000000-0000-0000-0000-0000000020b1', 'B1', 4);
insert into public.trap_reading (id, farm_id, trap_id, read_at, total, day_rate, photo_data, created_by) values
  ('00000000-0000-0000-0000-0000000040a1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000030a1', now() - interval '7 days', 12, 1.7, 'data:image/jpeg;base64,QUFB', '00000000-0000-0000-0000-0000000000e1'),
  ('00000000-0000-0000-0000-0000000040a2', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000030a1', now(), 30, 2.6, null, null),
  ('00000000-0000-0000-0000-0000000040b1', '00000000-0000-0000-0000-00000000f00b', '00000000-0000-0000-0000-0000000030b1', now(), 99, 14, 'data:image/jpeg;base64,QkJC', null);
insert into public.scout_observation (id, farm_id, zone_id, note, photo_data) values
  ('00000000-0000-0000-0000-0000000050a1', '00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-0000000020a1', 'whitefly on leaf', 'data:image/jpeg;base64,U0NPVVQ=');
insert into public.cost_entry (farm_id, day, category, amount) values
  ('00000000-0000-0000-0000-00000000f00a', current_date, 'nutrients', 1250.50),
  ('00000000-0000-0000-0000-00000000f00b', current_date, 'nutrients', 99);
insert into public.customer (id, farm_id, name, phone, email, address, channel) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000f00a', 'Green Grocer', '+27 82 000', 'gg@shop.test', '1 Main Rd', 'retail');
insert into public.worker (id, farm_id, name, phone, email, hourly_cost, user_id) values
  ('00000000-0000-0000-0000-0000000060a1', '00000000-0000-0000-0000-00000000f00a', 'Thabo', '+27 83 111', 'thabo@farm.test', 40, null);
insert into public.task (id, farm_id, title, family, zone_id, status) values
  ('00000000-0000-0000-0000-0000000070a1', '00000000-0000-0000-0000-00000000f00a', 'Scouting Z1', 'IPM', '00000000-0000-0000-0000-0000000020a1', 'done');
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

-- ── Giving access ──
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select set_config('test.jane', public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', ' Jane@Consult.test ', '{ipm}', now() + interval '30 days', 'Jane — IPM')::text, false);
select pg_temp.ok((select email from mcp.access where id = current_setting('test.jane')::uuid) = 'jane@consult.test', 'email kept lower-case and trimmed');
select pg_temp.ok((select user_id from mcp.access where id = current_setting('test.jane')::uuid) = '00000000-0000-0000-0000-0000000000e2', 'access bound to the existing confirmed account');
select set_config('test.acc', public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'acc@books.test', '{money,team}')::text, false);
select set_config('test.nobody', public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'nobody@consult.test', '{ipm}')::text, false);
select set_config('test.later', public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'later@new.test', '{growing}')::text, false);
select pg_temp.ok((select user_id is null from mcp.access where id = current_setting('test.later')::uuid), 'access can be given before the person has an account');

do $$ begin
  perform public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'x@y.test', '{ipm}', now() - interval '1 day');
  raise exception 'FAIL: past end date accepted';
exception when sqlstate '22023' then raise notice 'PASS a past end date is refused';
end $$;
do $$ begin
  perform public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'x@y.test', '{ipm,shopping}');
  raise exception 'FAIL: unknown area accepted';
exception when check_violation then raise notice 'PASS an unknown area is refused';
end $$;
do $$ begin
  perform public.mcp_access_give('00000000-0000-0000-0000-00000000f00b', 'x@y.test', '{ipm}');
  raise exception 'FAIL: manager of A gave access to B';
exception when insufficient_privilege then raise notice 'PASS a manager cannot give access to a farm they do not manage';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
do $$ begin
  perform public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'friend@x.test', '{money}');
  raise exception 'FAIL: outside person gave access';
exception when insufficient_privilege then raise notice 'PASS an outside person cannot give access';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1');
do $$ begin
  perform public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'friend@x.test', '{money}');
  raise exception 'FAIL: an OAuth (AI) token gave access';
exception when insufficient_privilege then raise notice 'PASS an AI token cannot give access, even the manager''s';
end $$;
do $$ begin
  perform public.mcp_access_list('00000000-0000-0000-0000-00000000f00a');
  raise exception 'FAIL: an OAuth token listed access';
exception when insufficient_privilege then raise notice 'PASS an AI token cannot list access';
end $$;

-- ── Consent page view of it ──
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select pg_temp.ok((select count(*) from public.mcp_my_access()) = 1 and (select farm from public.mcp_my_access()) = 'Farm A', 'mcp_my_access shows Jane her one farm');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e3');
select pg_temp.ok((select count(*) from public.mcp_my_access()) = 0, 'an unconfirmed email matches no access');

-- ── Requests ──
reset request.jwt.claims;
insert into test_ctx values
  ('jane', mcp.begin_request('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c1')::text),
  ('acc', mcp.begin_request('00000000-0000-0000-0000-0000000000e4', null)::text),
  ('random', gen_random_uuid()::text);
select pg_temp.ok((select v from test_ctx where k = 'jane') is not null, 'Jane gets a request');
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e3', null) is null, 'unconfirmed email gets no request');
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e1', null) is null, 'a manager without an access row gets no request (access is explicit)');
select pg_temp.ok((select farms from mcp.request where id = (select v from test_ctx where k = 'jane')::uuid) = '{"ipm": ["00000000-0000-0000-0000-00000000f00a"]}', 'Jane''s request covers ipm on farm A only');

-- An expired request
insert into mcp.request (id, user_id, farms, orgs, info, expires_at)
values ('00000000-0000-0000-0000-00000000dead', '00000000-0000-0000-0000-0000000000e2',
        '{"ipm": ["00000000-0000-0000-0000-00000000f00a"]}', '{}', '[]', now() - interval '1 second');
insert into test_ctx values ('expired', '00000000-0000-0000-0000-00000000dead');

-- Rate limit: 60 calls in the last minute
insert into mcp.call_log (user_id, tool, ok) select '00000000-0000-0000-0000-0000000000e4', 'query', true from generate_series(1, 60);
do $$ begin
  perform mcp.begin_request('00000000-0000-0000-0000-0000000000e4', null);
  raise exception 'FAIL: rate limit not applied';
exception when sqlstate 'P0001' then raise notice 'PASS more than 60 calls a minute are refused';
end $$;
delete from mcp.call_log;

-- ── The token hook ──
select pg_temp.ok(public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e1","claims":{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"},"authentication_method":"password"}')
  = '{"user_id":"00000000-0000-0000-0000-0000000000e1","claims":{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"},"authentication_method":"password"}', 'hook: a normal sign-in is untouched');
select pg_temp.ok(public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e2","claims":{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated","client_id":"00000000-0000-0000-0000-0000000000c1"},"authentication_method":"oauth_provider/authorization_code"}') #>> '{claims,role}' = 'mcp_reader', 'hook: an AI token of a person with access gets role mcp_reader');
select pg_temp.ok((public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e3","claims":{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated","client_id":"c"},"authentication_method":"token_refresh"}') #>> '{error,http_code}') = '403', 'hook: an AI token of a person without access is refused');
select pg_temp.ok(public.mcp_token_hook('{"user_id":"not-a-uuid","claims":{"role":"authenticated"},"authentication_method":"password"}') ->> 'user_id' = 'not-a-uuid', 'hook: a malformed normal event is still let through');

-- ── Ending and stopping ──
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
update mcp.access set ends_at = now() - interval '1 minute', starts_at = now() - interval '2 minutes' where id = current_setting('test.nobody')::uuid;
select pg_temp.ok((select state from public.mcp_access_list('00000000-0000-0000-0000-00000000f00a') where id = current_setting('test.nobody')::uuid) = 'ended', 'an access past its end date reads as ended');
select public.mcp_access_stop(current_setting('test.jane')::uuid);
select pg_temp.ok((select state from public.mcp_access_list('00000000-0000-0000-0000-00000000f00a') where id = current_setting('test.jane')::uuid) = 'stopped', 'a stopped access reads as stopped');
reset request.jwt.claims;
select pg_temp.ok(mcp.begin_request('00000000-0000-0000-0000-0000000000e2', null) is null, 'after stop Jane gets no new request');
select pg_temp.ok((select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-0000000000e2' and oauth_client_id is not null) = 0, 'stop signs Jane''s AI sessions out');
select pg_temp.ok((select count(*) from auth.sessions where user_id = '00000000-0000-0000-0000-0000000000e2' and oauth_client_id is null) = 1, 'stop keeps Jane''s own Naked Heart sign-in');
select pg_temp.ok(public.mcp_token_hook('{"user_id":"00000000-0000-0000-0000-0000000000e2","claims":{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated","client_id":"c"},"authentication_method":"token_refresh"}') ? 'error', 'after stop the hook refuses Jane''s refresh');
-- (Jane's request opened before the stop lives out its 2 minutes; the reader tests use it.)

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.ok(public.mcp_access_stop_all('00000000-0000-0000-0000-00000000f00a') = 2, 'stop all ends the two accesses still in force (accountant, later)');
reset request.jwt.claims;
-- give the accountant a fresh one for the reader tests (as the manager)
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'acc@books.test', '{money,team}');
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
  'outside the team area no view names a worker');
select pg_temp.ok((select count(*) from mcp.view_area) = (select count(*) from information_schema.views where table_schema = 'mcp'), 'every view is listed in view_area');
select pg_temp.ok(not exists (select 1 from information_schema.role_table_grants where grantee in ('anon','authenticated','PUBLIC') and table_schema = 'mcp'), 'the API roles have no grant on the mcp schema');
select pg_temp.ok(not has_schema_privilege('authenticated', 'mcp', 'usage'), 'authenticated cannot even see schema mcp');
select pg_temp.ok(not has_table_privilege('mcp_reader', 'public.trap_reading', 'select'), 'mcp_reader has no right on the tables');
select pg_temp.ok(not has_function_privilege('mcp_reader', 'mcp.begin_request(uuid,text)', 'execute'), 'mcp_reader cannot open requests');
select pg_temp.ok(not pg_has_role('authenticator', 'mcp_reader', 'member'), 'authenticator cannot switch to mcp_reader (AI tokens are refused by the REST API)');
