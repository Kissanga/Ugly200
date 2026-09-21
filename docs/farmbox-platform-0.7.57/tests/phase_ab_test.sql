-- ─────────────────────────────────────────────────────────────────────────────
-- 0.7.57 tests — run by tests/run_local.sh on a fresh local database:
--   stub → legacy rows → Phase A → Phase B → crop library → this file.
-- Every block raises on failure and prints PASS otherwise. On the platform,
-- fold these into tests/rls_test.sql style (PASS lines) once the schema names
-- are confirmed.
-- ─────────────────────────────────────────────────────────────────────────────
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- ── 1. category rename ───────────────────────────────────────────────────────
do $$ begin
  if exists (select 1 from crop where category in ('vines','fruiting')) then raise exception 'old categories remain'; end if;
  if (select category from crop where name = 'Tomato cherry indeterminate') <> 'fruiting_vines' then raise exception 'legacy Cherry tomato not renamed/recategorised'; end if;
  begin
    insert into crop (name, category) values ('bad', 'vines'); raise exception 'constraint should reject vines';
  exception when check_violation then null; end;
  if (select count(*) from crop_category) <> 6 then raise exception 'crop_category rows'; end if;
  raise notice 'PASS 1 categories renamed, constraint rebuilt, catalogue present';
end $$;

-- ── 2. library matching and archive ──────────────────────────────────────────
do $$ begin
  if (select count(*) from crop where lower(name) like '%cherry%') <> 1 then raise exception 'Cherry tomato duplicated instead of matched by alias'; end if;
  if (select count(*) from crop where archived_at is null) <> 50 then raise exception 'expected 50 active crops, got %', (select count(*) from crop where archived_at is null); end if;
  if (select archived_at from crop where name = 'Old lettuce') is null then raise exception 'Old lettuce should be archived'; end if;
  if exists (select 1 from crop where name = 'Old lettuce' and archived_reason is null) then raise exception 'archive reason missing'; end if;
  perform restore_crop((select id from crop where name = 'Old lettuce'));
  if (select archived_at from crop where name = 'Old lettuce') is not null then raise exception 'restore_crop failed'; end if;
  perform archive_crop((select id from crop where name = 'Old lettuce'), 'test');
  if (select archived_reason from crop where name = 'Old lettuce') <> 'test' then raise exception 'archive_crop failed'; end if;
  raise notice 'PASS 2 crops matched by alias, legacy crop archived not deleted, archive/restore work';
end $$;

-- ── 3. procedures: existing kept, new created with steps ─────────────────────
do $$ declare v_sop uuid; begin
  select id into v_sop from sop where title = 'Scout for pests and disease';
  if (select count(*) from sop where lower(title) = 'scout for pests and disease') <> 1 then raise exception 'existing procedure duplicated'; end if;
  if (select base_minutes from sop where id = v_sop) <> 4 or (select minutes_per_unit from sop where id = v_sop) <> 5 then raise exception 'existing timing overwritten'; end if;
  if (select count(*) from sop_step st join sop_version v on v.id = st.version_id where v.sop_id = v_sop) <> 1 then raise exception 'existing steps overwritten'; end if;
  if (select count(*) from sop where trigger_kind = 'crop_plan' and managed_in = 'console' and status = 'approved') < 30 then raise exception 'new procedures not approved/console'; end if;
  if exists (select 1 from sop s where s.trigger_kind = 'crop_plan' and not exists (select 1 from sop_version v join sop_step st on st.version_id = v.id where v.sop_id = s.id)) then raise exception 'a crop_plan procedure has no steps'; end if;
  if exists (select 1 from sop_step where step_type = 'measure' and (min_value is null or max_value is null)) then raise exception 'measure step without range'; end if;
  raise notice 'PASS 3 procedures: existing one kept (timing + steps), % new ones approved with steps', (select count(*) from sop) - 1;
end $$;

-- ── 4. every phase of every active crop has a procedure ──────────────────────
do $$ begin
  if exists (select 1 from crop c join crop_cycle cy on cy.crop_id = c.id join crop_phase ph on ph.cycle_id = cy.id
             where c.archived_at is null and not exists (select 1 from crop_phase_sop where phase_id = ph.id)) then raise exception 'phase without procedure'; end if;
  if exists (select 1 from crop c where c.archived_at is null and not exists (select 1 from crop_cycle where crop_id = c.id)) then raise exception 'crop without cycle'; end if;
  if (select count(*) from crop_library where archived_at is null) <> 50 then raise exception 'crop_library view'; end if;
  if (select jsonb_array_length(phases) from crop_library where name = 'Basil') < 6 then raise exception 'Basil phases'; end if;
  if (select cycle_days from crop_library where name = 'Radish microgreens') <> 11 then raise exception 'Radish microgreens cycle days = %', (select cycle_days from crop_library where name = 'Radish microgreens'); end if;
  raise notice 'PASS 4 50 crops with cycles, every phase carries a procedure, crop_library view reads titles per phase';
