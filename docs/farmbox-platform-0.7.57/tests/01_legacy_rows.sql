-- Legacy rows a 0.7.56 database would hold, so the tests prove the rename,
-- alias matching, archiving and the untouched legacy task. Local only.
insert into farm (id, name, code) values ('00000000-0000-0000-0000-000000000001', 'Test farm', 'F1');
insert into zone (id, farm_id, name, area_m2) values ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 'Zone 1', 30);
insert into position (zone_id, code, area_m2) values
  ('00000000-0000-0000-0000-000000000010', 'Z1-R1', 10),
  ('00000000-0000-0000-0000-000000000010', 'Z1-R2', 10),
  ('00000000-0000-0000-0000-000000000010', 'Z1-R3', 10);
-- an old crop under the old category and an old name: must become
-- "Tomato cherry indeterminate" / fruiting_vines, not a duplicate
insert into crop (name, category, medium, system) values ('Cherry tomato', 'vines', 'Slab', 'Drip-irrigated substrate');
-- an old fruiting crop that IS in the list under the same name
insert into crop (name, category) values ('Eggplant', 'fruiting');
-- a crop not in the list: archived, never deleted
insert into crop (name, category) values ('Old lettuce', 'leafy');
-- media defaults keyed by the old category codes, with their own CHECK
insert into media_default (category, medium, system) values ('vines', 'Slab', 'Drip-irrigated substrate'), ('fruiting', 'Bucket', 'Drip-irrigated substrate'), ('leafy', 'Net cup', 'NFT');
-- one of the 21 existing per-batch procedures, with its own timing and one step
with s as (insert into sop (title, trigger_kind, managed_in, status, base_minutes, minutes_per_unit, unit)
           values ('Scout for pests and disease', 'crop_plan', 'console', 'approved', 4, 5, 'position') returning id),
     v as (insert into sop_version (sop_id, version, approved_at) select id, 1, now() from s returning id)
insert into sop_step (version_id, seq, section, title, step_type) select id, 1, 'Look', 'Existing step', 'check' from v;
-- a task from before 0.7.57 (no crop, no positions)
insert into task (farm_id, title, planned_date, area, estimated_minutes)
values ('00000000-0000-0000-0000-000000000001', 'Legacy task', current_date, 'Pump room', 20);
