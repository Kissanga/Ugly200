# GO-LIVE 0.7.57 — grouped tasks, crop library, phone screens

Written 21 Sept 2026 from a cloud session that could reach **Ugly200 only**:
the FarmBox-Platform repo, the Supabase project and the console clone were not
reachable (GitHub scope + egress policy). So:

- **Naked Brain 0.11.5 is done and pushed** to `Kissanga/Ugly200 main`
  (commit "Naked Brain 0.11.5 — Grouped tasks with positions, two-level checklist").
  It works against the 0.7.56 database *today* (it groups one-task-per-position
  rows itself) and gets richer once the SQL below is live.
- **The platform side is delivered here as drop-in files**, tested on a local
  Postgres 16 against a stub of the assumed schema (`stub/`). Copy them into
  FarmBox-Platform, check the ASSUMED names, run the suite, commit, deploy.

Everything below is ordered. Do it top to bottom on your machine.

---

## 0. Before anything: 5-minute schema check

The SQL was written against the names in `stub/00_schema_stub.sql`. Confirm
these on the live project; each one that differs is a one-line fix in the
migration (search for `ASSUMED`).

```powershell
supabase db query --linked "select table_name, column_name from information_schema.columns where table_schema='public' and table_name in ('zone','position','crop','crop_cycle','crop_phase','sop','sop_version','sop_step','task') order by 1,2"
supabase db query --linked "select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname in ('sync_since','submit_run','complete_task')"
```

| Assumed | Used for | If different |
|---|---|---|
| `zone(id, farm_id, name, area_m2)` | task.area, m² unit | rename in `plan_crop_tasks`, `sync_since` |
| `position(id, zone_id, code, area_m2)` | task_position, m² share | rename in `plan_crop_tasks`, `sync_since`, `crop_library` |
| `crop_cycle(id, crop_id, is_default)` / `crop_phase(id, cycle_id, seq, name, days)` | phases & offsets | rename in `plan_crop_tasks`, `crop_library`, `lib_crop` |
| `sop(status='approved', base_minutes, minutes_per_unit, unit)` | timing | columns are added if missing; `status` values may need mapping |
| `sop_version(sop_id, version, approved_at)` | `sop_current_version()` | adapt that one function |
| `sync_since(uuid, timestamptz)` returns jsonb `{cursor,tasks,sops,sop_versions,sop_steps,deleted}` | the wrapper renames it to `sync_since_v1` and calls it | the rename block finds it by name whatever the argument types |
| farm membership table | RLS on `crop_plan`; the `assert_farm_member()` guard | both rely on `farm` rows being visible only to members (farm RLS). If `farm` is readable by everyone, replace the `exists (select 1 from farm …)` in both with the membership check `task` uses |
| `task` RLS allows the console user to insert/update/delete | `plan_crop`, `plan_crop_tasks`, `replan_crop` run as the caller (security invoker), so the caller's own policies apply | if workers must be able to plan, widen `task` policies; never switch the functions back to definer without a membership check inside |

The 21 existing per-batch procedures: the library matches by **title**. List
them first and, where a library title says the same thing under another name,
either rename the existing one or add its title to `gen/crop_library.js` so
the phase links land on it instead of creating a twin:

```powershell
supabase db query --linked "select title, base_minutes, minutes_per_unit, unit from sop where trigger_kind='crop_plan' order by title"
```

Sub-family names used by the new procedures: `Sowing & nursery`,
`Transplanting`, `Crop care`, `Irrigation & nutrition`, `Scouting & IPM`,
`Harvest`, `Cleaning & sanitation`. Map them to your Settings › Task families
list (a `replace` in the generator) before running the library.

## 1. Copy the files into FarmBox-Platform

```
migrations/20260921120000_phase_a_grouped_tasks.sql
migrations/20260921120100_phase_b_categories_archive.sql
data/crop_library_0757.sql              (generated — keep gen/crop_library.js next to it)
data/release_notes_0757.sql
tests/phase_ab_test.sql                 (fold into tests/rls_test.sql PASS style, or keep as a second file)
```

## 2. Run the fresh-container suite locally

