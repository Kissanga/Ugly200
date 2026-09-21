# Console 0.7.57 — changes to make in farmbox-console

The console clone was not reachable from the session that built 0.7.57, so
these are fragments against the conventions described in the 0.7.56 handoff
(vanilla JS pages, a procedure drawer, an editable Crop page, `VERSION` in
`console/js/update.js`). Adapt names to the real files.

## 1. Category codes and labels

Replace every hard-coded category list with the catalogue table:

```js
// once, at page load (cached)
const CATEGORIES = await sb.from('crop_category').select('code,label,seq,default_medium,default_system,default_plugs_per_tray').order('seq');
const catLabel = code => CATEGORIES.find(c => c.code === code)?.label || code;
```

`grep -rn "vines\|'fruiting'" console/` — every hit becomes `fruiting_vines` /
`fruiting_bush` (constants, filters, media defaults, the coloured labels).

## 2. Crop database: hide archived, Archive window

```js
// list
const { data: crops } = await sb.from('crop_library').select('*').is('archived_at', null)
  .order('category_seq').order('name');

// page head
<button class="btn" id="cropArchiveBtn">Archive</button>

// window
async function openCropArchive() {
  const { data } = await sb.from('crop').select('id,name,category,archived_at,archived_reason')
    .not('archived_at', 'is', null).order('name');
  openDrawer('Archived crops', data.map(c => `
    <div class="row">
      <div><b>${esc(c.name)}</b> <span class="muted">${catLabel(c.category)}</span>
        <div class="muted small">${fmtDate(c.archived_at)} · ${esc(c.archived_reason || '')}</div></div>
      <button class="btn btn-sm" data-restore="${c.id}">Restore</button>
    </div>`).join('') || '<p class="muted">Nothing archived.</p>');
  drawer.querySelectorAll('[data-restore]').forEach(b => b.onclick = async () => {
    await sb.rpc('restore_crop', { p_crop: b.dataset.restore }); openCropArchive(); reloadCrops();
  });
}
// the row menu on an active crop
async function archiveCrop(id) {
  const reason = prompt('Why archive this crop? (optional)') || null;
  await sb.rpc('archive_crop', { p_crop: id, p_reason: reason }); reloadCrops();
}
```

## 3. Crop database: procedure titles per phase (read-only link)

`crop_library.phases` is `[{seq,name,days,procedures:[{id,title,day_offset,repeat_days,unit,base_minutes,minutes_per_unit}]}]`.

```js
function phaseRows(crop) {
  return crop.phases.map(ph => `
    <tr><td>${ph.seq}</td><td>${esc(ph.name)}</td><td>${ph.days} d</td>
      <td>${ph.procedures.map(p => `
        <a href="#" class="proc-link" data-sop="${p.id}">${esc(p.title)}</a>
        <span class="muted small">day ${p.day_offset}${p.repeat_days ? ` · every ${p.repeat_days} d` : ''}
          · ${p.base_minutes} + ${p.minutes_per_unit}/${p.unit}</span>`).join('<br>')}</td></tr>`).join('');
}
document.addEventListener('click', e => {
  const a = e.target.closest('.proc-link'); if (!a) return;
  e.preventDefault(); openProcedureDrawer(a.dataset.sop, { readOnly: true });
});
```

## 4. Crop editor: pick a procedure per phase

```js
const { data: approved } = await sb.from('sop').select('id,title,unit,base_minutes,minutes_per_unit')
  .eq('status', 'approved').eq('trigger_kind', 'crop_plan').order('title');

function phaseProcEditor(ph) {          // ph.procedures = current links
  return `
    <div class="phase-procs" data-phase="${ph.id}">
      ${ph.procedures.map(p => procRow(p)).join('')}
      <button type="button" class="btn btn-sm add-proc">+ procedure</button>
    </div>`;
}
const procRow = (p = {}) => `
  <div class="proc-row">
    <select name="sop_id">${approved.map(s => `<option value="${s.id}" ${s.id === p.id ? 'selected' : ''}>${esc(s.title)}</option>`).join('')}</select>
    <label>day <input type="number" name="day_offset" value="${p.day_offset ?? 0}" min="0" style="width:4em"></label>
    <label>every <input type="number" name="repeat_days" value="${p.repeat_days ?? ''}" min="1" placeholder="once" style="width:4em"> d</label>
    <button type="button" class="btn-icon del-proc" aria-label="Remove">×</button>
  </div>`;

async function savePhaseProcs(phaseId, rows) {   // rows = [{sop_id, day_offset, repeat_days}]
  await sb.from('crop_phase_sop').delete().eq('phase_id', phaseId);
  if (rows.length) await sb.from('crop_phase_sop').insert(rows.map((r, i) => ({ phase_id: phaseId, ...r, seq: i + 1 })));
  // open tasks of plans on this crop follow the new links:
  const { data: plans } = await sb.from('crop_plan').select('id').eq('crop_id', cropId).in('status', ['planned', 'active']);
  for (const p of plans) await sb.rpc('replan_crop', { p_plan: p.id });
}
```

`crop_phase_sop` is read-only for `authenticated` in the migration (`crop_phase_sop_read`);
grant insert/update/delete to the console's role (or add a policy for the
console's editor role) before this editor goes live:

```sql
grant insert, update, delete on crop_phase_sop to authenticated;   -- or the console role
create policy crop_phase_sop_edit on crop_phase_sop for all using (true) with check (true);
```

The crop editor also gets **Plugs per tray** (`crop.plugs_per_tray`, default
from `crop_category.default_plugs_per_tray`).

## 5. Plan a crop

```js
async function planCrop({ farmId, cropId, zoneId, startDate, positions }) {
  // positions: [{position_id, quantity, unit:'plant'|'tray'}]
  const { data: planId, error } = await sb.rpc('plan_crop', {
    p_farm: farmId, p_crop: cropId, p_zone: zoneId, p_start: startDate, p_positions: positions });
  if (error) throw error;
  return planId;                         // tasks + task_position rows exist now
}
// after editing a plan's positions or dates:
await sb.rpc('replan_crop', { p_plan: planId });   // open tasks regenerated, done ones kept
```

Task list in the console: one row per task; expand to show `task_position`
(`select * from task_position where task_id = …`).

## 6. Release checklist (every release)

```
console/js/update.js     VERSION = '0.7.57'
version.json             "version": "0.7.57"
index.html               ?v=0.7.57 on every script/style
sw.js                    CACHE = 'console-0.7.57'
data/release_notes_0757.sql   (already written)
deploy-console.ps1
```
