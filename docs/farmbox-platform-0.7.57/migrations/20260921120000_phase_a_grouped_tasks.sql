-- ─────────────────────────────────────────────────────────────────────────────
-- 0.7.57 · Phase A — grouped tasks, units, phase-linked procedures
--
-- Decisions (owner, 21 Sept 2026):
--   (1) minutes are computed per position (base + per_unit × that position's
--       quantity) but the farm sees ONE task per crop × zone × date; the
--       positions hang off task_position with their own quantity and minutes.
--       crop.plugs_per_tray converts trays ↔ plants. Units:
--         tray     → plants / plugs_per_tray
--         position → 1 per position
--         plant    → plants
--         m2       → area of the position (or its share of the zone)
--   (2) procedures attach to crop PHASES (crop_phase_sop, with a day offset).
--
-- Apply on the owner's machine:
--   supabase db query --linked -f migrations/20260921120000_phase_a_grouped_tasks.sql
--   supabase migration repair --status applied 20260921120000
--
-- ASSUMED names (fix here if the live schema differs — see stub/00_schema_stub.sql):
--   zone(id, farm_id, name, area_m2) · position(id, zone_id, code, capacity, area_m2)
--   crop_cycle(id, crop_id, is_default) · crop_phase(id, cycle_id, seq, name, days)
--   sop(base_minutes, minutes_per_unit, unit, status) · sop_version(sop_id, version, approved_at)
--   task(farm_id, title, family, sop_id, sop_version_id, planned_date, area, estimated_minutes, status)
-- ─────────────────────────────────────────────────────────────────────────────
begin;

-- ── 1. columns ────────────────────────────────────────────────────────────────
alter table crop add column if not exists plugs_per_tray int not null default 72
  check (plugs_per_tray > 0);

alter table task add column if not exists crop_id   uuid references crop(id);
alter table task add column if not exists zone_id   uuid references zone(id);
alter table task add column if not exists phase_id  uuid references crop_phase(id);
alter table task add column if not exists plan_id   uuid;
alter table task add column if not exists quantity  numeric;
alter table task add column if not exists unit      text;
alter table task add column if not exists group_key text;
create index if not exists task_plan_idx on task(plan_id) where plan_id is not null;

alter table sop add column if not exists base_minutes     numeric not null default 0;
alter table sop add column if not exists minutes_per_unit numeric not null default 0;
alter table sop add column if not exists unit             text    not null default 'position';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sop_unit_check') then
    alter table sop add constraint sop_unit_check check (unit in ('tray','position','plant','m2'));
  end if;
end $$;

