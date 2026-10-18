#!/usr/bin/env python3
"""Writes migrations/20261018120100_mcp_views.sql: the read-only views an outside AI sees.

Every view lives in schema mcp, is owned by postgres (so it reads the tables past RLS) and keeps
only the rows of the farms the current request may see in its families: mcp.farms(families) answers
from the request the MCP function opened for this person (see 20261018120000_mcp_access.sql).

The column lists come from gen/schema_snapshot.json, a copy of the live public schema
(names and types only, taken 18 Oct 2026). A column named here that is not in the snapshot stops
the generator, so a renamed column shows up here and not as a broken view on Supabase.

    python3 gen/views.py            # from docs/naked-heart-mcp
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SNAP = json.load(open(os.path.join(HERE, 'schema_snapshot.json')))
OUT = os.path.join(HERE, '..', 'migrations', '20261018120100_mcp_views.sql')

# The AI data families: a fixed list (mcp.data_family), clicked per role and per person on the team page.
FAMILIES = ['crops', 'harvest', 'tasks', 'water', 'climate', 'pests', 'equipment', 'purchasing', 'sales', 'costs', 'team']
ALL = FAMILIES

# Never shown, in any view: people's contact details and names outside the team area, keys,
# photos (the photo tool hands those out one at a time), and bookkeeping columns.
DROP_ALWAYS = {
    'photo_data', 'photo_path', 'image_path', 'photo_url', 'phone', 'email', 'contact_person',
    'contact_name', 'address', 'linkedin_url', 'key_last4', 'shop_key_last4', 'author',
    'author_name', 'removed_name', 'proposer_name', 'decider_name', 'verified_name',
    'discarded_name', 'created_by', 'updated_by', 'user_id', 'generation_key', 'content_hash',
    'notion_page_id', 'client_id', 'client_ref', 'client_run_id', 'client_out',
}
# Outside the team family a worker is not even an id.
DROP_UNLESS_TEAM = {'worker_id', 'operator_id', 'co_signer_id', 'done_by', 'held_by', 'held_user',
                    'assigned_to', 'raised_by', 'closed_by', 'observer_id', 'added_by',
                    'validated_by', 'approved_by', 'decided_by', 'note_by', 'ai_seen_by',
                    'edited_by', 'removed_by', 'verified_by', 'author'}

# name, table, families, filter, about, extra (dict: drop / keep / add)
#   filter: farm    -> farm_id in the request's farms
#           scoped  -> the farm's own rows plus the standard (farm_id null) rows of its organisation
#           catalog -> whole table (franchisor standard lists), shown to anyone with one of the families
#           via:<view>.<col>=<col> -> rows whose parent is in another mcp view
V = []
def v(name, table, areas, filt, about, **kw):
    V.append(dict(name=name, table=table, areas=areas, filt=filt, about=about, **kw))

# ── Reference: every family sees the farm's shape ────────────────────────────────
v('farms', 'farm', ALL, 'self', 'The FarmBox units this access covers: country, town, time zone, currency, working days, trap map.',
  drop={'attributes', 'model_id'})
v('zones', 'zone', ALL, 'farm', 'Growing zones of each farm.')
v('areas', 'area', ALL, 'farm', 'Areas inside a farm (sumps, tables, rooms…), with their zone and system.')
v('growing_systems', 'growing_system', ALL, 'farm', 'Growing systems (NFT, troughs, towers…) per zone: size, positions, irrigation cycle.')
v('growing_positions', 'growing_position', ALL, 'farm', 'Each growing position (a channel, a table spot) with its code, row and x/y/z place in metres.')
v('crops', 'crop', ALL, 'scoped', 'Crop library: the farm\'s own crops and the standard ones of its organisation.')
v('crop_phases', 'crop_phase', ALL, 'via:crops.id=crop_id', 'Phases of each crop with their days.')
v('crop_targets', 'crop_target', ['crops', 'water', 'climate'], 'scoped', 'Climate and nutrient targets per crop and phase (EC, pH, temperature, RH, DLI).')
v('steady_groups', 'steady_group', ['crops', 'harvest'], 'farm', 'Zones planned together for a steady harvest.', drop={'undo'})
v('farm_holidays', 'farm_holiday', ALL, 'farm', 'Days a farm is closed or works a public holiday.')
v('task_families', 'task_family', ALL, 'catalog', 'Families of work.')

# ── Crops, harvest, tasks, water, climate, equipment ────────────────────────────────────────────────────────────────────
MONEY_IN_SCORE = "'{price,revenue,revenue_per_day}'::text[]"
v('crop_plans', 'crop_plan', ['crops', 'harvest'], 'farm', 'Crop batches: position, crop, sow/transplant/harvest dates, phase, expected yield, lot code (money is in crop_plan_money).',
  drop={'expected_revenue', 'expected_cost', 'score_json'},
  add=[f"t.score_json - {MONEY_IN_SCORE} as score_json"])
v('crop_plan_money', 'crop_plan', ['costs'], 'farm', 'Expected money of each crop batch: revenue, cost, and the planner\'s price, revenue and revenue a day.',
  keep=['id', 'farm_id', 'crop_id', 'batch_code', 'lot_code', 'status', 'harvest_start', 'harvest_end', 'expected_yield',
        'expected_revenue', 'expected_cost'],
  add=["(t.score_json ->> 'price')::numeric as planned_price", "(t.score_json ->> 'revenue')::numeric as planned_revenue",
       "(t.score_json ->> 'revenue_per_day')::numeric as planned_revenue_per_day"])
v('harvests', 'harvest', ['harvest', 'sales', 'costs'], 'farm', 'Harvests: date, batch, quantity and unit, grade, waste and why, destination.')
v('tasks', 'task', ['tasks'], 'farm', 'Tasks: what, where, planned and done dates, estimated and actual minutes, status, skip reasons.',
  drop={'source_ref', 'group_key', 'labour_plan_id'})
v('task_items', 'task_item', ['tasks'], 'via:tasks.id=task_id', 'What each task covered (a batch, an area, an asset, a trap) and its result.')
v('sops', 'sop', ['tasks'], 'scoped', 'Standard operating procedures: title, family, frequency, minutes.',
  keep=['id', 'sop_code', 'slug', 'title', 'family', 'category', 'document_type', 'purpose', 'summary', 'frequency',
        'estimated_minutes', 'minutes_per_unit', 'unit', 'min_workers', 'status', 'current_version', 'effective_date',
        'review_date', 'scope', 'org_id', 'farm_id', 'target_kind'])
v('checklist_runs', 'checklist_run', ['tasks'], 'farm', 'Each time a procedure was run: status, outcome, steps done.', drop={'duplicate_of'})
v('step_results', 'step_result', ['tasks'], 'via:checklist_runs.id=run_id', 'Results of the procedure steps: values, out of range, notes.', drop={'geo'})
v('issues', 'issue', ['tasks', 'pests', 'equipment'], 'farm', 'Issues and pest cases: title, severity, where, status, outcome.')
v('nutrient_recipes', 'nutrient_recipe', ['water'], 'scoped', 'Nutrient recipes and their targets by phase.')
v('irrigation_cycles', 'irrigation_cycle', ['water'], 'farm', 'Irrigation cycles: pattern, on/off minutes, start times.')
v('irrigation_events', 'irrigation_event', ['water'], 'farm', 'Irrigation runs reported by devices: volume, EC, pH, drain.')
v('sump_readings', 'sump_reading', ['water'], 'farm', 'Sump readings: EC, pH, water temperature, when and where.')
v('readings', 'reading', ['climate', 'water'], 'farm', 'Sensor readings (metric, value, time).')
v('metrics', 'metric', ['climate', 'water'], 'catalog', 'What a sensor can measure, with the standard watch and alarm limits.')
v('metric_limits', 'metric_limit', ['climate', 'water'], 'farm', 'The farm\'s own limits per metric and zone.')
v('devices', 'device', ['climate', 'water', 'equipment'], 'farm', 'Controllers, sensors and cameras (no keys, no settings).', drop={'config', 'external_id'})
v('camera_counts', 'camera_count', ['climate', 'crops'], 'farm', 'What the cameras counted (object, count, confidence) and whether a person confirmed it.')
v('camera_growth', 'camera_growth', ['climate', 'crops'], 'farm', 'Growth seen by the cameras: stage, canopy %, height, kg estimate.')
v('assets', 'asset', ['equipment'], 'farm', 'Equipment and its meters.')
v('maintenance_rules', 'maintenance_rule', ['equipment'], 'farm', 'Maintenance rules per asset: how often, last done.')
v('phase_durations_learned', 'phase_duration_learned', ['crops'], 'farm', 'Phase lengths the platform learned from this farm\'s own batches.')

# ── Pests ────────────────────────────────────────────────────────────────
I = ['pests']
v('sticky_traps', 'sticky_trap', I, 'farm', 'Sticky traps: code, zone, row, metres along the row, colour, size.')
v('trap_readings', 'trap_reading', I, 'farm', 'Trap counts: per reading the total, the insects a day, the species, the AI count and notes. has_photo = the photo tool can show it.',
  drop={'algorithm', 'ai_auto_at', 'ai_auto_tries', 'code_source'}, photo=True)
v('ipm_thresholds', 'ipm_threshold', I, 'farm', 'Per farm: watch and over, in insects a day on one trap.')
v('pest_catalog', 'pest_catalog', I, 'catalog', 'Codes for pests, diseases, disorders and beneficials used in tags.')
v('scout_observations', 'scout_observation', I, 'farm', 'Scouting photos: zone, crop, plant part, tags, note, AI reading, measures. has_photo = the photo tool can show it.',
  drop={'ai_auto_at', 'ai_auto_tries', 'px_per_mm'}, photo=True)
v('case_points', 'case_point', I, 'farm', 'The evolution of a pest case: severity and counts over time.')
v('case_traps', 'case_trap', I, 'farm', 'Which traps a pest case follows.')
v('ipm_programs', 'ipm_program', I, 'farm', 'Treatment programmes on pest cases: product, rate, interval, applications.')
v('ipm_applications', 'ipm_application', I, 'farm', 'Each treatment application: day, product, quantity, status.')
v('ipm_products', 'ipm_product', I, 'catalog', 'IPM product catalogue: active ingredient, rates, PHI, REI, targets.', drop={'source_urls', 'label_url'})
v('ipm_templates', 'ipm_template', I, 'catalog', 'Treatment programme library: target, approach, steps.')
v('ipm_template_steps', 'ipm_template_step', I, 'catalog', 'Steps of each programme template.')
v('zone_opinions', 'zone_opinion', I, 'farm', 'The AI\'s opinion on a zone over its last 30 days (a proposal, decided by a person).')
v('greenhouse_opinions', 'greenhouse_opinion', I, 'farm', 'The AI\'s report on a whole unit for one scouting day.', drop={'critique'})
v('scout_notes', 'scout_note', I, 'farm', 'What people said or wrote about the whole greenhouse on a scouting day (text only).',
  keep=['id', 'farm_id', 'day', 'task_id', 'source', 'typed', 'transcript', 'language', 'body', 'created_at'],
  where='t.removed_at is null')
v('scout_note_digests', 'scout_note_digest', I, 'farm', 'One day\'s greenhouse notes rewritten by an AI as one text.')

# ── Purchasing, sales, costs ──────────────────────────────────────────────────────────────────────
P, S, C = ['purchasing'], ['sales'], ['costs']
v('items', 'item', ['purchasing', 'costs'], 'scoped', 'Items bought: unit, pack size, unit cost, reorder point.')
v('suppliers', 'supplier', P, 'scoped', 'Suppliers: name, region, lead days (no contact details).')
v('item_suppliers', 'item_supplier', P, 'via:items.id=item_id', 'Which supplier sells which item.')
v('purchase_requests', 'purchase_request', P, 'farm', 'What needs buying: item, quantity, need-by date, status, late.')
v('purchase_orders', 'purchase_order', P, 'farm', 'Purchase orders: supplier, status, expected delivery.')
v('sales_orders', 'sales_order', S, 'farm', 'Sales orders: customer, status.')
v('sales_order_lines', 'sales_order_line', S, 'farm', 'Order lines: crop, kg, delivery date, repeats.')
v('order_deliveries', 'order_delivery', S, 'farm', 'Deliveries: kg, price per kg, amount.')
v('customers', 'customer', S, 'farm', 'Customers: kind, channel, price factor, payment terms, credit limit (no contact details).', drop={'attributes', 'referred_by'})
v('cost_entries', 'cost_entry', C, 'farm', 'Costs: day, category, amount, supplier, batch or zone.')
v('stock_movements', 'stock_movement', P, 'farm', 'Stock in and out per item.')
v('item_stock_rules', 'item_stock_rule', P, 'farm', 'The farm\'s reorder rules per item.')
v('market_prices', 'market_price_week', ['sales', 'costs'], 'catalog', 'Wholesale market prices per region, species and week (rand per kg).')
v('market_species', 'market_species', ['sales', 'costs'], 'catalog', 'Species names used by the market prices.')
v('price_references', 'price_reference', S, 'catalog', 'Reference prices per crop (USD).')
v('price_seasons', 'price_season', S, 'catalog', 'Seasonal price factors per crop category.')
v('price_channels', 'price_channel', S, 'catalog', 'Sales channels and their price factors.')
v('price_countries', 'price_country', S, 'catalog', 'Country currency, exchange rate and price index.')
v('ai_usage', 'ai_usage', C, 'farm', 'What the platform\'s own AI cost: per call the model, tokens and USD.', drop={'ref_kind', 'ref_id'})

# ── Team (people) — never given unless asked for ───────────────────────────────
T = ['team']
v('workers', 'worker', T, 'farm', 'The team: name, role, employment, hourly cost, working days (no contact details; AI-only people are not listed).',
  drop={'attributes', 'notes'}, where="t.role <> 'ai_only'")
v('time_entries', 'time_entry', T, 'farm', 'Clock in and out per worker.')
v('task_times', 'task_time', T, 'farm', 'Minutes each worker spent on each task.')
v('task_workers', 'task_worker', T, 'via:tasks.id=task_id', 'Who was on each task.')
v('labour_plans', 'labour_plan', T, 'farm', 'Weekly labour plans: capacity and demand minutes.', drop={'snapshot'})
v('labour_slots', 'labour_slot', T, 'via:labour_plans.id=plan_id', 'Who works which days in a weekly plan.')
v('worker_absences', 'worker_absence', T, 'farm', 'Absences.', drop={'reason'})
v('worker_skills', 'worker_skill', T, 'via:workers.id=worker_id', 'Skills per worker.')
v('camera_presence', 'camera_presence', T, 'farm', 'Minutes of people per area and time slot seen by cameras (counts only, never who).')

# Hand-written views (aggregates), checked against the snapshot by the test run instead.
CUSTOM = [
    ('labour_minutes_daily', ['costs', 'tasks'],
     'Labour per day, task family and zone, without names: people, minutes and cost (minutes x hourly cost).',
     """select tt.farm_id, (tt.started_at at time zone coalesce(f.timezone, 'UTC'))::date as day,
       t.family, t.zone_id, t.sop_id,
       count(distinct tt.worker_id) as people,
       round(sum(extract(epoch from (tt.stopped_at - tt.started_at)) / 60)::numeric, 1) as minutes,
       round(sum(extract(epoch from (tt.stopped_at - tt.started_at)) / 3600 * coalesce(w.hourly_cost, 0))::numeric, 2) as cost
  from public.task_time tt
  join public.task t on t.id = tt.task_id
  join public.farm f on f.id = tt.farm_id
  left join public.worker w on w.id = tt.worker_id
 where tt.stopped_at is not null
   and tt.farm_id = any(mcp.farms('{costs,tasks}'))
 group by 1, 2, 3, 4, 5"""),
    ('clocked_hours_daily', ['costs'],
     'Hours clocked per farm and day, without names: people and hours.',
     """select te.farm_id, (te.clock_in at time zone coalesce(f.timezone, 'UTC'))::date as day,
       count(distinct te.worker_id) as people,
       round(sum(extract(epoch from (te.clock_out - te.clock_in)) / 3600)::numeric, 2) as hours
  from public.time_entry te
  join public.farm f on f.id = te.farm_id
 where te.clock_out is not null
   and te.farm_id = any(mcp.farms('{costs}'))
 group by 1, 2"""),
]


def cols_of(table):
    if table not in SNAP:
        sys.exit(f'table {table} is not in the snapshot')
    return [c for c, _ in SNAP[table]['cols']]


def row_filter(spec, area_list, a):
    """The where clause that keeps a row of spec's table (alias a) for the given areas.
    A via: child is filtered on its parent's table with the child's own areas, so a team-only
    view of task workers does not need the growing area that the tasks view asks for."""
    areas = '{' + ','.join(area_list) + '}'
    f = spec['filt']
    if f == 'self':
        return f"{a}.id = any(mcp.farms('{areas}'))"
    if f == 'farm':
        return f"{a}.farm_id = any(mcp.farms('{areas}'))"
    if f == 'scoped':
        return (f"({a}.farm_id = any(mcp.farms('{areas}'))"
                f" or ({a}.farm_id is null and ({a}.org_id is null or {a}.org_id = any(mcp.orgs('{areas}')))))")
    if f == 'catalog':
        return f"mcp.has_area('{areas}')"
    if f.startswith('via:'):
        parent_name, rest = f[4:].split('.', 1)
        pcol, col = rest.split('=')
        if col not in cols_of(spec['table']):
            sys.exit(f'{spec["name"]}: column {col} is not in {spec["table"]}')
        parent = next((s for s in V if s['name'] == parent_name), None) or sys.exit(f'no view {parent_name}')
        pa = a + 'p'
        return (f"{a}.{col} in (select {pa}.{pcol} from public.{parent['table']} {pa}"
                f" where {row_filter(parent, area_list, pa)})")
    sys.exit(f'unknown filter {f}')


def build(spec):
    table, cols = spec['table'], cols_of(spec['table'])
    team = 'team' in spec['areas']
    for c in list(spec.get('keep', [])) + list(spec.get('drop', [])):
        if c not in cols:
            sys.exit(f'{spec["name"]}: column {c} is not in {table}')
    if 'keep' in spec:
        chosen = [c for c in cols if c in spec['keep']]
    else:
        gone = DROP_ALWAYS | spec.get('drop', set()) | (set() if team else DROP_UNLESS_TEAM)
        chosen = [c for c in cols if c not in gone]
    sel = [f't.{c}' for c in chosen] + list(spec.get('add', []))
    if spec.get('photo'):
        sel.append('(t.photo_data is not null) as has_photo')
    where = row_filter(spec, spec['areas'], 't')
    if spec.get('where'):
        where += f" and {spec['where']}"
    body = ',\n       '.join(sel)
    return (f"create view mcp.{spec['name']} with (security_barrier) as\n"
            f"select {body}\n  from public.{table} t\n where {where};\n")


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    names = [s['name'] for s in V] + [c[0] for c in CUSTOM]
    assert len(names) == len(set(names)), 'duplicate view name'
    out = ['-- GENERATED by gen/views.py from gen/schema_snapshot.json — edit the generator, not this file.',
           '-- Naked Heart MCP, part 2 of 2: the views a person\'s AI may read (schema mcp, read through mcp_reader).',
           '-- Needs part 1 (20261018120000_mcp_access.sql). Safe to run again: it drops and recreates the views.',
           '', 'begin;', '',
           'do $$ declare r record; begin',
           "  for r in select table_name from information_schema.views where table_schema = 'mcp' loop",
           "    execute format('drop view if exists mcp.%I cascade', r.table_name);",
           '  end loop;',
           'end $$;',
           'truncate mcp.view_area;', '']
    for s in V:
        out.append(build(s))
    for name, areas, about, sql in CUSTOM:
        out.append(f'create view mcp.{name} with (security_barrier) as\n{sql};\n')
    out.append('insert into mcp.view_area (view_name, areas, about, sort) values')
    rows = []
    for i, s in enumerate(V):
        rows.append(f"  ({q(s['name'])}, '{{{','.join(s['areas'])}}}', {q(s['about'])}, {i + 1})")
    for j, (name, areas, about, _) in enumerate(CUSTOM):
        rows.append(f"  ({q(name)}, '{{{','.join(areas)}}}', {q(about)}, {len(V) + j + 1})")
    out.append(',\n'.join(rows) + ';')
    out += ['',
            "do $$ declare r record; begin",
            "  for r in select table_name from information_schema.views where table_schema = 'mcp' loop",
            "    execute format('alter view mcp.%I owner to postgres', r.table_name);",
            "    execute format('revoke all on mcp.%I from public, anon, authenticated', r.table_name);",
            "    execute format('grant select on mcp.%I to mcp_reader', r.table_name);",
            "  end loop;",
            "end $$;", '', 'commit;', '']
    open(OUT, 'w').write('\n'.join(out))
    print(f'{len(V) + len(CUSTOM)} views -> {os.path.relpath(OUT)}')


if __name__ == '__main__':
    main()
