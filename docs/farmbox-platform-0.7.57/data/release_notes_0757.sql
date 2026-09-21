-- 0.7.57 release note (console "What's new"). ASSUMED columns: version, released_on, title, body.
insert into release_note (version, released_on, title, body)
select '0.7.57', date '2026-09-22', 'Crop library, grouped tasks, procedures on phases',
$$• Crop database rebuilt: 50 crops in six families (Fruiting vines, Fruiting bush, Leafy, Mixed leafy, Herbs, Microgreens), each with a full cycle and a procedure on every phase. Crops outside the list are archived — see the new Archive button; nothing was deleted.
• Vines → Fruiting vines, Fruiting → Fruiting bush.
• Planning a crop now creates ONE task per crop × zone × date. Positions sit under the task with their own quantity and minutes; minutes = base + per-unit × quantity, in trays (plugs per tray on the crop), positions, plants or m².
• Procedures attach to crop phases with a day offset (and a repeat interval); the Crop database shows the procedure title per phase, the editor picks it from the approved list.
• Naked Brain 0.11.5: grouped task cards with positions and minutes; checklist steps with a Details tap.$$
where not exists (select 1 from release_note where version = '0.7.57');