-- ── 2. crop plan (what was planted where) ─────────────────────────────────────
-- ASSUMED new. If the console already stores plans under another name, point
-- plan_crop_tasks() at that table instead of creating this one.
create table if not exists crop_plan (
  id         uuid primary key default gen_random_uuid(),
  farm_id    uuid not null references farm(id),
  crop_id    uuid not null references crop(id),
  cycle_id   uuid references crop_cycle(id),
  zone_id    uuid not null references zone(id),
  start_date date not null,
  status     text not null default 'planned' check (status in ('planned','active','finished','cancelled')),
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists crop_plan_position (
  id          uuid primary key default gen_random_uuid(),
  plan_id     uuid not null references crop_plan(id) on delete cascade,
  position_id uuid not null references position(id),
  quantity    numeric not null check (quantity > 0),   -- in `unit`
  unit        text not null default 'plant' check (unit in ('plant','tray')),
  unique (plan_id, position_id)
);
alter table task drop constraint if exists task_plan_id_fkey;
alter table task add constraint task_plan_id_fkey foreign key (plan_id) references crop_plan(id) on delete set null;

-- ── 3. procedures on phases ───────────────────────────────────────────────────
create table if not exists crop_phase_sop (
  id         uuid primary key default gen_random_uuid(),
  phase_id   uuid not null references crop_phase(id) on delete cascade,
  sop_id     uuid not null references sop(id),
  day_offset int  not null default 0,                   -- days after the phase starts
  repeat_days int check (repeat_days is null or repeat_days > 0), -- null = once; n = every n days while the phase lasts
  seq        int  not null default 1,
  unique (phase_id, sop_id, day_offset)
);
create index if not exists crop_phase_sop_phase_idx on crop_phase_sop(phase_id);

-- ── 4. positions of a grouped task ────────────────────────────────────────────
create table if not exists task_position (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references task(id) on delete cascade,
  position_id uuid references position(id) on delete set null,
  position_code text,                                  -- kept so a deleted position still reads on the phone
  quantity    numeric not null default 0,
  unit        text,
  minutes     numeric not null default 0,
  updated_at  timestamptz not null default now(),
  unique (task_id, position_id)
);
create index if not exists task_position_task_idx on task_position(task_id);

-- RLS: a row is visible when its task is (task's own policies decide).
alter table crop_plan          enable row level security;
alter table crop_plan_position enable row level security;
alter table crop_phase_sop     enable row level security;
alter table task_position      enable row level security;
drop policy if exists task_position_via_task on task_position;
create policy task_position_via_task on task_position
  for all using (exists (select 1 from task t where t.id = task_id))
  with check (exists (select 1 from task t where t.id = task_id));
drop policy if exists crop_plan_via_farm on crop_plan;
create policy crop_plan_via_farm on crop_plan
  for all using (exists (select 1 from farm f where f.id = farm_id))
  with check (exists (select 1 from farm f where f.id = farm_id));
drop policy if exists crop_plan_position_via_plan on crop_plan_position;
create policy crop_plan_position_via_plan on crop_plan_position
  for all using (exists (select 1 from crop_plan p where p.id = plan_id))
  with check (exists (select 1 from crop_plan p where p.id = plan_id));
drop policy if exists crop_phase_sop_read on crop_phase_sop;
create policy crop_phase_sop_read on crop_phase_sop for select using (true);
grant select, insert, update, delete on crop_plan, crop_plan_position, task_position to authenticated;
grant select on crop_phase_sop to authenticated;

-- ── 5. units and minutes ──────────────────────────────────────────────────────
-- How many of a procedure's unit one position represents.
create or replace function unit_quantity(p_unit text, p_plants numeric, p_area_m2 numeric, p_plugs_per_tray int)
returns numeric language sql immutable as $$
  select case p_unit
    when 'tray'     then round(coalesce(p_plants, 0) / greatest(coalesce(p_plugs_per_tray, 72), 1)::numeric, 2)
    when 'position' then 1
    when 'plant'    then coalesce(p_plants, 0)
    when 'm2'       then coalesce(p_area_m2, 0)
    else 1 end;
$$;

-- Minutes a procedure takes for a quantity of its unit.
create or replace function sop_minutes(p_base numeric, p_per_unit numeric, p_quantity numeric)
returns numeric language sql immutable as $$
  select round(coalesce(p_base, 0) + coalesce(p_per_unit, 0) * coalesce(p_quantity, 0), 1);
$$;

-- Plants a plan position holds, whatever unit it was entered in.
create or replace function plan_position_plants(p_quantity numeric, p_unit text, p_plugs_per_tray int)
returns numeric language sql immutable as $$
  select case when p_unit = 'tray' then coalesce(p_quantity, 0) * greatest(coalesce(p_plugs_per_tray, 72), 1)
              else coalesce(p_quantity, 0) end;
$$;

-- The version of a procedure the phone should run: latest approved.
create or replace function sop_current_version(p_sop uuid)
returns uuid language sql stable as $$
  select id from sop_version where sop_id = p_sop and approved_at is not null
  order by version desc limit 1;
$$;

-- ── 6. the generator ──────────────────────────────────────────────────────────
-- One task per crop × zone × date per phase procedure; positions underneath.
-- Runs as the CALLER (security invoker): the farm, crop_plan and task RLS
-- policies decide what they may plan. Open tasks are updated IN PLACE (same
-- id, so a phone's queued completion still lands); done ones are left alone;
-- open tasks the plan no longer produces are removed.
create or replace function assert_farm_member(p_farm uuid)
returns void language plpgsql stable as $$
begin
  -- farm rows are only visible to their members (farm RLS), so visibility is membership
  if not exists (select 1 from farm where id = p_farm) then
    raise exception 'not a member of farm %', p_farm using errcode = '42501';
  end if;
end $$;

create or replace function plan_crop_tasks(p_plan uuid, p_replace boolean default true)
returns int language plpgsql security invoker set search_path = public as $$
declare
  v_plan   crop_plan%rowtype;
  v_crop   crop%rowtype;
  v_zone   zone%rowtype;
  v_cycle  uuid;
  v_n      int := 0;
  v_keep   uuid[] := '{}';
  r_phase  record;
  r_sop    record;
  v_start  int;
  v_offset int;
  v_date   date;
  v_task   uuid;
  v_status text;
  v_total_min numeric;
  v_total_qty numeric;
  v_pos_count int;
begin
  select * into v_plan from crop_plan where id = p_plan;
  if not found then raise exception 'plan % not found', p_plan; end if;
  perform assert_farm_member(v_plan.farm_id);
  select * into v_crop from crop where id = v_plan.crop_id;
  select * into v_zone from zone where id = v_plan.zone_id;
  v_cycle := coalesce(v_plan.cycle_id,
    (select id from crop_cycle where crop_id = v_crop.id order by is_default desc nulls last, id limit 1));
  if v_cycle is null then raise exception 'crop % has no cycle', v_crop.name; end if;

  select count(*) into v_pos_count from position where zone_id = v_zone.id;

  v_start := 0;
  for r_phase in
    select ph.id, ph.seq, ph.name, coalesce(ph.days, 0) as days
    from crop_phase ph where ph.cycle_id = v_cycle order by ph.seq
  loop
    for r_sop in
      select cps.id as phase_sop_id, cps.day_offset, cps.repeat_days, s.*
      from crop_phase_sop cps join sop s on s.id = cps.sop_id
      where cps.phase_id = r_phase.id and coalesce(s.status, 'approved') = 'approved'
      order by cps.day_offset, cps.seq
    loop
      v_offset := r_sop.day_offset;
      -- once, or every repeat_days while the phase lasts
      while v_offset <= greatest(r_phase.days - 1, r_sop.day_offset) loop
        v_date := v_plan.start_date + v_start + v_offset;
        v_task := null; v_status := null;
        select id, status into v_task, v_status from task
        where plan_id = p_plan and phase_id = r_phase.id and sop_id = r_sop.id and planned_date = v_date
        order by (status = 'done') desc limit 1;

        if v_status = 'done' then
          v_keep := v_keep || v_task;                 -- done: never touched
        else
          if v_task is null then
            insert into task (farm_id, title, family, sop_id, sop_version_id, planned_date, area,
                              estimated_minutes, status, crop_id, zone_id, phase_id, plan_id, quantity, unit, group_key)
            values (v_plan.farm_id, r_sop.title || ' — ' || v_crop.name, coalesce(r_sop.family, 'agriculture'),
                    r_sop.id, sop_current_version(r_sop.id), v_date, v_zone.name,
                    0, 'open', v_crop.id, v_zone.id, r_phase.id, p_plan, 0, r_sop.unit,
                    p_plan::text || ':' || r_sop.phase_sop_id::text || ':' || v_date::text)
            returning id into v_task;
            v_n := v_n + 1;
          else
            update task set title = r_sop.title || ' — ' || v_crop.name, sop_version_id = sop_current_version(r_sop.id),
                            area = v_zone.name, unit = r_sop.unit, zone_id = v_zone.id, crop_id = v_crop.id
            where id = v_task;
            delete from task_position where task_id = v_task;
          end if;
          v_keep := v_keep || v_task;

          insert into task_position (task_id, position_id, position_code, quantity, unit, minutes)
          select v_task, pos.id, pos.code, q.qty, r_sop.unit,
                 sop_minutes(r_sop.base_minutes, r_sop.minutes_per_unit, q.qty)
          from crop_plan_position cpp
          join position pos on pos.id = cpp.position_id
          cross join lateral (
            select unit_quantity(r_sop.unit,
                     plan_position_plants(cpp.quantity, cpp.unit, v_crop.plugs_per_tray),
                     coalesce(pos.area_m2, v_zone.area_m2 / nullif(v_pos_count, 0)),
                     v_crop.plugs_per_tray) as qty) q
          where cpp.plan_id = p_plan;

          select coalesce(sum(minutes), 0), coalesce(sum(quantity), 0)
            into v_total_min, v_total_qty from task_position where task_id = v_task;
          -- a plan with no positions still gets the base minutes once
          if v_total_min = 0 and not exists (select 1 from task_position where task_id = v_task) then
            v_total_min := sop_minutes(r_sop.base_minutes, r_sop.minutes_per_unit, 0);
          end if;
          update task set estimated_minutes = v_total_min, quantity = v_total_qty where id = v_task;
        end if;
        exit when r_sop.repeat_days is null;
        v_offset := v_offset + r_sop.repeat_days;
      end loop;
    end loop;
    v_start := v_start + r_phase.days;
  end loop;

  if p_replace then                                    -- open tasks the plan no longer produces
    delete from task where plan_id = p_plan and status <> 'done' and not (id = any(v_keep));
  end if;
  update crop_plan set status = 'active', updated_at = now() where id = p_plan and status = 'planned';
  return v_n;
end $$;

-- Plan a crop in one call from the console: positions as [{position_id, quantity, unit}].
create or replace function plan_crop(p_farm uuid, p_crop uuid, p_zone uuid, p_start date,
                                     p_positions jsonb, p_cycle uuid default null)
returns uuid language plpgsql security invoker set search_path = public as $$
declare v_plan uuid;
begin
  perform assert_farm_member(p_farm);
  if not exists (select 1 from zone where id = p_zone and farm_id = p_farm) then
    raise exception 'zone % is not in farm %', p_zone, p_farm;
  end if;
  insert into crop_plan (farm_id, crop_id, cycle_id, zone_id, start_date)
  values (p_farm, p_crop, p_cycle, p_zone, p_start) returning id into v_plan;
  insert into crop_plan_position (plan_id, position_id, quantity, unit)
  select v_plan, (e->>'position_id')::uuid, (e->>'quantity')::numeric, coalesce(e->>'unit', 'plant')
  from jsonb_array_elements(coalesce(p_positions, '[]'::jsonb)) e;
  perform plan_crop_tasks(v_plan, true);
  return v_plan;
end $$;

-- Re-plan every open task of a plan after the crop cycle or a procedure's minutes change.
create or replace function replan_crop(p_plan uuid)
returns int language sql security invoker set search_path = public as $$
  select plan_crop_tasks(p_plan, true);
$$;

-- ── 7. sync_since: wrap the 0.7.56 function, add task_positions + crop/zone names ──
do $$
declare v_args text;
begin
  if not exists (select 1 from pg_proc where proname = 'sync_since_v1' and pronamespace = 'public'::regnamespace)
     and exists (select 1 from pg_proc where proname = 'sync_since' and pronamespace = 'public'::regnamespace) then
    select pg_get_function_identity_arguments(oid) into v_args
      from pg_proc where proname = 'sync_since' and pronamespace = 'public'::regnamespace limit 1;
    execute format('alter function public.sync_since(%s) rename to sync_since_v1', v_args);
  end if;
end $$;

create or replace function sync_since(p_farm uuid, p_since timestamptz)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v jsonb;
  v_tasks jsonb;
  v_positions jsonb;
begin
  v := sync_since_v1(p_farm, p_since);

  select coalesce(jsonb_agg(
           e || jsonb_strip_nulls(jsonb_build_object(
             'crop_name',  c.name,
             'zone_name',  z.name,
             'phase_name', ph.name,
             'quantity',   t.quantity,
             'unit',       t.unit,
             'group_key',  t.group_key))
         order by ord), '[]'::jsonb)
    into v_tasks
  from jsonb_array_elements(coalesce(v->'tasks', '[]'::jsonb)) with ordinality as x(e, ord)
  left join task t  on t.id = (x.e->>'id')::uuid
  left join crop c  on c.id = t.crop_id
  left join zone z  on z.id = t.zone_id
  left join crop_phase ph on ph.id = t.phase_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', tp.id, 'task_id', tp.task_id, 'position_id', tp.position_id,
           'position_code', coalesce(p.code, tp.position_code),
           'quantity', tp.quantity, 'unit', tp.unit, 'minutes', tp.minutes)), '[]'::jsonb)
    into v_positions
  from task_position tp
  left join position p on p.id = tp.position_id
  where tp.task_id in (select (e->>'id')::uuid from jsonb_array_elements(coalesce(v->'tasks', '[]'::jsonb)) e);

  return v || jsonb_build_object('tasks', v_tasks, 'task_positions', v_positions);
end $$;
grant execute on function sync_since(uuid, timestamptz) to authenticated;
grant execute on function plan_crop(uuid, uuid, uuid, date, jsonb, uuid) to authenticated;
grant execute on function plan_crop_tasks(uuid, boolean) to authenticated;
grant execute on function replan_crop(uuid) to authenticated;

-- ── 8. keep task_position minutes in step when a procedure's timing is edited ─
-- Runs as the editor (console owner); open tasks keep their ids.
create or replace function sop_timing_changed() returns trigger language plpgsql security invoker as $$
begin
  if new.base_minutes is distinct from old.base_minutes
     or new.minutes_per_unit is distinct from old.minutes_per_unit
     or new.unit is distinct from old.unit then
    perform replan_crop(p.id)
      from (select distinct plan_id as id from task where sop_id = new.id and plan_id is not null and status <> 'done') p;
  end if;
  return new;
end $$;
drop trigger if exists sop_timing_changed_trg on sop;
create trigger sop_timing_changed_trg after update on sop
  for each row execute function sop_timing_changed();

commit;
