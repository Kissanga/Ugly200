#!/usr/bin/env node
// Generates data/crop_library_0757.sql — the approved 50-crop library with a
// full cycle per crop and a procedure on every phase (owner, 21 Sept 2026).
// Idempotent: procedures are matched by title (existing ones keep their
// content and timings), crops by name or alias (updated, never duplicated),
// crops outside the list are ARCHIVED, never deleted.
//   node gen/crop_library.js > data/crop_library_0757.sql
'use strict';

// ── procedures ───────────────────────────────────────────────────────────────
// unit: tray | position | plant | m2 · minutes = base + per_unit × quantity
const step = (section, title, instruction, expected_result, action_plan, extra = {}) =>
  ({ section, title, instruction, expected_result, action_plan, step_type: 'check', ...extra });
const doStep = (section, title, instruction, expected, plan, extra = {}) => step(section, title, instruction, expected, plan, { step_type: 'do', ...extra });
const measure = (section, title, instruction, unit, min, max, plan) =>
  step(section, title, instruction, `${min}–${max} ${unit}`, plan, { step_type: 'measure', value_unit: unit, min_value: min, max_value: max });
const record = (section, title, instruction, expected) => step(section, title, instruction, expected, null, { step_type: 'record' });

const SOPS = [
  { title: 'Sow seeds in plug trays', sub: 'Sowing & nursery', unit: 'tray', base: 5, per: 4, tools: 'Plug trays, sowing medium, labels, seed', ppe: 'Gloves',
    summary: 'Fill, sow, label and water in the plug trays for one batch.',
    steps: [
      doStep('Prepare', 'Fill trays with moist medium', 'Fill each plug level, tap the tray to settle, do not compact.', 'Plugs level and evenly moist', 'Re-wet the medium before filling if it runs dry.'),
      doStep('Sow', 'Sow one seed per plug at the right depth', 'Depth 2× the seed size. Pelleted seed: leave uncovered.', 'One seed in every plug', 'Empty plugs: sow again before covering.'),
      doStep('Sow', 'Label each tray', 'Crop, variety, sowing date and batch code on a stake label.', 'Every tray labelled', null),
      doStep('Water', 'Water in with a fine rose', 'Until water drips from the base. Do not wash seed out.', 'Trays draining', null),
      record('Record', 'Number of trays sown', 'Count the trays taken to the germination area.', 'trays'),
    ] },
  { title: 'Sow microgreen trays', sub: 'Sowing & nursery', unit: 'tray', base: 5, per: 3, tools: 'Shallow trays, medium, scale, seed', ppe: 'Gloves',
    summary: 'Dense sowing of one batch of microgreen trays, then blackout.',
    steps: [
      doStep('Prepare', 'Fill and level the trays', '2 cm of medium, pressed flat and watered until moist.', 'Flat, moist surface', null),
      doStep('Sow', 'Weigh and spread the seed', 'Use the seed weight on the crop card. Spread evenly, no clumps.', 'Even cover, seeds touching but not stacked', 'Clumps: spread with a dry hand before misting.'),
      doStep('Sow', 'Mist and stack under blackout', 'Mist the surface, stack trays with a weight or a blackout lid.', 'Trays dark and moist', null),
      record('Record', 'Number of trays sown', null, 'trays'),
    ] },
  { title: 'Germination check', sub: 'Sowing & nursery', unit: 'tray', base: 2, per: 0.5, tools: 'Thermometer', ppe: null,
    summary: 'Daily look at germinating trays: moisture, temperature, first emergence.',
    steps: [
      measure('Check', 'Air temperature in the germination area', 'Read the thermometer at tray height.', '°C', 18, 26, 'Out of range: adjust the heater or vent and tell the grower.'),
      step('Check', 'Medium is moist, not wet', 'Press a plug: it should feel damp, no free water.', 'Damp plugs', 'Dry: mist. Waterlogged: stop watering, improve drainage.'),
      step('Check', 'No mould or damping-off', 'Look for grey fuzz or collapsed seedlings.', 'Clean trays', 'Remove affected plugs, increase air movement, tell the grower.', { evidence: 'photo_if_nok' }),
      record('Record', 'Emergence (% of plugs)', 'Estimate on 3 trays.', '%'),
    ] },
  { title: 'Uncover microgreens (end of blackout)', sub: 'Sowing & nursery', unit: 'tray', base: 2, per: 0.5, tools: null, ppe: null,
    summary: 'Take the trays out of blackout and under light.',
    steps: [
      step('Check', 'Seedlings 2–4 cm and pale yellow', 'The tray is ready when the stems have lifted the lid.', 'Even stand, 2–4 cm', 'Uneven: give one more day of blackout.'),
      doStep('Do', 'Move trays under light, bottom-water', 'Space trays, water from below so the leaves stay dry.', 'Trays under light, medium moist', null),
    ] },
  { title: 'Nursery watering and check', sub: 'Sowing & nursery', unit: 'tray', base: 3, per: 0.5, tools: 'EC/pH meter', ppe: null,
    summary: 'Water and check the seedlings in the nursery.',
    steps: [
      measure('Check', 'Feed EC', 'Test the feed in the nursery tank.', 'mS/cm', 0.8, 1.6, 'Out of range: correct the tank before watering.'),
      measure('Check', 'Feed pH', null, 'pH', 5.5, 6.5, 'Out of range: correct the tank before watering.'),
      doStep('Do', 'Water the trays', 'Bottom-water until the plugs darken; drain the excess.', 'Plugs moist, no standing water', null),
      step('Check', 'Seedlings green, upright and even', 'Look for stretching, yellowing or pests.', 'Healthy, even trays', 'Stretched: more light. Yellow: check feed. Pests: scout the nursery.', { evidence: 'photo_if_nok' }),
    ] },
  { title: 'Harden off seedlings', sub: 'Sowing & nursery', unit: 'tray', base: 2, per: 0.5, tools: null, ppe: null,
    summary: 'Prepare the seedlings for the growing zone in the last days of the nursery.',
    steps: [
      doStep('Do', 'Lower the nursery temperature and reduce watering', 'Follow the crop card. Keep the plugs moist, not wet.', 'Sturdy, compact seedlings', null),
      step('Check', 'Seedlings ready to transplant', 'Roots hold the plug together; 2–4 true leaves.', 'Plug lifts out whole', 'Not ready: wait 2 days and check again.'),
    ] },
  { title: 'Thin seedlings', sub: 'Sowing & nursery', unit: 'tray', base: 2, per: 1, tools: 'Scissors', ppe: null,
    summary: 'One seedling per plug.',
    steps: [
      doStep('Do', 'Cut extra seedlings at the base', 'Keep the strongest; cut, do not pull.', 'One seedling per plug', null),
      doStep('Do', 'Fill gaps from spare trays', 'Move plugs from the spare tray into empty cells.', 'No empty plugs', null),
    ] },
  { title: 'Transplant seedlings to growing position', sub: 'Transplanting', unit: 'plant', base: 5, per: 0.25, tools: 'Trolley, labels', ppe: 'Gloves',
    summary: 'Move the plugs from the nursery into the growing position.',
    steps: [
      step('Prepare', 'Position clean and irrigation running', 'Channels or slabs wet, emitters dripping.', 'Ready to plant', 'Not running: fix before planting.'),
      doStep('Do', 'Set one plug per site', 'Roots down, top of the plug level with the cup or slab surface.', 'All sites planted', 'Damaged plugs: discard, take from the spare tray.'),
      doStep('Do', 'Label the position', 'Crop, variety, transplant date, batch code.', 'Label on the position', null),
      record('Record', 'Plants transplanted', 'Count the plants set in this position.', 'plants'),
    ] },
  { title: 'Plant strawberry plugs or bare roots', sub: 'Transplanting', unit: 'plant', base: 5, per: 0.4, tools: 'Bucket of water, trolley', ppe: 'Gloves',
    summary: 'Plant strawberries with the crown at the surface.',
    steps: [
      doStep('Prepare', 'Soak bare roots 30 min', 'Roots in water, crowns dry.', 'Roots hydrated', null),
      doStep('Do', 'Plant with the crown level with the surface', 'Crown buried rots; crown too high dries.', 'Crown at the surface, roots spread down', null),
      doStep('Do', 'Water in and label', null, 'Moist root zone, position labelled', null),
      record('Record', 'Plants set', null, 'plants'),
    ] },
  { title: 'Nutrient solution check (EC, pH, temperature)', sub: 'Irrigation & nutrition', unit: 'position', base: 5, per: 3, tools: 'EC/pH meter, thermometer', ppe: 'Gloves',
    summary: 'Measure the feed and the drain of the position and correct the tank.',
    steps: [
      measure('Feed', 'Feed EC', 'Sample at the emitter or channel inlet.', 'mS/cm', 1.2, 3.0, 'Out of the crop target: correct the tank and tell the grower.'),
      measure('Feed', 'Feed pH', null, 'pH', 5.5, 6.5, 'Out of range: correct with acid/base per the tank card.'),
      measure('Feed', 'Solution temperature', null, '°C', 16, 26, 'Above 26 °C: check the chiller; below 16: check the heater.'),
      measure('Drain', 'Drain EC', 'Sample the drain or channel outlet.', 'mS/cm', 1.2, 4.0, 'Drain EC > feed + 1: increase the irrigation volume.'),
      step('Tank', 'Tank level and pump running', null, 'Level above the mark, pump on', 'Top up with fresh water; pump off: restart and report.'),
    ] },
  { title: 'Scout for pests and disease', sub: 'Scouting & IPM', unit: 'position', base: 3, per: 4, tools: 'Hand lens, sticky traps', ppe: null, validation: 'checklist_evidence',
    summary: 'Weekly walk of the position: leaves, stems, traps.',
    steps: [
      step('Look', 'Undersides of leaves, 10 plants', 'Aphids, whitefly, thrips, mites, eggs.', 'No pests found', 'Pests: photograph, count, tell the grower the same day.', { evidence: 'photo_if_nok' }),
      step('Look', 'Sticky traps', 'Count the catch and replace full traps.', 'Catch stable or falling', 'Rising catch: report.'),
      step('Look', 'Leaf spots, mildew, rot', 'Old leaves, fruit, stem base.', 'No disease', 'Remove affected leaves in a bag; report.', { evidence: 'photo_if_nok' }),
      record('Record', 'Overall plant health (1–5)', null, '1–5'),
    ] },
  { title: 'Plant walk and growth record', sub: 'Crop care', unit: 'position', base: 3, per: 3, tools: 'Tape measure', ppe: null,
    summary: 'Weekly growth record on the position.',
    steps: [
      record('Record', 'Plant height / head size', 'Measure 3 plants, note the average.', 'cm'),
      step('Look', 'Growth even across the position', null, 'Even stand', 'Uneven: check emitters and drainage at the weak end.'),
      record('Record', 'Days to expected harvest', 'From the crop card and the plant stage.', 'days'),
    ] },
  { title: 'Prune and train vines', sub: 'Crop care', unit: 'plant', base: 5, per: 0.6, tools: 'Clips, twine, pruning knife', ppe: 'Gloves',
    summary: 'Weekly clip the head to the string and remove side shoots.',
    steps: [
      doStep('Do', 'Clip the head to the string', 'One clip under a leaf, string not twisted round the head.', 'Head supported', null),
      doStep('Do', 'Remove side shoots', 'Break out shoots under 5 cm at the leaf axils.', 'Single stem', 'Shoots over 10 cm: cut clean with the knife.'),
      doStep('Do', 'Remove yellow or diseased leaves', 'Bag and remove from the zone.', 'Clean canopy', null),
    ] },
  { title: 'Lower and lean (high-wire)', sub: 'Crop care', unit: 'plant', base: 5, per: 0.5, tools: 'Hooks', ppe: 'Gloves',
    summary: 'Drop the hooks and lean the vines along the row.',
    steps: [
      doStep('Do', 'Release string and lower the plant 20–30 cm', 'Keep the head above the wire.', 'Heads at working height', null),
      doStep('Do', 'Lay the stem on the support', 'No stem kinks; fruit off the floor.', 'Stems supported', 'Kinked stem: tie a support under the kink.'),
    ] },
  { title: 'Remove suckers and lower leaves', sub: 'Crop care', unit: 'plant', base: 3, per: 0.3, tools: 'Pruning knife', ppe: 'Gloves',
    summary: 'Keep the canopy open under the lowest truss.',
    steps: [
      doStep('Do', 'Remove leaves below the ripening truss', 'Up to 3 leaves per plant per week.', 'Air reaches the fruit', null),
      doStep('Do', 'Remove suckers at the base', null, 'Clean stem base', null),
    ] },
  { title: 'Pollination check', sub: 'Crop care', unit: 'position', base: 3, per: 2, tools: null, ppe: null,
    summary: 'Flowers set fruit: bees or vibration.',
    steps: [
      step('Check', 'Open flowers show bee marks or set fruit', 'Brown marks on the anther cone, small fruit behind old flowers.', 'Fruit setting', 'No set: vibrate the trusses 2 s each at midday; report.'),
      doStep('Do', 'Vibrate trusses if no pollinators', 'Only on dry flowers, late morning.', 'Trusses shaken', null),
    ] },
  { title: 'Stake and tie bush crops', sub: 'Crop care', unit: 'plant', base: 5, per: 0.4, tools: 'Stakes, twine, clips', ppe: 'Gloves',
    summary: 'Support plants that carry fruit.',
    steps: [
      doStep('Do', 'Tie the main stems to the stake or string', 'Loose loop, not cutting into the stem.', 'Plants upright', null),
      doStep('Do', 'Remove broken or ground-touching branches', null, 'Fruit off the floor', null),
    ] },
  { title: 'Pinch herbs to bush out', sub: 'Crop care', unit: 'plant', base: 2, per: 0.1, tools: 'Scissors', ppe: null,
    summary: 'Pinch the growing tips so the plant branches.',
    steps: [
      doStep('Do', 'Pinch above the 2nd–3rd node', 'Remove the tip with a clean cut.', 'Plants branching', null),
      doStep('Do', 'Remove flower buds', 'Buds turn leaves bitter.', 'No flowers', null),
    ] },
  { title: 'Runner removal (strawberry)', sub: 'Crop care', unit: 'plant', base: 3, per: 0.2, tools: 'Scissors', ppe: 'Gloves',
    summary: 'Cut runners so the energy goes to the fruit.',
    steps: [
      doStep('Do', 'Cut runners at the crown', 'Bag the cuttings.', 'No runners', null),
      doStep('Do', 'Remove old and diseased leaves', null, 'Open crown', null),
    ] },
  { title: 'Root zone and irrigation check', sub: 'Irrigation & nutrition', unit: 'position', base: 3, per: 2, tools: null, ppe: null,
    summary: 'Emitters, flow and roots on the position.',
    steps: [
      step('Check', 'Every emitter or channel flowing', 'Walk the row during an irrigation cycle.', 'All flowing', 'Blocked: clean or replace; report.'),
      step('Check', 'Roots white and healthy', 'Lift a plug or cup.', 'White roots', 'Brown, slimy roots: report the same day.', { evidence: 'photo_if_nok' }),
      step('Check', 'Drain fraction 20–35 %', 'From the drain tray or channel.', 'Drain in range', 'Low: add an irrigation cycle. High: remove one.'),
    ] },
  { title: 'Fruit thinning', sub: 'Crop care', unit: 'plant', base: 3, per: 0.3, tools: 'Scissors', ppe: 'Gloves',
    summary: 'Fewer, bigger fruit.',
    steps: [
      doStep('Do', 'Remove misshapen and surplus fruit', 'Leave the number per truss on the crop card.', 'Even fruit load', null),
    ] },
  { title: 'Harvest leafy heads', sub: 'Harvest', unit: 'plant', base: 5, per: 0.3, tools: 'Knife, crates, scale', ppe: 'Gloves, hairnet',
    summary: 'Cut heads at size, pack and weigh.',
    steps: [
      step('Check', 'Heads at the target size', 'Compare with the crop card.', 'Ready', 'Under size: leave 2–3 days.'),
      doStep('Do', 'Cut at the base, remove outer damaged leaves', 'Cut clean, keep the head dry.', 'Clean heads in crates', null),
      record('Record', 'Heads harvested', null, 'heads'),
      record('Record', 'Weight harvested', 'Weigh the crates net.', 'kg'),
    ] },
  { title: 'Cut-and-come-again harvest', sub: 'Harvest', unit: 'm2', base: 5, per: 6, tools: 'Knife or harvester, crates, scale', ppe: 'Gloves, hairnet',
    summary: 'Cut leaves above the growing point and let the crop regrow.',
    steps: [
      doStep('Do', 'Cut 2–3 cm above the crown', 'Do not cut into the growing point.', 'Crown intact, leaves in crates', null),
      doStep('Do', 'Remove yellow leaves from the cut', null, 'Clean product', null),
      record('Record', 'Weight harvested', null, 'kg'),
    ] },
  { title: 'Harvest herbs', sub: 'Harvest', unit: 'plant', base: 5, per: 0.2, tools: 'Scissors, crates', ppe: 'Gloves, hairnet',
    summary: 'Cut stems, leave a third of the plant.',
    steps: [
      doStep('Do', 'Cut stems above a node, leave one third', 'Cut in the morning when the leaves are dry.', 'Plants can regrow', null),
      doStep('Do', 'Bunch and crate', null, 'Bunches in crates', null),
      record('Record', 'Weight or bunches harvested', null, 'kg or bunches'),
    ] },
  { title: 'Harvest fruit', sub: 'Harvest', unit: 'plant', base: 5, per: 0.5, tools: 'Crates, scissors, scale', ppe: 'Gloves',
    summary: 'Pick ripe fruit and grade it.',
    steps: [
      doStep('Do', 'Pick fruit at the colour stage on the crop card', 'Twist or cut, keep the calyx.', 'Ripe fruit picked', null),
      doStep('Do', 'Grade: first, second, waste', null, 'Crates by grade', null),
      record('Record', 'Weight harvested (first grade)', null, 'kg'),
      record('Record', 'Weight second grade and waste', null, 'kg'),
    ] },
  { title: 'Harvest strawberries', sub: 'Harvest', unit: 'plant', base: 5, per: 0.3, tools: 'Punnets, crates', ppe: 'Gloves',
    summary: 'Pick fully red fruit into punnets.',
    steps: [
      doStep('Do', 'Pick fully red fruit with the calyx', 'Pinch the stem, do not pull the fruit.', 'Ripe fruit in punnets', null),
      doStep('Do', 'Remove rotten fruit into a bag', null, 'No rot left on plants', null),
      record('Record', 'Weight harvested', null, 'kg'),
    ] },
  { title: 'Harvest microgreen trays', sub: 'Harvest', unit: 'tray', base: 5, per: 4, tools: 'Knife, containers, scale', ppe: 'Gloves, hairnet',
    summary: 'Cut the trays above the medium and pack.',
    steps: [
      step('Check', 'Cotyledons open, first true leaf showing', null, 'Ready', 'Not yet: leave one day.'),
      doStep('Do', 'Cut just above the medium, no medium in the cut', 'Dry leaves only; do not wash.', 'Clean product', null),
      record('Record', 'Weight harvested', null, 'g'),
    ] },
  { title: 'Weigh and record yield', sub: 'Harvest', unit: 'position', base: 3, per: 1, tools: 'Scale', ppe: null,
    summary: 'The week\'s yield for the position.',
    steps: [
      record('Record', 'Total weight this week', 'Sum of the harvest records.', 'kg'),
      record('Record', 'Waste this week', null, 'kg'),
    ] },
  { title: 'Pack and cold-store harvest', sub: 'Harvest', unit: 'position', base: 5, per: 2, tools: 'Crates, labels', ppe: 'Gloves, hairnet',
    summary: 'Into the cold room within the hour.',
    steps: [
      doStep('Do', 'Label crates: crop, date, position', null, 'Crates labelled', null),
      measure('Check', 'Cold room temperature', null, '°C', 2, 8, 'Out of range: report before storing.'),
      doStep('Do', 'Store, oldest at the front', null, 'Stock rotated', null),
    ] },
  { title: 'Crop end: remove plants and clean the position', sub: 'Cleaning & sanitation', unit: 'position', base: 10, per: 15, tools: 'Bags, brushes, sanitiser', ppe: 'Gloves, goggles',
    summary: 'Clear the crop and sanitise the position for the next one.',
    steps: [
      doStep('Do', 'Remove all plants and roots', 'Bag and take out of the zone.', 'Position empty', null),
      doStep('Do', 'Wash channels, cups, slabs or buckets', null, 'No organic matter left', null),
      doStep('Do', 'Sanitise and rinse', 'Per the sanitiser card; rinse before replanting.', 'Position sanitised', null),
      step('Check', 'Emitters and pump flushed', null, 'Clean water at every emitter', 'Blocked: replace.'),
    ] },
  { title: 'Clean and sanitise trays', sub: 'Cleaning & sanitation', unit: 'tray', base: 5, per: 1, tools: 'Brush, sanitiser', ppe: 'Gloves, goggles',
    summary: 'Trays ready for the next sowing.',
    steps: [
      doStep('Do', 'Knock out the medium, brush, wash', null, 'No residue', null),
      doStep('Do', 'Soak in sanitiser, rinse, dry', 'Per the sanitiser card.', 'Trays dry and stacked', null),
    ] },
];