end $$;

-- ── 5. units ─────────────────────────────────────────────────────────────────
do $$ begin
  if unit_quantity('tray', 144, null, 72) <> 2 then raise exception 'tray'; end if;
  if unit_quantity('position', 144, 10, 72) <> 1 then raise exception 'position'; end if;
  if unit_quantity('plant', 144, 10, 72) <> 144 then raise exception 'plant'; end if;
  if unit_quantity('m2', 144, 12.5, 72) <> 12.5 then raise exception 'm2'; end if;
  if plan_position_plants(2, 'tray', 72) <> 144 then raise exception 'plants from trays'; end if;
  if sop_minutes(5, 0.25, 144) <> 41 then raise exception 'sop_minutes'; end if;
  raise notice 'PASS 5 unit conversions and minutes formula';
end $$;

-- ── 6. plan a crop → one task per crop × zone × date, positions underneath ──
do $$
declare v_farm uuid; v_zone uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; v_crop uuid; v_plan uuid; v_task task%rowtype; n int; v_sop uuid;
begin
  select id into v_farm from farm limit 1;
  select id into v_zone from zone where farm_id = v_farm limit 1;
  select id into v_p1 from position where zone_id = v_zone and code = 'Z1-R1';
  select id into v_p2 from position where zone_id = v_zone and code = 'Z1-R2';
  select id into v_p3 from position where zone_id = v_zone and code = 'Z1-R3';
  select id into v_crop from crop where name = 'Tomato cherry indeterminate';
  v_plan := plan_crop(v_farm, v_crop, v_zone, date '2026-10-01',
            jsonb_build_array(jsonb_build_object('position_id', v_p1, 'quantity', 1, 'unit', 'tray'),
                              jsonb_build_object('position_id', v_p2, 'quantity', 40, 'unit', 'plant'),
                              jsonb_build_object('position_id', v_p3, 'quantity', 20, 'unit', 'plant')));
  select count(*) into n from task where plan_id = v_plan;
  if n < 100 then raise exception 'too few tasks generated: %', n; end if;
  -- no two tasks for the same procedure on the same day: grouped, not per position
  if exists (select 1 from task where plan_id = v_plan group by sop_id, planned_date having count(*) > 1) then raise exception 'tasks not grouped'; end if;
  -- the transplant task: plant unit, 100 plants, 5 + 0.25 × 100 = 30 min
  select t.* into v_task from task t join sop s on s.id = t.sop_id where t.plan_id = v_plan and s.title = 'Transplant seedlings to growing position';
  if v_task.quantity <> 100 or v_task.unit <> 'plant' then raise exception 'transplant quantity % %', v_task.quantity, v_task.unit; end if;
  if v_task.estimated_minutes <> 40 then raise exception 'transplant minutes % (expected 3×5 base + 0.25×100)', v_task.estimated_minutes; end if;
  if (select count(*) from task_position where task_id = v_task.id) <> 3 then raise exception 'positions on transplant'; end if;
  if (select minutes from task_position where task_id = v_task.id and position_id = v_p1) <> 15 then raise exception 'per-position minutes'; end if;
  if v_task.planned_date <> date '2026-10-30' then raise exception 'transplant date % (1 sow + 7 germ + 21 nursery + 1)', v_task.planned_date; end if;
  if v_task.area <> 'Zone 1' or v_task.crop_id <> v_crop or v_task.zone_id <> v_zone or v_task.phase_id is null then raise exception 'task links'; end if;
  if v_task.sop_version_id is null then raise exception 'sop_version not resolved'; end if;
  -- tray-unit task: sowing 1 tray-equivalent per position → 40 plants / 40 plugs = 1 tray each
  select t.* into v_task from task t join sop s on s.id = t.sop_id where t.plan_id = v_plan and s.title = 'Sow seeds in plug trays';
  if v_task.quantity <> 2.5 then raise exception 'sowing trays % (expected 1 + 1 + 0.5)', v_task.quantity; end if;
  if v_task.planned_date <> date '2026-10-01' then raise exception 'sowing date'; end if;
  -- repeats: harvest fruit every 3 days for 150 days = 50 tasks
  select count(*) into n from task t join sop s on s.id = t.sop_id where t.plan_id = v_plan and s.title = 'Harvest fruit';
  if n <> 50 then raise exception 'harvest repeats %', n; end if;
  -- replan keeps done tasks, regenerates the rest
  update task set status = 'done' where id = v_task.id;
  n := replan_crop(v_plan);
  if (select status from task where id = v_task.id) <> 'done' then raise exception 'replan removed a done task'; end if;
  if (select count(*) from task where plan_id = v_plan group by sop_id, planned_date having count(*) > 1 limit 1) is not null then raise exception 'replan duplicated'; end if;
  -- editing a procedure's timing replans its open tasks
  select id into v_sop from sop where title = 'Harvest fruit';
  update sop set minutes_per_unit = 1 where id = v_sop;
  if (select estimated_minutes from task where plan_id = v_plan and sop_id = v_sop and status <> 'done' limit 1) <> 115 then
    raise exception 'timing trigger: expected 3×5 + 1×100 = 115, got %', (select estimated_minutes from task where plan_id = v_plan and sop_id = v_sop and status <> 'done' limit 1); end if;
  raise notice 'PASS 6 plan_crop: % tasks, grouped per date, per-position minutes summed, repeats, replan, timing trigger', (select count(*) from task where plan_id = v_plan);
