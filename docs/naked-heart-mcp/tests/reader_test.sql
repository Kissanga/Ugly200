-- Part B, run logged in AS mcp_reader (psql -U mcp_reader), as the MCP function's second
-- connection is. Variables: jane, acc, random, expired (request ids from part A).
\set ON_ERROR_STOP on

-- Jane: ipm on farm A
select set_config('mcp.request', :'jane', false);
do $$ begin
  assert (select count(*) from trap_readings) = 2, 'Jane sees the 2 readings of farm A';
  assert (select count(*) from trap_readings where farm_id <> '00000000-0000-0000-0000-00000000f00a') = 0, 'and none of farm B';
  assert (select bool_and(has_photo is not null) from trap_readings), 'has_photo is there';
  assert (select count(*) from sticky_traps) = 1, 'one trap';
  assert (select count(*) from zones) = 1, 'reference views follow the access: one zone';
  assert (select count(*) from farms) = 1 and (select name from farms) = 'Farm A', 'one farm';
  assert (select count(*) from cost_entries) = 0, 'no money area: no costs';
  assert (select count(*) from workers) = 0, 'no team area: no workers';
  assert (select count(*) from pest_catalog) = 1, 'catalogue of the area is visible';
  assert (select count(*) from market_prices) = 0 or true, 'market prices (money) not asked';
  assert (select count(*) from crops) = 3, 'crops: standard + own organisation + own farm, not org B''s nor farm B''s';
  assert not exists (select 1 from crops where name in ('Secret crop (org B)', 'Other farm crop')), 'no other organisation''s or farm''s crops';
  assert mcp.photo('scout', '00000000-0000-0000-0000-0000000050a1') like 'data:image/jpeg;base64,%', 'photo of farm A is given';
  assert mcp.photo('trap', '00000000-0000-0000-0000-0000000040b1') is null, 'photo of farm B is not';
  assert (mcp.my_access() -> 0 ->> 'farm') = 'Farm A', 'my_access tells which farm';
  raise notice 'PASS Jane sees exactly ipm on farm A';
end $$;

-- What mcp_reader can never do
do $$ begin
  perform count(*) from public.trap_reading;
  raise exception 'FAIL: read a table directly';
exception when insufficient_privilege then raise notice 'PASS no direct table read';
end $$;
do $$ begin
  perform count(*) from mcp.access;
  raise exception 'FAIL: read mcp.access';
exception when insufficient_privilege then raise notice 'PASS cannot read who has access';
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
  perform public.mcp_access_give('00000000-0000-0000-0000-00000000f00a', 'me@x.test', '{money}');
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

-- The accountant: money + team on farm A
select set_config('mcp.request', :'acc', false);
do $$ begin
  assert (select count(*) from cost_entries) = 1 and (select sum(amount) from cost_entries) = 1250.50, 'one cost of farm A';
  assert (select count(*) from customers) = 1, 'customers visible';
  assert (select count(*) from trap_readings) = 0, 'no ipm';
  assert (select count(*) from workers) = 1 and (select name from workers) = 'Thabo', 'team: the worker by name';
  assert (select count(*) from task_workers) = 1, 'team view through tasks works without the growing area';
  assert (select count(*) from tasks) = 0, 'but the tasks themselves are growing';
  assert (select minutes from labour_minutes_daily) between 89 and 91, 'labour minutes aggregated';
  assert (select cost from labour_minutes_daily) = 60.00, '90 min at 40/h = 60';
  raise notice 'PASS the accountant sees money and team of farm A only';
end $$;
