-- ─────────────────────────────────────────────────────────────────────────────
-- 0.7.57 · Phase B — crop categories renamed, crop archive
--
-- Decisions (owner, 21 Sept 2026):
--   (3) vines → fruiting_vines "Fruiting vines"; fruiting → fruiting_bush
--       "Fruiting bush", everywhere (constraints, seeds, media defaults,
--       console lists).
--   (5) crops not in the 50-crop library are ARCHIVED, never deleted. The
--       Crop database hides archived crops; an "Archive" window lists them.
--
-- Apply on the owner's machine:
--   supabase db query --linked -f migrations/20260921120100_phase_b_categories_archive.sql
--   supabase migration repair --status applied 20260921120100
-- ─────────────────────────────────────────────────────────────────────────────
begin;

-- ── 1. categories ─────────────────────────────────────────────────────────────
-- Every CHECK in public that names the old values (crop, media defaults, zone
-- defaults…) is dropped, the values are renamed in every table with a
-- `category` column, and each CHECK is put back with the new values.
-- Constraint and table names are discovered, not assumed.
create temp table _cat_checks as
  select conrelid::regclass as tbl, conname, pg_get_constraintdef(oid) as def
  from pg_constraint
  where contype = 'c' and connamespace = 'public'::regnamespace
    and pg_get_constraintdef(oid) ~ '''vines''|''fruiting''';
do $$
declare r record;
begin
  for r in select * from _cat_checks loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
  for r in
    select c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'category' and t.table_type = 'BASE TABLE'
  loop
    execute format('update %I set category = ''fruiting_vines'' where category = ''vines''', r.table_name);
    execute format('update %I set category = ''fruiting_bush''  where category = ''fruiting''', r.table_name);
  end loop;
  for r in select * from _cat_checks loop
    execute format('alter table %s add constraint %I %s', r.tbl, r.conname,
      replace(replace(r.def, '''vines''', '''fruiting_vines'''), '''fruiting''', '''fruiting_bush'''));
  end loop;
end $$;
drop table _cat_checks;

-- crop always ends up with the six-value check, whatever it had before
alter table crop drop constraint if exists crop_category_check;
alter table crop add constraint crop_category_check
  check (category in ('fruiting_vines','fruiting_bush','leafy','mixed_leafy','herbs','microgreens'));

-- Category catalogue for the console (label + default medium/system + plugs per tray).
create table if not exists crop_category (
  code  text primary key,
  label text not null,
  seq   int  not null,
  default_medium text,
  default_system text,
  default_plugs_per_tray int not null default 72
);
insert into crop_category (code, label, seq, default_medium, default_system, default_plugs_per_tray) values
  ('fruiting_vines', 'Fruiting vines', 1, 'Slab',     'Drip-irrigated substrate', 40),
  ('fruiting_bush',  'Fruiting bush',  2, 'Bucket',   'Drip-irrigated substrate', 40),
  ('leafy',          'Leafy',          3, 'Net cup',  'NFT',                      128),
  ('mixed_leafy',    'Mixed leafy',    4, 'Net cup',  'NFT',                      128),
  ('herbs',          'Herbs',          5, 'Net cup',  'NFT',                      128),
  ('microgreens',    'Microgreens',    6, 'Trays',    'Ebb & flow',               1)
on conflict (code) do update set label = excluded.label, seq = excluded.seq,
  default_medium = excluded.default_medium, default_system = excluded.default_system,
  default_plugs_per_tray = excluded.default_plugs_per_tray;
alter table crop_category enable row level security;
drop policy if exists crop_category_read on crop_category;
create policy crop_category_read on crop_category for select using (true);
grant select on crop_category to authenticated, anon;

-- ── 2. archive ────────────────────────────────────────────────────────────────
alter table crop add column if not exists archived_at timestamptz;
alter table crop add column if not exists archived_reason text;
create index if not exists crop_active_idx on crop(name) where archived_at is null;

create or replace function archive_crop(p_crop uuid, p_reason text default null)
returns void language sql security definer set search_path = public as $$
  update crop set archived_at = coalesce(archived_at, now()), archived_reason = coalesce(p_reason, archived_reason),
                  updated_at = now()
  where id = p_crop;
$$;
create or replace function restore_crop(p_crop uuid)
returns void language sql security definer set search_path = public as $$
  update crop set archived_at = null, archived_reason = null, updated_at = now() where id = p_crop;
$$;
grant execute on function archive_crop(uuid, text), restore_crop(uuid) to authenticated;

-- What the Crop database page reads: active crops with their cycle and phases,
-- each phase with the procedure titles attached (decision 2).
create or replace view crop_library as
select c.id, c.name, c.category, cc.label as category_label, cc.seq as category_seq,
       c.medium, c.system, c.plugs_per_tray, c.archived_at,
       cy.id as cycle_id, cy.name as cycle_name,
       (select coalesce(sum(days), 0) from crop_phase where cycle_id = cy.id) as cycle_days,
       (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', ph.id, 'seq', ph.seq, 'name', ph.name, 'days', ph.days,
                 'procedures', (select coalesce(jsonb_agg(jsonb_build_object(
                                  'id', s.id, 'title', s.title, 'day_offset', cps.day_offset,
                                  'repeat_days', cps.repeat_days, 'unit', s.unit,
                                  'base_minutes', s.base_minutes, 'minutes_per_unit', s.minutes_per_unit)
                                  order by cps.day_offset, cps.seq), '[]'::jsonb)
                                from crop_phase_sop cps join sop s on s.id = cps.sop_id where cps.phase_id = ph.id))
               order by ph.seq), '[]'::jsonb)
          from crop_phase ph where ph.cycle_id = cy.id) as phases
from crop c
left join crop_category cc on cc.code = c.category
left join lateral (select * from crop_cycle where crop_id = c.id order by is_default desc nulls last, id limit 1) cy on true;
grant select on crop_library to authenticated;

commit;
