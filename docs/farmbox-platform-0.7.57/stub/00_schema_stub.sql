-- ─────────────────────────────────────────────────────────────────────────────
-- STUB SCHEMA — LOCAL TESTING ONLY. Never run this on Supabase.
--
-- FarmBox-Platform could not be reached from the session that wrote 0.7.57,
-- so this file recreates the *assumed* shape of the tables the migrations
-- touch, from the 0.7.56 handoff notes. Where the real column names differ,
-- fix the migration, not this stub. Every assumption is marked ASSUMED.
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists pgcrypto;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
end $$;

create table farm (
  id uuid primary key default gen_random_uuid(),
  name text not null, code text, timezone text default 'Europe/Rome'
);

create table zone (                                   -- ASSUMED: growing zones (0.7.4x "editable growing zones")
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farm(id),
  name text not null,
  area_m2 numeric,
  system text, medium text
);

create table position (                               -- ASSUMED: a slot in a zone (row, bench, tower…)
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references zone(id),
  code text not null,
  capacity int,                                       -- plants (or trays) it holds
  area_m2 numeric
);

create table crop (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null check (category in ('vines','fruiting','leafy','mixed_leafy','herbs','microgreens')),
  medium text, system text,
  plant_spacing_cm numeric,
  notes text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table crop_cycle (
  id uuid primary key default gen_random_uuid(),
  crop_id uuid not null references crop(id) on delete cascade,
  name text not null default 'Standard',
  system text,
  total_days int,
  is_default boolean default true
);

create table crop_phase (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references crop_cycle(id) on delete cascade,
  seq int not null,
  name text not null,
  days int not null default 0,                        -- length of the phase
  notes text
);

create table sop (                                    -- "procedures" in the console
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text,
  family text default 'agriculture',
  sub_family text,
  trigger_kind text default 'crop_plan',              -- crop_plan | schedule | manual
  managed_in text default 'console',                  -- console | notion
  status text default 'approved',                     -- draft | approved | archived
  validation text default 'checklist',                -- tick | checklist | checklist_evidence
  base_minutes numeric default 0,
  minutes_per_unit numeric default 0,
  unit text default 'position' check (unit in ('tray','position','plant','m2')),
  safety_ppe text, tools text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table sop_version (
  id uuid primary key default gen_random_uuid(),
  sop_id uuid not null references sop(id) on delete cascade,
  version int not null default 1,
  approved_at timestamptz,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table sop_step (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references sop_version(id) on delete cascade,
  seq int not null,
  section text, title text not null,
  instruction text, expected_result text, action_plan text,
  step_type text default 'check',                     -- check | do | measure | record
  evidence text, value_unit text, min_value numeric, max_value numeric, target_source text default 'fixed',
  updated_at timestamptz default now()
);

create table task (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farm(id),
  title text not null,
  family text default 'agriculture',
  sop_id uuid references sop(id),
  sop_version_id uuid references sop_version(id),
  planned_date date not null,
  due_time time,
  area text,
  estimated_minutes numeric default 0,
  status text default 'open',                         -- open | done | cancelled
  done_at timestamptz,
  position_id uuid references position(id),           -- ASSUMED: the old one-task-per-position link
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table release_note (
  id uuid primary key default gen_random_uuid(),
  version text not null, released_on date default current_date, title text, body text
);

-- ASSUMED: the 0.7.5x sync RPC. Real body unknown; this stand-in returns the
-- same top-level keys the phone reads, so the wrapper in the migration can be
-- tested against it.
create or replace function sync_since(p_farm uuid, p_since timestamptz)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'cursor', now(),
    'tasks', coalesce((select jsonb_agg(to_jsonb(t)) from task t where t.farm_id = p_farm), '[]'::jsonb),
    'sops', coalesce((select jsonb_agg(to_jsonb(s)) from sop s), '[]'::jsonb),
    'sop_versions', coalesce((select jsonb_agg(to_jsonb(v)) from sop_version v), '[]'::jsonb),
    'sop_steps', coalesce((select jsonb_agg(to_jsonb(st)) from sop_step st), '[]'::jsonb),
    'deleted', '[]'::jsonb);
$$;

create or replace function complete_task(p_task uuid, p_minutes numeric)
returns void language sql as $$
  update task set status = 'done', done_at = now() where id = p_task;
$$;

create or replace function submit_run(p jsonb)
returns uuid language plpgsql as $$
begin
  update task set status = 'done', done_at = now() where id = (p->>'task_id')::uuid;
  return gen_random_uuid();
end $$;