Per CLAUDE.md: migrations/*.sql → seed.sql → data/*.sql → tests/rls_test.sql.
Expected: 118 PASS from before + the 9 blocks in `tests/phase_ab_test.sql`.
`tests/run_local.sh` here shows the exact order used against the stub.

## 3. Apply to the linked project (never `supabase db push`)

```powershell
supabase db query --linked -f migrations/20260921120000_phase_a_grouped_tasks.sql
supabase migration repair --status applied 20260921120000
supabase db query --linked -f migrations/20260921120100_phase_b_categories_archive.sql
supabase migration repair --status applied 20260921120100
supabase db query --linked -f data/crop_library_0757.sql
#   → prints active_crops=50, archived_crops=N, crop_plan_procedures≈31+, phases_without_procedure=0
supabase db query --linked -f data/release_notes_0757.sql
```

Smoke test on the live data (read-only):

```powershell
supabase db query --linked "select name, category, plugs_per_tray from crop where archived_at is null order by category, name"
supabase db query --linked "select name from crop where archived_at is not null"
supabase db query --linked "select jsonb_pretty(phases) from crop_library where name='Basil'"
```

Plan one real crop and look at the tasks:

```powershell
supabase db query --linked "select plan_crop('<farm>', (select id from crop where name='Butterhead lettuce'), '<zone>', current_date, '[{\"position_id\":\"<pos>\",\"quantity\":2,\"unit\":\"tray\"}]'::jsonb)"
supabase db query --linked "select planned_date, title, quantity, unit, estimated_minutes from task where plan_id='<plan>' order by 1 limit 20"
supabase db query --linked "select * from task_position where task_id=(select id from task where plan_id='<plan>' order by planned_date limit 1)"
```

Replanning (a cycle or timing edit) updates open tasks **in place**: same task ids, positions and minutes recomputed, done tasks untouched, surplus open tasks removed. A phone's queued completion for an open task therefore still lands after a replan.

No Edge Function changes are needed: `sync_since`, `complete_task` and
`submit_run` keep their signatures (the phone adds `position_ids` to the
submit_run payload, which the jsonb parameter ignores).

## 4. Console 0.7.57

`console/CONSOLE-CHANGES.md` has the fragments. In order:

1. Category labels: `vines`/`fruiting` → `fruiting_vines`/`fruiting_bush`
   everywhere in the console (`grep -rn "vines\|'fruiting'" console/js`),
   preferably reading `crop_category` instead of a hard-coded list.
2. Crop database: hide `archived_at is not null`; page-head button **Archive**
   opens a window listing archived crops with a Restore action.
3. Crop database: per phase, the procedure title(s) with a link that opens
   the procedure drawer read-only (data from the `crop_library` view).
4. Crop editor: per phase, a select of approved procedures + day offset +
   repeat days, saved to `crop_phase_sop`.
5. Plan crop dialog: crop, zone, positions with quantity/unit → `plan_crop()`;
   an existing plan → `replan_crop()`.
6. Release: bump `VERSION` in `console/js/update.js` and `version.json`,
   `?v=0.7.57` in `index.html`, `CACHE` in `sw.js`; run `deploy-console.ps1`.

## 5. Phone (already live once you refresh)

Naked Brain 0.11.5 is on `main`; the phone picks it up through `version.json`
("Update now"). With the 0.7.56 database it groups tasks itself; with 0.7.57
it shows crop, phase, quantity and the server's positions.

## What was decided and where it lives

| Decision | Where |
|---|---|
| (1) one task per crop × zone × date, positions with own minutes; `plugs_per_tray`; units | Phase A migration §1, §4, §5, §6; phone `loadGroups()` |
| (2) procedures on phases with day offset; titles shown per phase; editor select | Phase A §3 (`crop_phase_sop`), Phase B `crop_library` view, console spec §3–4 |
| (3) fruiting_vines / fruiting_bush | Phase B §1 + `crop_category`; generator uses the new codes |
| (4) 50-crop library, every phase with a procedure, 21 existing reused, ~10 new | `data/crop_library_0757.sql` (31 procedures, 30 new in a clean DB; fewer once titles are reconciled) |
| (5) archive, never delete; Archive window | Phase B §2, library's final UPDATE, console spec §2 |
| (6) Naked Brain grouped card + Details tap | Ugly200 `index.html` 0.11.5 |