end $$;

-- ── 7. sync_since: wrapper keeps the old keys and adds positions + names ────
do $$ declare v_farm uuid; j jsonb; t jsonb; begin
  select id into v_farm from farm limit 1;
  j := sync_since(v_farm, '-infinity'::timestamptz);
  if not (j ? 'tasks' and j ? 'sops' and j ? 'sop_versions' and j ? 'sop_steps' and j ? 'deleted' and j ? 'cursor') then raise exception 'old keys missing'; end if;
  if not j ? 'task_positions' then raise exception 'task_positions missing'; end if;
  if jsonb_array_length(j->'task_positions') < 3 then raise exception 'task_positions empty'; end if;
  select e into t from jsonb_array_elements(j->'tasks') e where e->>'title' like 'Transplant seedlings%' limit 1;
  if t->>'crop_name' <> 'Tomato cherry indeterminate' or t->>'zone_name' <> 'Zone 1' or t->>'phase_name' <> 'Transplant' then raise exception 'task enrichment: %', t; end if;
  if (t->>'quantity')::numeric <> 100 or t->>'unit' <> 'plant' or t->>'group_key' is null then raise exception 'task quantity/unit/group_key'; end if;
  if not exists (select 1 from jsonb_array_elements(j->'task_positions') e where e->>'task_id' = t->>'id' and e->>'position_code' = 'Z1-R1' and (e->>'minutes')::numeric = 15) then raise exception 'position row'; end if;
  -- a legacy task without crop keeps its row untouched
  if (select count(*) from jsonb_array_elements(j->'tasks') e where e->>'title' = 'Legacy task') <> 1 then raise exception 'legacy task lost'; end if;
  raise notice 'PASS 7 sync_since wraps v1: same keys, tasks enriched, task_positions delivered';
end $$;

-- ── 8. idempotency: library twice, migrations twice ──────────────────────────
\i data/crop_library_0757.sql
do $$ begin
  if (select count(*) from crop where archived_at is null) <> 50 then raise exception 'second library run changed active crops'; end if;
  if (select count(*) from sop) <> 31 then raise exception 'second library run duplicated procedures: %', (select count(*) from sop); end if;
  if (select count(*) from crop where lower(name) like '%cherry%') <> 1 then raise exception 'second run duplicated crops'; end if;
  -- the planned tomato still points at phases that carry their procedures
  if exists (select 1 from task t where t.phase_id is not null and not exists (select 1 from crop_phase where id = t.phase_id)) then raise exception 'planned tasks lost their phase'; end if;
  if exists (select 1 from crop c join crop_cycle cy on cy.crop_id = c.id join crop_phase ph on ph.cycle_id = cy.id
             where c.archived_at is null and not exists (select 1 from crop_phase_sop where phase_id = ph.id)) then raise exception 'phase lost its procedures on re-run'; end if;
  if (select count(*) from crop_phase ph join crop_cycle cy on cy.id = ph.cycle_id join crop c on c.id = cy.crop_id where c.name = 'Tomato cherry indeterminate') <> 8 then raise exception 'tomato phases duplicated on re-run'; end if;
  raise notice 'PASS 8 library is idempotent, re-run keeps planned phases linked';
end $$;
\i migrations/20260921120000_phase_a_grouped_tasks.sql
\i migrations/20260921120100_phase_b_categories_archive.sql
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'sync_since_v1') or (select count(*) from pg_proc where proname like 'sync_since%') <> 2 then raise exception 'rerun broke sync_since'; end if;
  raise notice 'PASS 9 migrations re-apply cleanly';
end $$;