// ── phase templates ──────────────────────────────────────────────────────────
// p(title, day_offset, repeat_days)
const p = (title, day_offset = 0, repeat_days = null) => ({ title, day_offset, repeat_days });
const care = (extra = []) => [
  p('Nutrient solution check (EC, pH, temperature)', 0, 3),
  p('Scout for pests and disease', 2, 7),
  p('Plant walk and growth record', 1, 7),
  p('Root zone and irrigation check', 3, 7),
  ...extra,
];
const nursery = days => ({ name: 'Nursery', days, procedures: [p('Nursery watering and check', 0, 2), p('Thin seedlings', 3), p('Harden off seedlings', Math.max(days - 3, 1))] });
const sowing = { name: 'Sowing', days: 1, procedures: [p('Sow seeds in plug trays')] };
const germination = days => ({ name: 'Germination', days, procedures: [p('Germination check', 1, 2)] });
const transplant = { name: 'Transplant', days: 1, procedures: [p('Transplant seedlings to growing position')] };
const cropEnd = { name: 'Crop end', days: 2, procedures: [p('Crop end: remove plants and clean the position'), p('Clean and sanitise trays', 1)] };

const vine = ({ nurseryDays = 21, vegDays = 28, flowerDays = 21, harvestDays = 120, harvestEvery = 3, lean = true }) => [
  sowing, germination(7), nursery(nurseryDays), transplant,
  { name: 'Vegetative', days: vegDays, procedures: care([p('Prune and train vines', 7, 7)]) },
  { name: 'Flowering and fruit set', days: flowerDays, procedures: care([p('Pollination check', 0, 3), p('Prune and train vines', 0, 7), ...(lean ? [p('Lower and lean (high-wire)', 4, 7)] : []), p('Remove suckers and lower leaves', 2, 7)]) },
  { name: 'Harvest', days: harvestDays, procedures: care([p('Harvest fruit', 0, harvestEvery), p('Prune and train vines', 1, 7), ...(lean ? [p('Lower and lean (high-wire)', 4, 7)] : []), p('Remove suckers and lower leaves', 2, 7), p('Weigh and record yield', 6, 7), p('Pack and cold-store harvest', 0, harvestEvery)]) },
  cropEnd,
];
const bush = ({ nurseryDays = 28, vegDays = 28, flowerDays = 21, harvestDays = 90, harvestEvery = 3, thin = false }) => [
  sowing, germination(8), nursery(nurseryDays), transplant,
  { name: 'Vegetative', days: vegDays, procedures: care([p('Stake and tie bush crops', 7, 7)]) },
  { name: 'Flowering and fruit set', days: flowerDays, procedures: care([p('Pollination check', 0, 3), p('Stake and tie bush crops', 3, 7), ...(thin ? [p('Fruit thinning', 10, 7)] : [])]) },
  { name: 'Harvest', days: harvestDays, procedures: care([p('Harvest fruit', 0, harvestEvery), p('Stake and tie bush crops', 3, 7), p('Weigh and record yield', 6, 7), p('Pack and cold-store harvest', 0, harvestEvery)]) },
  cropEnd,
];
const strawberry = ({ harvestDays = 120 }) => [
  { name: 'Planting', days: 1, procedures: [p('Plant strawberry plugs or bare roots')] },
  { name: 'Establishment', days: 21, procedures: care([p('Runner removal (strawberry)', 7, 7)]) },
  { name: 'Flowering', days: 21, procedures: care([p('Pollination check', 0, 3), p('Runner removal (strawberry)', 3, 7)]) },
  { name: 'Harvest', days: harvestDays, procedures: care([p('Harvest strawberries', 0, 2), p('Runner removal (strawberry)', 3, 7), p('Weigh and record yield', 6, 7), p('Pack and cold-store harvest', 0, 2)]) },
  { name: 'Crop end', days: 2, procedures: [p('Crop end: remove plants and clean the position')] },
];
const leafyHead = ({ germDays = 4, nurseryDays = 14, vegDays = 28, harvestDays = 5 }) => [
  sowing, germination(germDays), nursery(nurseryDays), transplant,
  { name: 'Vegetative', days: vegDays, procedures: care() },
  { name: 'Harvest', days: harvestDays, procedures: [p('Harvest leafy heads', 0, 2), p('Weigh and record yield', harvestDays - 1), p('Pack and cold-store harvest', 0, 2)] },
  cropEnd,
];
const leafyCut = ({ germDays = 4, nurseryDays = 10, vegDays = 21, harvestDays = 28, cutEvery = 7 }) => [
  sowing, germination(germDays), nursery(nurseryDays), transplant,
  { name: 'Vegetative', days: vegDays, procedures: care() },
  { name: 'Harvest (multi-cut)', days: harvestDays, procedures: care([p('Cut-and-come-again harvest', 0, cutEvery), p('Weigh and record yield', 6, 7), p('Pack and cold-store harvest', 0, cutEvery)]) },
  cropEnd,
];
const herb = ({ germDays = 7, nurseryDays = 21, vegDays = 21, harvestDays = 56, cutEvery = 7, pinch = true }) => [
  sowing, germination(germDays), nursery(nurseryDays), transplant,
  { name: 'Vegetative', days: vegDays, procedures: care(pinch ? [p('Pinch herbs to bush out', 7, 7)] : []) },
  { name: 'Harvest (multi-cut)', days: harvestDays, procedures: care([p('Harvest herbs', 0, cutEvery), ...(pinch ? [p('Pinch herbs to bush out', 3, 14)] : []), p('Weigh and record yield', 6, 7), p('Pack and cold-store harvest', 0, cutEvery)]) },
  cropEnd,
];
const micro = ({ blackoutDays = 3, growDays = 6 }) => [
  { name: 'Sowing', days: 1, procedures: [p('Sow microgreen trays')] },
  { name: 'Blackout', days: blackoutDays, procedures: [p('Germination check', 1, 1)] },
  { name: 'Growing', days: growDays, procedures: [p('Uncover microgreens (end of blackout)', 0), p('Nursery watering and check', 1, 1)] },
  { name: 'Harvest', days: 1, procedures: [p('Harvest microgreen trays'), p('Pack and cold-store harvest')] },
  { name: 'Clean', days: 1, procedures: [p('Clean and sanitise trays')] },
];

