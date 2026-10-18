-- Part B, run logged in AS mcp_reader (psql -U mcp_reader), as the MCP function's second
-- connection is. Variables: jane, acc, random, expired (request ids from part A).
\set ON_ERROR_STOP on

-- Jane (AI-only): pests on farm A and its sister unit A2
select set_config('mcp.request', :'jane', false);
do $$ begin
  assert (select count(*) from trap_readings) = 3, 'Jane sees the readings of farm A and A2';
  assert (select count(*) from trap_readings where farm_id = '00000000-0000-0000-0000-00000000f00b') = 0, 'and none of farm B';
  assert (select bool_and(has_photo is not null) from trap_readings), 'has_photo is there';
  assert (select count(*) from sticky_traps) = 2, 'two traps';
  assert (select count(*) from zones) = 2, 'reference views follow the access: two zones';
  assert (select string_agg(name, ',' order by name) from farms) = 'Farm A,Farm A2', 'two farms';
  assert (select count(*) from cost_entries) = 0, 'no costs family: no costs';
  assert (select count(*) from workers) = 0, 'no team family: no workers';
  assert (select count(*) from tasks) = 0, 'no tasks family: no tasks';
  assert (select count(*) from pest_catalog) = 1, 'the pests catalogue is visible';
  assert (select count(*) from crops) = 3, 'crops: standard + own organisation + own farm, not org B''s nor farm B''s';
  assert not exists (select 1 from crops where name in ('Secret crop (org B)', 'Other farm crop')), 'no other organisation''s or farm''s crops';
  assert mcp.photo('scout', '00000000-0000-0000-0000-0000000050a1') like 'data:image/jpeg;base64,%', 'photo of farm A is given';
  assert mcp.photo('trap', '00000000-0000-0000-0000-0000000040b1') is null, 'photo of farm B is not';
  assert (select count(*) from jsonb_array_elements(mcp.my_access())) = 2, 'my_access tells both farms';
  raise notice 'PASS Jane sees exactly pests on farm A and its sister A2';
end $$;

-- What mcp_reader can never do
do $$ begin
  perform count(*) from public.trap_reading;
  raise exception 'FAIL: read a table directly';
exception when insufficient_privilege then raise notice 'PASS no direct table read';
end $$;
do $$ begin
  perform count(*) from mcp.person;
  raise exception 'FAIL: read mcp.person';
exception when insufficient_privilege then raise notice 'PASS cannot read who is ticked';
end $$;
do $$ begin
  perform count(*) from mcp.person_data;
  raise exception 'FAIL: read mcp.person_data';
exception when insufficient_privilege then raise notice 'PASS cannot read anyone''s families';
end $$;
do $$ begin
  perform mcp.person_families('00000000-0000-0000-0000-0000000060e1');
  raise exception 'FAIL: ran person_families';
exception when insufficient_privilege then raise notice 'PASS cannot work out anyone''s families';
end $$;
do $$ begin
  perform count(*) from mcp.request;
  raise exception 'FAIL: read mcp.request (other request ids)';
exception when insufficient_privilege then raise notice 'PASS cannot read other requests';
end $$;
do $$ begin
  perform mcp.begin_request('00000000-0000-0000-0000-0000000000e4', null);
  raise exception 'FAIL: opened a request';
exception when insufficient_privilege then raise notice 'PASS cannot open a request for anyone';
end $$;
do $$ begin
  perform set_config('role', 'postgres', true);
  raise exception 'FAIL: switched to postgres';
exception when insufficient_privilege or invalid_parameter_value then raise notice 'PASS cannot switch role from a query';
end $$;
do $$ begin
  perform set_config('role', 'authenticated', true);
  raise exception 'FAIL: switched to authenticated';
exception when insufficient_privilege or invalid_parameter_value then raise notice 'PASS cannot become authenticated either';
end $$;
do $$ begin
  set transaction read write;
  raise exception 'FAIL: left read-only';
exception when others then raise notice 'PASS cannot leave read-only (%)', sqlerrm;
end $$;
do $$ begin
  perform public.mcp_set_access('00000000-0000-0000-0000-0000000060e2', true);
  raise exception 'FAIL: gave access';
exception when insufficient_privilege then raise notice 'PASS cannot call the managers'' functions';
end $$;
do $$ begin
  perform app.is_farm_manager('00000000-0000-0000-0000-00000000f00a');
  raise exception 'FAIL: reached app schema';
exception when insufficient_privilege then raise notice 'PASS cannot reach the app schema';
end $$;

-- Changing the request id by hand gets nothing
select set_config('mcp.request', :'random', false);
do $$ begin
  assert (select count(*) from trap_readings) = 0 and (select count(*) from farms) = 0, 'a guessed id sees nothing';
  raise notice 'PASS a made-up request id sees nothing';
end $$;
select set_config('mcp.request', :'expired', false);
do $$ begin
  assert (select count(*) from trap_readings) = 0, 'an expired request sees nothing';
  raise notice 'PASS an expired request sees nothing';
end $$;
select set_config('mcp.request', 'not-a-uuid', false);
do $$ begin
  assert (select count(*) from farms) = 0, 'garbage id sees nothing and does not crash';
  raise notice 'PASS a garbage request id sees nothing and does not error';
end $$;
reset mcp.request;
do $$ begin
  assert (select count(*) from farms) = 0, 'no id sees nothing';
  raise notice 'PASS no request id sees nothing';
end $$;

-- The office person: harvest, purchasing, costs and team (added); sales taken away
select set_config('mcp.request', :'acc', false);
do $$ begin
  assert (select count(*) from cost_entries) = 1 and (select sum(amount) from cost_entries) = 1250.50, 'one cost, of farm A';
  assert (select count(*) from customers) = 0, 'sales was taken away: no customers';
  assert (select count(*) from trap_readings) = 0, 'no pests';
  assert exists (select 1 from workers where name = 'Thabo'), 'team (added): the workers by name';
  assert not exists (select 1 from workers where role = 'ai_only'), 'AI-only people are not in the team data';
  assert (select count(*) from task_workers) = 1, 'team view through tasks works without the tasks family';
  assert (select count(*) from tasks) = 0, 'but the tasks themselves are not given';
  assert (select minutes from labour_minutes_daily) between 89 and 91, 'labour minutes aggregated';
  assert (select cost from labour_minutes_daily) = 60.00, '90 min at 40/h = 60';
  raise notice 'PASS the office person sees exactly their clicked families';
end $$;
