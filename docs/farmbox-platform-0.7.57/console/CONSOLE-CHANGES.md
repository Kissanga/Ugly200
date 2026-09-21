# Console 0.7.57 — the Crop database as one drop-in module

The console clone was not reachable from the session that built 0.7.57, so
the whole Crop database page for 0.7.57 ships here as **one self-contained
module** instead of edits to files I could not see:

```
console/farmbox-crops.js   the module (no dependencies beyond a supabase-js v2 client)
console/demo.html          the module running against an in-memory mock — open it in a browser
console/demo-data.js       the tested 0.7.57 library as demo data
```

`demo.html` is the acceptance test: it was driven in headless Chromium through
every flow (list, search, phases, read-only procedure drawer, phase editor +
save + replan, plugs per tray, archive, Archive window + restore, Plan a crop).

## What the module does (decisions 2, 3, 5 and the planner)

- **Crop database** grouped by family with the new labels from `crop_category`
  (Fruiting vines, Fruiting bush, Leafy, Mixed leafy, Herbs, Microgreens),
  archived crops hidden, search box.
- **Per phase, the procedure titles** with day offset, repeat and timing; a
  title opens the procedure read-only (your drawer via `openProcedure`, or the
  module's own drawer showing the approved steps).
- **Edit phases** (editors only): per phase a select of approved `crop_plan`
  procedures + day offset + repeat days; Save rewrites `crop_phase_sop` and
  calls `replan_crop` on the crop's open plans.
- **Plugs per tray** inline on the crop.
- **Archive…** on a crop (reason optional, never deletes) and the **Archive**
  button in the page head opening the window with **Restore**.
- **Plan a crop**: crop, farm, zone, start date, positions with quantity and
  unit → `plan_crop()`; the toast says how many tasks were created.

## Integration (10 minutes)

1. Copy `farmbox-crops.js` to `console/js/`.
2. On the Crop database page, replace the current list with a container and
   mount the module:

```html
<div id="cropDb"></div>
<script src="js/farmbox-crops.js?v=0.7.57"></script>
<script>
  FarmBoxCrops.mount({
    el: document.getElementById('cropDb'),
    sb: supabase,                               // the page's supabase-js v2 client
    canEdit: currentUserCanEditCrops,           // owner/agronomist → true
    openProcedure: id => openProcedureDrawer(id, { readOnly: true })   // optional: reuse your drawer
  });
</script>
```

3. Theme: the module reads `--fbc-ink`, `--fbc-muted`, `--fbc-line`,
   `--fbc-surface`, `--fbc-accent` if defined on the page; otherwise it uses
   neutral defaults. Map them to the console's tokens in one CSS rule.
4. Grants for the editor (done by `apply-0757.ps1`, or run by hand):

```sql
grant insert, update, delete on crop_phase_sop to authenticated;
create policy crop_phase_sop_edit on crop_phase_sop for all using (true) with check (true);
```

5. Elsewhere in the console, replace the old category codes:
   `grep -rn "vines\|'fruiting'" console/js` → `fruiting_vines` / `fruiting_bush`,
   or read labels from `crop_category` as the module does.
6. Task list: one row per task; expand to show `task_position`
   (`select * from task_position where task_id = …`).

## Release checklist (every release)

```
console/js/update.js     VERSION = '0.7.57'
version.json             "version": "0.7.57"
index.html               ?v=0.7.57 on every script/style
sw.js                    CACHE = 'console-0.7.57'
data/release_notes_0757.sql   (applied by apply-0757.ps1)
deploy-console.ps1
```