// ── the 50 crops ─────────────────────────────────────────────────────────────
const C = (name, category, medium, system, plugs, phases, aliases = []) => ({ name, category, medium, system, plugs_per_tray: plugs, phases, aliases });
const CROPS = [
  // Fruiting vines (5)
  C('Tomato cherry indeterminate', 'fruiting_vines', 'Slab', 'Drip-irrigated substrate', 40, vine({ harvestDays: 150, harvestEvery: 3 }), ['cherry tomato', 'tomato cherry', 'tomato (cherry)']),
  C('Tomato round indeterminate', 'fruiting_vines', 'Slab', 'Drip-irrigated substrate', 40, vine({ harvestDays: 150, harvestEvery: 3 }), ['tomato', 'tomato round', 'beef tomato', 'tomato indeterminate']),
  C('Cucumber mini', 'fruiting_vines', 'Slab', 'Drip-irrigated substrate', 40, vine({ nurseryDays: 14, vegDays: 21, flowerDays: 10, harvestDays: 60, harvestEvery: 2 }), ['mini cucumber', 'cucumber (mini)']),
  C('Cucumber English', 'fruiting_vines', 'Slab', 'Drip-irrigated substrate', 40, vine({ nurseryDays: 14, vegDays: 21, flowerDays: 10, harvestDays: 60, harvestEvery: 2 }), ['cucumber', 'english cucumber', 'long cucumber']),
  C('Climbing green bean', 'fruiting_vines', 'Bucket', 'Drip-irrigated substrate', 72, vine({ nurseryDays: 10, vegDays: 21, flowerDays: 14, harvestDays: 45, harvestEvery: 3, lean: false }), ['pole bean', 'climbing bean', 'green bean (climbing)']),
  // Fruiting bush (9)
  C('Tomato determinate', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, bush({ nurseryDays: 21, vegDays: 28, flowerDays: 21, harvestDays: 60, harvestEvery: 3 }), ['bush tomato', 'tomato (determinate)']),
  C('Bell pepper red', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, bush({ nurseryDays: 35, vegDays: 28, flowerDays: 28, harvestDays: 120, harvestEvery: 7, thin: true }), ['red pepper', 'bell pepper', 'pepper red', 'sweet pepper red']),
  C('Bell pepper yellow', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, bush({ nurseryDays: 35, vegDays: 28, flowerDays: 28, harvestDays: 120, harvestEvery: 7, thin: true }), ['yellow pepper', 'pepper yellow', 'sweet pepper yellow']),
  C('Chilli', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, bush({ nurseryDays: 35, vegDays: 28, flowerDays: 21, harvestDays: 120, harvestEvery: 7 }), ['chili', 'chilli pepper', 'hot pepper', 'chile']),
  C('Eggplant', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, bush({ nurseryDays: 35, vegDays: 28, flowerDays: 21, harvestDays: 120, harvestEvery: 4, thin: true }), ['aubergine', 'eggplants']),
  C('Courgette', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, bush({ nurseryDays: 14, vegDays: 21, flowerDays: 10, harvestDays: 60, harvestEvery: 2 }), ['zucchini', 'summer squash']),
  C('Bush green bean', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 72, bush({ nurseryDays: 10, vegDays: 21, flowerDays: 10, harvestDays: 30, harvestEvery: 3 }), ['bush bean', 'dwarf bean', 'green bean', 'green beans']),
  C('Strawberry Albion', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, strawberry({ harvestDays: 150 }), ['strawberry', 'strawberries', 'albion']),
  C('Strawberry Chandler', 'fruiting_bush', 'Bucket', 'Drip-irrigated substrate', 40, strawberry({ harvestDays: 90 }), ['chandler']),
  // Leafy (11)
  C('Butterhead lettuce', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 28 }), ['butterhead', 'lettuce butterhead', 'boston lettuce']),
  C('Iceberg lettuce', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 42, harvestDays: 7 }), ['iceberg', 'crisphead']),
  C('Romaine lettuce', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 35 }), ['romaine', 'cos lettuce', 'cos']),
  C('Leaf lettuce', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 28 }), ['lettuce', 'lollo', 'oak leaf', 'oakleaf', 'loose leaf lettuce']),
  C('Frisée', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 42, harvestDays: 7 }), ['frisee', 'curly endive']),
  C('Escarole', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 42, harvestDays: 7 }), ['broad-leaved endive', 'scarole']),
  C('Radicchio', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 49, harvestDays: 7 }), ['chicory red', 'red chicory']),
  C('Baby spinach', 'leafy', 'Net cup', 'NFT', 128, leafyCut({ germDays: 5, nurseryDays: 10, vegDays: 14, harvestDays: 21, cutEvery: 7 }), ['spinach']),
  C('Pak choi', 'leafy', 'Net cup', 'NFT', 128, leafyHead({ vegDays: 28 }), ['bok choy', 'pak choy', 'bok choi']),
  C('Kale', 'leafy', 'Net cup', 'NFT', 128, leafyCut({ nurseryDays: 14, vegDays: 28, harvestDays: 56, cutEvery: 7 }), ['curly kale', 'cavolo nero']),
  C('Swiss chard', 'leafy', 'Net cup', 'NFT', 128, leafyCut({ nurseryDays: 14, vegDays: 28, harvestDays: 56, cutEvery: 7 }), ['chard', 'rainbow chard']),
  // Mixed leafy (5)
  C('Rocket', 'mixed_leafy', 'Net cup', 'NFT', 128, leafyCut({ germDays: 3, nurseryDays: 10, vegDays: 14, harvestDays: 28, cutEvery: 7 }), ['arugula', 'rucola']),
  C('Mizuna', 'mixed_leafy', 'Net cup', 'NFT', 128, leafyCut({ germDays: 3, nurseryDays: 10, vegDays: 14, harvestDays: 28, cutEvery: 7 })),
  C('Mâche', 'mixed_leafy', 'Net cup', 'NFT', 128, leafyCut({ germDays: 7, nurseryDays: 14, vegDays: 21, harvestDays: 14, cutEvery: 7 }), ['mache', 'lamb\'s lettuce', 'corn salad']),
  C('Watercress', 'mixed_leafy', 'Net cup', 'NFT', 128, leafyCut({ germDays: 5, nurseryDays: 14, vegDays: 21, harvestDays: 42, cutEvery: 7 })),
  C('Tatsoi', 'mixed_leafy', 'Net cup', 'NFT', 128, leafyCut({ germDays: 3, nurseryDays: 10, vegDays: 14, harvestDays: 28, cutEvery: 7 })),
  // Herbs (10)
  C('Basil', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 5, nurseryDays: 21, vegDays: 21, harvestDays: 56 }), ['sweet basil', 'genovese basil']),
  C('Coriander', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 7, nurseryDays: 14, vegDays: 14, harvestDays: 28, pinch: false }), ['cilantro']),
  C('Flat parsley', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 14, nurseryDays: 21, vegDays: 21, harvestDays: 84, pinch: false }), ['parsley', 'italian parsley', 'flat-leaf parsley']),
  C('Curly parsley', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 14, nurseryDays: 21, vegDays: 21, harvestDays: 84, pinch: false }), ['parsley curly']),
  C('Dill', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 7, nurseryDays: 14, vegDays: 14, harvestDays: 28, pinch: false })),
  C('Mint', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 10, nurseryDays: 21, vegDays: 21, harvestDays: 84 }), ['spearmint', 'peppermint']),
  C('Chives', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 10, nurseryDays: 28, vegDays: 28, harvestDays: 84, pinch: false })),
  C('Thyme', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 14, nurseryDays: 28, vegDays: 28, harvestDays: 84, cutEvery: 14 })),
  C('Oregano', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 10, nurseryDays: 28, vegDays: 28, harvestDays: 84, cutEvery: 14 })),
  C('Sage', 'herbs', 'Net cup', 'NFT', 128, herb({ germDays: 14, nurseryDays: 28, vegDays: 28, harvestDays: 84, cutEvery: 14 })),
  // Microgreens (10)
  C('Pea microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 4, growDays: 7 }), ['pea shoots', 'microgreens pea', 'pea']),
  C('Sunflower microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 4, growDays: 6 }), ['sunflower shoots', 'microgreens sunflower', 'sunflower']),
  C('Radish microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 3, growDays: 5 }), ['microgreens radish', 'radish']),
  C('Broccoli microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 3, growDays: 6 }), ['microgreens broccoli', 'broccoli']),
  C('Mustard microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 3, growDays: 5 }), ['microgreens mustard', 'mustard']),
  C('Kale microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 3, growDays: 7 }), ['microgreens kale']),
  C('Basil microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 4, growDays: 12 }), ['microgreens basil']),
  C('Coriander microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 5, growDays: 12 }), ['microgreens coriander', 'cilantro microgreens']),
  C('Beetroot microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 5, growDays: 10 }), ['microgreens beetroot', 'beet microgreens', 'beetroot']),
  C('Amaranth microgreens', 'microgreens', 'Trays', 'Ebb & flow', 1, micro({ blackoutDays: 4, growDays: 10 }), ['microgreens amaranth', 'amaranth']),
];

// ── checks ───────────────────────────────────────────────────────────────────
const sopTitles = new Set(SOPS.map(s => s.title));
if (CROPS.length !== 50) throw new Error('expected 50 crops, got ' + CROPS.length);
for (const c of CROPS) for (const ph of c.phases) {
  if (!ph.procedures.length) throw new Error(`${c.name} / ${ph.name}: phase without a procedure`);
  for (const pr of ph.procedures) if (!sopTitles.has(pr.title)) throw new Error(`${c.name}: unknown procedure ${pr.title}`);
}
const names = new Set(); for (const c of CROPS) { const k = c.name.toLowerCase(); if (names.has(k)) throw new Error('duplicate crop ' + c.name); names.add(k); }

// ── SQL ──────────────────────────────────────────────────────────────────────
const lit = v => v == null ? 'null' : `$j$${JSON.stringify(v)}$j$::jsonb`;
const out = [];
out.push(`-- ─────────────────────────────────────────────────────────────────────────────
-- 0.7.57 · crop library — ${CROPS.length} crops, ${SOPS.length} procedures. GENERATED by gen/crop_library.js; edit that, not this.
--
-- Idempotent. Procedures match by title (case-insensitive): an existing one
-- keeps its content and any timing already set; a missing one is created
-- approved, managed in the console, with version 1 and its checklist steps.
-- Crops match by name or alias: updated in place (renamed to the library name),
-- never duplicated. The crop's default cycle is rebuilt from the library
-- (phases referenced by done tasks are kept). Crops not in the library are
-- archived, never deleted.
--
-- Apply after the two 0.7.57 migrations:
--   supabase db query --linked -f data/crop_library_0757.sql
-- ─────────────────────────────────────────────────────────────────────────────
begin;

create or replace function pg_temp.lib_sop(p jsonb) returns uuid language plpgsql as $$
declare v_id uuid; v_ver uuid; s jsonb; i int := 0;
begin
  select id into v_id from sop where lower(title) = lower(p->>'title') order by created_at limit 1;
  if v_id is null then
    insert into sop (title, summary, family, sub_family, trigger_kind, managed_in, status, validation,
                     base_minutes, minutes_per_unit, unit, safety_ppe, tools)
    values (p->>'title', p->>'summary', 'agriculture', p->>'sub_family', 'crop_plan', 'console', 'approved',
            coalesce(p->>'validation', 'checklist'), (p->>'base_minutes')::numeric, (p->>'minutes_per_unit')::numeric,
            p->>'unit', p->>'safety_ppe', p->>'tools')
    returning id into v_id;
  else
    -- timings only where nobody has set them yet
    update sop set base_minutes = (p->>'base_minutes')::numeric, minutes_per_unit = (p->>'minutes_per_unit')::numeric,
                   unit = p->>'unit'
    where id = v_id and coalesce(base_minutes, 0) = 0 and coalesce(minutes_per_unit, 0) = 0;
    update sop set sub_family = p->>'sub_family' where id = v_id and sub_family is null;
    update sop set status = 'approved' where id = v_id and status = 'draft' and not exists (select 1 from sop_version where sop_id = v_id);
  end if;
  if not exists (select 1 from sop_version where sop_id = v_id) then
    insert into sop_version (sop_id, version, approved_at) values (v_id, 1, now()) returning id into v_ver;
    for s in select * from jsonb_array_elements(p->'steps') loop
      i := i + 1;
      insert into sop_step (version_id, seq, section, title, instruction, expected_result, action_plan, step_type,
                            evidence, value_unit, min_value, max_value, target_source)
      values (v_ver, i, s->>'section', s->>'title', s->>'instruction', s->>'expected_result', s->>'action_plan',
              coalesce(s->>'step_type', 'check'), s->>'evidence', s->>'value_unit',
              (s->>'min_value')::numeric, (s->>'max_value')::numeric, 'fixed');
    end loop;
  end if;
  return v_id;
end $$;

create or replace function pg_temp.lib_crop(p jsonb) returns uuid language plpgsql as $$
declare v_id uuid; v_cycle uuid; v_phase uuid; ph jsonb; pr jsonb; n int := 0; m int; v_sop uuid;
begin
  select id into v_id from crop
  where lower(name) = lower(p->>'name')
     or lower(name) in (select lower(a) from jsonb_array_elements_text(coalesce(p->'aliases', '[]'::jsonb)) a)
  order by (lower(name) = lower(p->>'name')) desc, archived_at nulls first, created_at limit 1;
  if v_id is null then
    insert into crop (name, category, medium, system, plugs_per_tray)
    values (p->>'name', p->>'category', p->>'medium', p->>'system', (p->>'plugs_per_tray')::int)
    returning id into v_id;
  else
    update crop set name = p->>'name', category = p->>'category',
                    medium = coalesce(medium, p->>'medium'), system = coalesce(system, p->>'system'),
                    plugs_per_tray = case when plugs_per_tray = 72 then (p->>'plugs_per_tray')::int else plugs_per_tray end,
                    archived_at = null, archived_reason = null, updated_at = now()
    where id = v_id;
  end if;

  select id into v_cycle from crop_cycle where crop_id = v_id order by is_default desc nulls last, id limit 1;
  if v_cycle is null then
    insert into crop_cycle (crop_id, name, is_default) values (v_id, 'Standard', true) returning id into v_cycle;
  end if;
  delete from crop_phase_sop where phase_id in (select id from crop_phase where cycle_id = v_cycle);
  -- phases not in the library go, unless a task still points at them
  delete from crop_phase cp where cp.cycle_id = v_cycle
    and lower(cp.name) not in (select lower(x->>'name') from jsonb_array_elements(p->'phases') x)
    and not exists (select 1 from task t where t.phase_id = cp.id);
  update crop_phase set seq = seq + 1000 where cycle_id = v_cycle;   -- clear the way for renumbering

  for ph in select * from jsonb_array_elements(p->'phases') loop
    n := n + 1;
    select id into v_phase from crop_phase where cycle_id = v_cycle and lower(name) = lower(ph->>'name') order by seq limit 1;
    if v_phase is null then
      insert into crop_phase (cycle_id, seq, name, days) values (v_cycle, n, ph->>'name', (ph->>'days')::int) returning id into v_phase;
    else
      update crop_phase set seq = n, name = ph->>'name', days = (ph->>'days')::int where id = v_phase;
    end if;
    m := 0;
    for pr in select * from jsonb_array_elements(ph->'procedures') loop
      m := m + 1;
      select id into v_sop from sop where lower(title) = lower(pr->>'title') order by created_at limit 1;
      if v_sop is null then raise exception 'procedure "%" missing for crop %', pr->>'title', p->>'name'; end if;
      insert into crop_phase_sop (phase_id, sop_id, day_offset, repeat_days, seq)
      values (v_phase, v_sop, coalesce((pr->>'day_offset')::int, 0), (pr->>'repeat_days')::int, m)
      on conflict (phase_id, sop_id, day_offset) do nothing;
    end loop;
  end loop;
  -- a kept phase the library no longer names (tasks point at it) sits after the others, unlinked
  delete from crop_phase cp where cp.cycle_id = v_cycle and cp.seq > 1000
    and not exists (select 1 from task t where t.phase_id = cp.id);
  return v_id;
end $$;

-- ── procedures ───────────────────────────────────────────────────────────────`);
for (const s of SOPS) {
  const j = { title: s.title, summary: s.summary, sub_family: s.sub, validation: s.validation || 'checklist',
              base_minutes: s.base, minutes_per_unit: s.per, unit: s.unit, safety_ppe: s.ppe, tools: s.tools, steps: s.steps };
  out.push(`select pg_temp.lib_sop(${lit(j)});`);
}
out.push(`\n-- ── crops ────────────────────────────────────────────────────────────────────`);
for (const c of CROPS) out.push(`select pg_temp.lib_crop(${lit(c)});`);
out.push(`
-- ── archive everything else (never delete) ───────────────────────────────────
update crop set archived_at = now(), archived_reason = 'Not in the 0.7.57 crop library', updated_at = now()
where archived_at is null
  and lower(name) not in (${CROPS.map(c => `'${c.name.toLowerCase().replace(/'/g, "''")}'`).join(', ')});

-- ── summary ──────────────────────────────────────────────────────────────────
select (select count(*) from crop where archived_at is null) as active_crops,
       (select count(*) from crop where archived_at is not null) as archived_crops,
       (select count(*) from sop where trigger_kind = 'crop_plan') as crop_plan_procedures,
       (select count(*) from crop_phase ph join crop_cycle cy on cy.id = ph.cycle_id join crop c on c.id = cy.crop_id
         where c.archived_at is null and not exists (select 1 from crop_phase_sop where phase_id = ph.id)) as phases_without_procedure;
commit;
`);
process.stdout.write(out.join('\n'));
