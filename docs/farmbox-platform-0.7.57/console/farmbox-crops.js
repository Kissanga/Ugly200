/* farmbox-crops.js — Crop database for the FarmBox console, 0.7.57.
 *
 * One drop-in module: the crop list by family (archived hidden), an Archive
 * window with Restore, per-phase procedure titles that open read-only, a phase
 * procedure editor (select from approved procedures + day offset + repeat),
 * plugs per tray, and a "Plan a crop" dialog that calls plan_crop().
 *
 *   <div id="cropDb"></div>
 *   <script src="js/farmbox-crops.js"></script>
 *   <script>FarmBoxCrops.mount({ el: document.getElementById('cropDb'), sb: supabase, canEdit: true,
 *                                openProcedure: id => openProcedureDrawer(id, { readOnly: true }) });</script>
 *
 * `sb` is a supabase-js v2 client. `openProcedure` is optional: without it the
 * module shows the procedure's approved steps in its own read-only drawer.
 * Talks only to: crop_category, crop_library (view), crop, crop_phase_sop, sop,
 * sop_version, sop_step, farm, zone, position, crop_plan, task and the RPCs
 * archive_crop, restore_crop, plan_crop, replan_crop.
 */
(function (global) {
  'use strict';
  const CSS = `
  .fbc { font: 14px/1.5 system-ui, sans-serif; color: var(--fbc-ink, #1c2320); }
  .fbc * { box-sizing: border-box; }
  .fbc-head { display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin-bottom:14px; }
  .fbc-head h2 { margin:0; font-size:20px; flex:1; }
  .fbc input[type=search], .fbc select, .fbc input[type=number], .fbc input[type=date], .fbc input[type=text] { font:inherit; padding:6px 8px; border:1px solid var(--fbc-line,#d5d9d4); border-radius:6px; background:var(--fbc-surface,#fff); color:inherit; }
  .fbc-btn { font:inherit; font-weight:600; padding:7px 12px; border-radius:6px; border:1px solid var(--fbc-line,#d5d9d4); background:var(--fbc-surface,#fff); color:inherit; cursor:pointer; }
  .fbc-btn.primary { background:var(--fbc-accent,#1f7a5c); border-color:var(--fbc-accent,#1f7a5c); color:#fff; }
  .fbc-btn.small { padding:3px 8px; font-size:12px; font-weight:500; }
  .fbc-btn:disabled { opacity:.5; cursor:default; }
  .fbc-fam { font-size:12px; text-transform:uppercase; letter-spacing:.08em; color:var(--fbc-muted,#5b665f); margin:18px 0 6px; display:flex; gap:8px; align-items:center; }
  .fbc-fam i { width:10px; height:10px; border-radius:2px; background:var(--dot); display:inline-block; }
  .fbc-row { border:1px solid var(--fbc-line,#d5d9d4); border-radius:8px; background:var(--fbc-surface,#fff); margin-bottom:6px; }
  .fbc-row > summary { list-style:none; cursor:pointer; padding:9px 12px; display:grid; grid-template-columns:1fr auto auto; gap:4px 14px; align-items:center; }
  .fbc-row > summary::-webkit-details-marker { display:none; }
  .fbc-row b { font-weight:600; }
  .fbc-meta { color:var(--fbc-muted,#5b665f); font-size:12.5px; }
  .fbc-mono { font-family: ui-monospace, monospace; font-size:12.5px; color:var(--fbc-muted,#5b665f); white-space:nowrap; }
  .fbc-body { border-top:1px solid var(--fbc-line,#d5d9d4); padding:8px 12px 12px; }
  .fbc-tools { display:flex; gap:8px; flex-wrap:wrap; align-items:center; margin:4px 0 8px; }
  .fbc-tools label { color:var(--fbc-muted,#5b665f); font-size:12.5px; }
  .fbc-tools input[type=number] { width:70px; }
  .fbc-phase { display:grid; grid-template-columns:170px 1fr; gap:4px 14px; padding:8px 0; border-top:1px dashed var(--fbc-line,#d5d9d4); }
  .fbc-phase:first-of-type { border-top:0; }
  .fbc-proc { font-size:13px; margin-bottom:3px; display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
  .fbc-proc a { color:var(--fbc-accent,#1f7a5c); text-decoration:none; font-weight:500; cursor:pointer; }
  .fbc-proc a:hover { text-decoration:underline; }
  .fbc-proc-edit { display:flex; gap:6px; align-items:center; flex-wrap:wrap; margin-bottom:4px; font-size:12.5px; }
  .fbc-proc-edit select { max-width:280px; }
  .fbc-proc-edit input[type=number] { width:64px; }
  .fbc-modal { position:fixed; inset:0; background:rgba(0,0,0,.35); display:flex; align-items:flex-start; justify-content:center; padding:5vh 16px; z-index:1000; overflow:auto; }
  .fbc-dialog { background:var(--fbc-surface,#fff); color:inherit; border-radius:10px; max-width:640px; width:100%; padding:18px 20px; box-shadow:0 10px 40px rgba(0,0,0,.25); }
  .fbc-dialog h3 { margin:0 0 10px; font-size:18px; }
  .fbc-dialog .fbc-close { float:right; }
  .fbc-field { display:grid; grid-template-columns:130px 1fr; gap:6px 10px; align-items:center; margin-bottom:8px; }
  .fbc-pos { display:grid; grid-template-columns:auto 1fr 90px 90px; gap:6px 10px; align-items:center; padding:4px 0; border-top:1px dashed var(--fbc-line,#d5d9d4); font-size:13px; }
  .fbc-step { padding:8px 0; border-top:1px dashed var(--fbc-line,#d5d9d4); font-size:13px; }
  .fbc-step .sec { font-size:11px; text-transform:uppercase; letter-spacing:.08em; color:var(--fbc-muted,#5b665f); }
  .fbc-step .d { color:var(--fbc-muted,#5b665f); }
  .fbc-empty { color:var(--fbc-muted,#5b665f); padding:12px 0; }
  .fbc-toast { position:fixed; left:50%; bottom:24px; transform:translateX(-50%); background:#1c2320; color:#fff; padding:10px 16px; border-radius:8px; font-size:14px; z-index:1100; }
  @media (max-width:560px) { .fbc-phase, .fbc-field { grid-template-columns:1fr; } .fbc-row > summary { grid-template-columns:1fr; } }
  `;
  const COLORS = { fruiting_vines: '#b5451b', fruiting_bush: '#c2731f', leafy: '#2e7d32', mixed_leafy: '#4c8c2b', herbs: '#1f7a5c', microgreens: '#3b6fb6' };
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const el = (tag, cls, html) => { const n = document.createElement(tag); if (cls) n.className = cls; if (html != null) n.innerHTML = html; return n; };
  const unitWord = u => ({ tray: 'tray', position: 'position', plant: 'plant', m2: 'm²' }[u] || u || '');
  const ok = r => { if (r.error) throw new Error(r.error.message || String(r.error)); return r.data; };

  function toast(msg) {
    const t = el('div', 'fbc-toast', esc(msg)); document.body.appendChild(t);
    setTimeout(() => t.remove(), 2600);
  }
  function modal(title) {
    const wrap = el('div', 'fbc-modal'); const box = el('div', 'fbc-dialog');
    box.innerHTML = `<button class="fbc-btn small fbc-close" aria-label="Close">×</button><h3>${esc(title)}</h3>`;
    const body = el('div'); box.appendChild(body); wrap.appendChild(box); document.body.appendChild(wrap);
    const close = () => wrap.remove();
    box.querySelector('.fbc-close').onclick = close;
    wrap.addEventListener('click', e => { if (e.target === wrap) close(); });
    return { body, close };
  }

  async function mount(opts) {
    const { el: root, sb } = opts;
    const canEdit = !!opts.canEdit;
    if (!document.getElementById('fbc-style')) { const s = el('style'); s.id = 'fbc-style'; s.textContent = CSS; document.head.appendChild(s); }
    root.classList.add('fbc');
    const state = { cats: [], crops: [], procs: [], q: '' };

    async function load() {
      state.cats = ok(await sb.from('crop_category').select('code,label,seq,default_medium,default_system,default_plugs_per_tray').order('seq'));
      state.crops = ok(await sb.from('crop_library').select('*').is('archived_at', null).order('category_seq').order('name'));
      state.procs = ok(await sb.from('sop').select('id,title,unit,base_minutes,minutes_per_unit').eq('status', 'approved').eq('trigger_kind', 'crop_plan').order('title'));
    }
    const catLabel = code => state.cats.find(c => c.code === code)?.label || code;

    function render() {
      root.innerHTML = '';
      const head = el('div', 'fbc-head', `<h2>Crop database</h2>
        <input type="search" id="fbc-q" placeholder="Search crops" value="${esc(state.q)}" aria-label="Search crops">
        ${canEdit ? '<button class="fbc-btn primary" id="fbc-plan">Plan a crop</button>' : ''}
        <button class="fbc-btn" id="fbc-archive">Archive</button>`);
      root.appendChild(head);
      head.querySelector('#fbc-q').oninput = e => { state.q = e.target.value; renderList(); };
      head.querySelector('#fbc-archive').onclick = openArchive;
      if (canEdit) head.querySelector('#fbc-plan').onclick = () => openPlan();
      root.appendChild(el('div', null)).id = 'fbc-list';
      renderList();
    }

    function renderList() {
      const list = root.querySelector('#fbc-list'); list.innerHTML = '';
      const q = state.q.trim().toLowerCase();
      const crops = state.crops.filter(c => !q || c.name.toLowerCase().includes(q) || catLabel(c.category).toLowerCase().includes(q));
      if (!crops.length) { list.appendChild(el('div', 'fbc-empty', 'No crops match.')); return; }
      let cat = null;
      for (const c of crops) {
        if (c.category !== cat) { cat = c.category; list.appendChild(el('div', 'fbc-fam', `<i style="--dot:${COLORS[cat] || '#888'}"></i>${esc(catLabel(cat))} · ${crops.filter(x => x.category === cat).length}`)); }
        list.appendChild(cropRow(c));
      }
    }

    function cropRow(c) {
      const phases = c.phases || [];
      const d = el('details', 'fbc-row');
      d.innerHTML = `<summary><span><b>${esc(c.name)}</b><div class="fbc-meta">${esc(c.medium || '')} · ${esc(c.system || '')} · ${c.plugs_per_tray} plugs/tray · ${phases.length} phases</div></span>
        <span class="fbc-mono">${c.cycle_days} days</span><span></span></summary>`;
      const body = el('div', 'fbc-body'); d.appendChild(body);
      d.addEventListener('toggle', () => { if (d.open) paintBody(); });
      function paintBody(editing) {
        body.innerHTML = '';
        const tools = el('div', 'fbc-tools');
        if (canEdit) {
          tools.innerHTML = `<label>Plugs per tray <input type="number" min="1" value="${c.plugs_per_tray}" id="ppt-${c.id}"></label>
            <button class="fbc-btn small" data-act="edit">${editing ? 'Cancel' : 'Edit phases'}</button>
            ${editing ? '<button class="fbc-btn small primary" data-act="save">Save phases</button>' : ''}
            <button class="fbc-btn small" data-act="plan">Plan this crop</button>
            <button class="fbc-btn small" data-act="archive">Archive…</button>`;
          tools.querySelector(`#ppt-${c.id}`).onchange = async e => {
            const v = parseInt(e.target.value, 10); if (!(v > 0)) return;
            ok(await sb.from('crop').update({ plugs_per_tray: v }).eq('id', c.id)); c.plugs_per_tray = v; toast('Saved');
          };
          tools.querySelector('[data-act=edit]').onclick = () => paintBody(!editing);
          tools.querySelector('[data-act=plan]').onclick = () => openPlan(c.id);
          tools.querySelector('[data-act=archive]').onclick = async () => {
            const reason = prompt(`Archive "${c.name}"? It is hidden, not deleted. Reason (optional):`); if (reason === null) return;
            ok(await sb.rpc('archive_crop', { p_crop: c.id, p_reason: reason || null })); toast('Archived'); await load(); render();
          };
          if (editing) tools.querySelector('[data-act=save]').onclick = () => savePhases();
        }
        body.appendChild(tools);
        let day = 0;
        for (const ph of phases) {
          const row = el('div', 'fbc-phase');
          row.innerHTML = `<div><b>${ph.seq}. ${esc(ph.name)}</b><div class="fbc-mono">day ${day} · ${ph.days} d</div></div>`;
          const right = el('div'); row.appendChild(right); right.dataset.phase = ph.id;
          if (!editing) {
            for (const p of ph.procedures || []) {
              const pr = el('div', 'fbc-proc', `<a data-sop="${p.id}">${esc(p.title)}</a><span class="fbc-mono">+${p.day_offset}${p.repeat_days ? ' every ' + p.repeat_days + ' d' : ''} · ${p.base_minutes} + ${p.minutes_per_unit}/${unitWord(p.unit)}</span>`);
              pr.querySelector('a').onclick = () => openProcedure(p.id, p.title);
              right.appendChild(pr);
            }
            if (!(ph.procedures || []).length) right.appendChild(el('div', 'fbc-meta', 'No procedure on this phase.'));
          } else {
            (ph.procedures || []).forEach(p => right.appendChild(procEditRow(p)));
            const add = el('button', 'fbc-btn small', '+ procedure'); add.type = 'button';
            add.onclick = () => right.insertBefore(procEditRow({}), add); right.appendChild(add);
          }
          body.appendChild(row); day += ph.days;
        }
        if (!phases.length) body.appendChild(el('div', 'fbc-empty', 'No cycle yet for this crop.'));
      }
      function procEditRow(p) {
        const r = el('div', 'fbc-proc-edit');
        r.innerHTML = `<select name="sop_id">${state.procs.map(s => `<option value="${s.id}" ${s.id === p.id ? 'selected' : ''}>${esc(s.title)}</option>`).join('')}</select>
          <label>day <input type="number" name="day_offset" min="0" value="${p.day_offset ?? 0}"></label>
          <label>every <input type="number" name="repeat_days" min="1" placeholder="once" value="${p.repeat_days ?? ''}"> d</label>
          <button class="fbc-btn small" type="button" aria-label="Remove">×</button>`;
        r.querySelector('button').onclick = () => r.remove();
        return r;
      }
      async function savePhases() {
        for (const right of body.querySelectorAll('[data-phase]')) {
          const rows = [...right.querySelectorAll('.fbc-proc-edit')].map((r, i) => ({
            phase_id: right.dataset.phase, sop_id: r.querySelector('[name=sop_id]').value,
            day_offset: parseInt(r.querySelector('[name=day_offset]').value, 10) || 0,
            repeat_days: parseInt(r.querySelector('[name=repeat_days]').value, 10) || null, seq: i + 1 }));
          ok(await sb.from('crop_phase_sop').delete().eq('phase_id', right.dataset.phase));
          if (rows.length) ok(await sb.from('crop_phase_sop').insert(rows));
        }
        const plans = ok(await sb.from('crop_plan').select('id').eq('crop_id', c.id).in('status', ['planned', 'active']));
        for (const p of plans || []) ok(await sb.rpc('replan_crop', { p_plan: p.id }));
        toast(`Phases saved${plans?.length ? ` · ${plans.length} plan${plans.length > 1 ? 's' : ''} re-planned` : ''}`);
        await load(); render();
        const again = [...root.querySelectorAll('.fbc-row')].find(x => x.querySelector('b')?.textContent === c.name); if (again) again.open = true;
      }
      return d;
    }

    async function openProcedure(id, title) {
      if (opts.openProcedure) return opts.openProcedure(id);
      const m = modal(title || 'Procedure');
      const ver = ok(await sb.from('sop_version').select('id,version').eq('sop_id', id).not('approved_at', 'is', null).order('version', { ascending: false }).limit(1));
      const v = (ver || [])[0];
      if (!v) { m.body.innerHTML = '<div class="fbc-empty">No approved version yet.</div>'; return; }
      const steps = ok(await sb.from('sop_step').select('*').eq('version_id', v.id).order('seq'));
      m.body.innerHTML = `<div class="fbc-meta">Version ${v.version} · read-only</div>` + (steps || []).map(s => `
        <div class="fbc-step"><div class="sec">${esc(s.section || '')}</div><b>${s.seq}. ${esc(s.title)}</b> <span class="fbc-mono">${esc(s.step_type)}${s.step_type === 'measure' ? ` ${s.min_value ?? ''}–${s.max_value ?? ''} ${esc(s.value_unit || '')}` : ''}</span>
          ${s.instruction ? `<div class="d">${esc(s.instruction)}</div>` : ''}${s.expected_result ? `<div class="d"><b>Expected:</b> ${esc(s.expected_result)}</div>` : ''}${s.action_plan ? `<div class="d"><b>If not OK:</b> ${esc(s.action_plan)}</div>` : ''}</div>`).join('');
    }

    async function openArchive() {
      const m = modal('Archived crops');
      const rows = ok(await sb.from('crop').select('id,name,category,archived_at,archived_reason').not('archived_at', 'is', null).order('name'));
      if (!rows?.length) { m.body.innerHTML = '<div class="fbc-empty">Nothing archived.</div>'; return; }
      m.body.innerHTML = rows.map(c => `<div class="fbc-proc" style="justify-content:space-between;padding:6px 0;border-top:1px dashed var(--fbc-line,#d5d9d4)">
        <span><b>${esc(c.name)}</b> <span class="fbc-meta">${esc(catLabel(c.category))} · ${new Date(c.archived_at).toLocaleDateString()}${c.archived_reason ? ' · ' + esc(c.archived_reason) : ''}</span></span>
        ${canEdit ? `<button class="fbc-btn small" data-restore="${c.id}">Restore</button>` : ''}</div>`).join('');
      m.body.querySelectorAll('[data-restore]').forEach(b => b.onclick = async () => {
        ok(await sb.rpc('restore_crop', { p_crop: b.dataset.restore })); toast('Restored'); m.close(); await load(); render();
      });
    }

    async function openPlan(cropId) {
      const m = modal('Plan a crop');
      const farms = ok(await sb.from('farm').select('id,name').order('name'));
      const zones = ok(await sb.from('zone').select('id,farm_id,name').order('name'));
      const positions = ok(await sb.from('position').select('id,zone_id,code').order('code'));
      const today = new Date().toISOString().slice(0, 10);
      m.body.innerHTML = `
        <div class="fbc-field"><label for="fbc-p-crop">Crop</label><select id="fbc-p-crop">${state.crops.map(c => `<option value="${c.id}" ${c.id === cropId ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div>
        <div class="fbc-field"><label for="fbc-p-farm">Farm</label><select id="fbc-p-farm">${(farms || []).map(f => `<option value="${f.id}">${esc(f.name)}</option>`).join('')}</select></div>
        <div class="fbc-field"><label for="fbc-p-zone">Zone</label><select id="fbc-p-zone"></select></div>
        <div class="fbc-field"><label for="fbc-p-date">Start date</label><input type="date" id="fbc-p-date" value="${today}"></div>
        <div id="fbc-p-pos"></div>
        <div class="fbc-tools" style="margin-top:12px"><button class="fbc-btn primary" id="fbc-p-go">Create tasks</button><span class="fbc-meta" id="fbc-p-hint"></span></div>`;
      const $ = id => m.body.querySelector('#' + id);
      const paintZones = () => {
        const fz = (zones || []).filter(z => z.farm_id === $('fbc-p-farm').value);
        $('fbc-p-zone').innerHTML = fz.map(z => `<option value="${z.id}">${esc(z.name)}</option>`).join(''); paintPositions();
      };
      const paintPositions = () => {
        const ps = (positions || []).filter(p => p.zone_id === $('fbc-p-zone').value);
        $('fbc-p-pos').innerHTML = ps.length ? `<div class="fbc-meta">Positions · tick the ones planted, with the quantity</div>` + ps.map(p => `
          <div class="fbc-pos"><input type="checkbox" id="pp-${p.id}" data-pos="${p.id}" checked><label for="pp-${p.id}"><b>${esc(p.code)}</b></label>
            <input type="number" min="0.01" step="any" value="1" aria-label="Quantity ${esc(p.code)}"><select aria-label="Unit ${esc(p.code)}"><option value="tray">trays</option><option value="plant">plants</option></select></div>`).join('')
          : '<div class="fbc-empty">This zone has no positions yet.</div>';
      };
      $('fbc-p-farm').onchange = paintZones; $('fbc-p-zone').onchange = paintPositions; paintZones();
      $('fbc-p-go').onclick = async () => {
        const rows = [...m.body.querySelectorAll('.fbc-pos')].filter(r => r.querySelector('[data-pos]').checked).map(r => ({
          position_id: r.querySelector('[data-pos]').dataset.pos, quantity: parseFloat(r.querySelector('input[type=number]').value) || 0, unit: r.querySelector('select').value }))
          .filter(r => r.quantity > 0);
        $('fbc-p-go').disabled = true; $('fbc-p-hint').textContent = 'Planning…';
        try {
          const planId = ok(await sb.rpc('plan_crop', { p_farm: $('fbc-p-farm').value, p_crop: $('fbc-p-crop').value, p_zone: $('fbc-p-zone').value, p_start: $('fbc-p-date').value, p_positions: rows }));
          const r = await sb.from('task').select('id', { count: 'exact', head: true }).eq('plan_id', planId);
          const n = r.count != null ? r.count : '';
          toast(`Planned${n !== '' ? ` · ${n} tasks` : ''}`); m.close();
        } catch (e) { $('fbc-p-hint').textContent = e.message; $('fbc-p-go').disabled = false; }
      };
    }

    await load(); render();
    return { reload: async () => { await load(); render(); } };
  }

  global.FarmBoxCrops = { mount };
})(window);
