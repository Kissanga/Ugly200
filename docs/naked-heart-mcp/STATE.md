# Naked Heart MCP — state

Lets a team member — staff, or an outside freelancer in the new **AI only** role — connect **their own
Claude or ChatGPT** to Naked Heart and have it **read** the farm data their job allows, to analyse it.
Read-only, per farm (with its sister units), per data family, until an end date or until the MCP tick
is taken off, and every question logged.

**Status (20 Oct 2026): live.** The Platform session brought it in (its own notes are in Platform);
on 20 Oct the Naked Heart connector answered `describe` for the owner's team row (farm admin, FarmBox1
and FarmLab, all 11 families). Built and tested here on 18 Oct.

**Team guide:** [Connect your AI to Naked Heart](https://claude.ai/code/artifact/1ddabdbb-cdbb-49f8-8de9-de2a22ecf89e)
(a Claude doc, private until shared from its Share menu): Claude and ChatGPT steps with links, phone,
first questions, limits, problems and fixes. It gives the address **`https://mcp.nkd.farm`**.

## The address: mcp.nkd.farm

`cloudflare/mcp-worker.js` is a Cloudflare Worker on `mcp.nkd.farm` that passes every call to the
Supabase function and answers the sign-in discovery itself (`/.well-known/oauth-protected-resource`
names `https://mcp.nkd.farm`; the 401's `WWW-Authenticate` is rewritten to point there; Supabase Auth's
metadata is also served at the root for older clients). It holds no secret. Nothing on Supabase changes,
so `https://azfiajzhzewjcblbltmp.supabase.co/functions/v1/mcp` keeps working for connectors already
added with it. Tested with fetch faked (`tests/worker.test.mjs`, 6 tests).

Set up (owner, Cloudflare dashboard):
1. [Workers & Pages](https://dash.cloudflare.com/?to=/:account/workers-and-pages) › **Create** › **Create Worker** (Start
   with Hello World), name `naked-heart-mcp` › **Deploy**.
2. **Edit code**, replace everything with `cloudflare/mcp-worker.js` (raw link by commit id), **Deploy**.
3. The Worker › **Settings** › **Domains & Routes** › **Add** › **Custom domain** › `mcp.nkd.farm` › **Add domain**.
4. Check: https://mcp.nkd.farm/.well-known/oauth-protected-resource shows `"resource":"https://mcp.nkd.farm"`.
5. In Claude: remove the Naked Heart connector, add it again with `https://mcp.nkd.farm`, sign in, Allow.

Done 20 Oct 2026: the Worker `naked-heart-mcp` is on `mcp.nkd.farm`, and step 4 shows `"resource":"https://mcp.nkd.farm"`
with Supabase Auth as the sign-in server.

## Managed on the team page

The same pattern as task responsibilities (`task_subfamily` list, `job_bundle` per job,
`worker_responsibility` / `team_exclusion` per person):

| What | Where | Like |
|---|---|---|
| a fixed list of 11 AI data families | `mcp.data_family` | `task_subfamily` |
| the families of each job: standard (`mcp.role_default`), or the farm's own click (`mcp.role_data`, kept on the home farm) | *What each job's AI may read* | `job_bundle` |
| per person: a family added beyond the job, or a job family taken away | `mcp.person_data`, `mcp.person_data_off` | `worker_responsibility`, `team_exclusion` |
| per person: the **MCP** tick and an end date | `mcp.person` | — |
| role **ai_only**: in the team only for their AI | `worker.role` | — |

A job change flows to everybody of that job at once; a person's own additions and removals stay.
Access ends when the end date passes, the tick is taken off, the person is no longer active in the
team, or they are left with no family. Taking it off signs their AI out (Supabase sessions of OAuth
clients are deleted) unless another team row of theirs still gives access.

**AI only** (`ai_only`): forced by a trigger to `off_tasks`, no working days, 0 hours, casual, whatever
the team page sends; no Naked Heart login (no membership); not listed in the `team` family's data.
They sign in on the consent page with the email on their team row (magic link or password), so a
freelancer needs no account set up by the farm. Someone without an email or login cannot be ticked.

### The families and the standard per job

| Family | Gives | Admin, manager | Assistant, agronomist | Technician | Office | Worker, trainee | AI only |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| Crops & batches | batches (without money), phases, targets, steady groups, learned phase lengths | ✓ | ✓ | | | ✓ | |
| Harvests | quantity, grade, waste, destination | ✓ | ✓ | | ✓ | | |
| Tasks & procedures | tasks, what they covered, procedures and step results, issues | ✓ | ✓ | ✓ | | ✓ | |
| Nutrients & irrigation | recipes, cycles and runs, sump EC / pH / temperature | ✓ | ✓ | ✓ | | | |
| Climate & sensors | readings and limits, devices (no keys), camera counts and growth | ✓ | ✓ | ✓ | | | |
| Pests & disease | traps and counts, scouting photos, cases, treatments, IPM library, AI opinions | ✓ | ✓ | | | | |
| Equipment | assets, meters, maintenance | ✓ | | ✓ | | | |
| Purchasing & stock | items, suppliers (no contacts), requests and orders, stock | ✓ | | | ✓ | | |
| Sales & customers | orders, deliveries, customers (no contacts), market and reference prices | ✓ | | | ✓ | | |
| Costs | costs, expected revenue and cost of each batch (`crop_plan_money`), the platform's AI cost, labour minutes and cost per day without names | ✓ | | | ✓ | | |
| Team (personal data) | names, roles, hourly cost, clock-ins, minutes per person, plans, absences, skills | ✓ | | | | | |

Every family also gets the farm's shape: farm, zones, areas, systems, positions (x/y in metres), the
crop library and phases, holidays. Never in any view: phone, email, address, contact names, keys,
`user_id`/`created_by`, photos (only one at a time through **photo**), and outside `team` no worker id
at all. Tested: a test fails if a view gains such a column, or a view belongs to a family not in the list.

## How a request is served

```
Claude / ChatGPT ──OAuth 2.1 (Supabase Auth's own OAuth server)──► person signs in, consent page, Allow
        │  token (role mcp_reader, set by the token hook)
        ▼
Edge Function mcp  (https://azfiajzhzewjcblbltmp.supabase.co/functions/v1/mcp)
  1. Supabase Auth checks the token
  2. postgres connection: mcp.begin_request(user) → nobody ticked = nothing;
     else a request row: the farms (with sister units) per family, valid 2 min, random id
  3. reader connection, LOGGED IN AS mcp_reader: read-only transaction, mcp.request = id,
     runs the AI's one SELECT over the mcp views → rows; always rolled back and closed
  4. postgres connection: mcp.call_log row (who, which AI, the SQL, rows, ok)
```

Tools the AI gets: **describe** (its farms, families, end date, and every table with its columns),
**query** (one PostgreSQL SELECT over the views, ≤ 1000 rows), **photo** (one scouting / trap /
camera photo as an image, so the AI can look at it).

## Files (`docs/naked-heart-mcp/`)

| File | What |
|---|---|
| `migrations/20261018120000_mcp_access.sql` | schema `mcp`, login role `mcp_reader`, role `ai_only` and its trigger, the families, job and person tables, requests, call log, token hook, and the team page's functions `mcp_team`, `mcp_set_role`, `mcp_reset_role`, `mcp_person_family`, `mcp_set_access`, `mcp_stop_all`, `mcp_call_log`, `mcp_my_access` |
| `migrations/20261018120100_mcp_views.sql` | GENERATED: the 79 views the AI reads. Edit `gen/views.py`, then `python3 gen/views.py` |
| `gen/views.py`, `gen/schema_snapshot.json` | the views per family, checked against the live columns (snapshot 18 Oct 2026) |
| `functions/mcp/` | the Edge Function: `index.ts` (Deno entry), `handler.ts` (MCP over HTTP), `db.ts` (the two connections) |
| `pages/team-ai.html` | the AI part of the team page, standalone until moved into it: job chips, people with MCP tick, end date and chips, Stop all, the address to send, what was asked |
| `pages/oauth-consent.html` | the consent page Supabase sends people to (Allow / Deny, shows their farms and families) |
| `tests/run_local.sh` | 75 database tests + 24 function tests on a local Postgres 16 stub: `PGHOST=… PGPORT=… PGUSER=postgres tests/run_local.sh` |

## Go live (in order)

Work in a session that has the Platform repo — paste `PLATFORM-SESSION-PROMPT.md` — then the owner does the
dashboard steps.

1. **Platform repo**: copy `migrations/*` to `Platform/supabase/migrations/` (give them timestamps after
   the newest there), `functions/mcp/` to `Platform/supabase/functions/mcp/`, and add to
   `supabase/config.toml`: `[functions.mcp]` `verify_jwt = false`. Run `tests/run_local.sh` there.
2. **Keep AI-only people out of work lists** (Platform functions and console) — see the next section.
   Do this in the same release as the migration: before it, nobody can be `ai_only`.
3. **Database**: apply the two migrations the way Platform does — never `supabase db push`:
   `supabase db query --linked -f …` per file, then `supabase migration repair --status applied …`.
4. **Reader password** — SQL editor, with a long random password that is kept only in step 5:
   `alter role mcp_reader with password '…';`
5. **Secret** — Edge Functions › Secrets: `MCP_READER_DB_URL` = the *Session pooler* string from
   Connect, with user `mcp_reader.azfiajzhzewjcblbltmp` and that password.
6. **Deploy**: `supabase functions deploy mcp --no-verify-jwt`.
7. **Auth › OAuth Server**: enable; dynamic client registration ON (Claude and ChatGPT register
   themselves); Authorization Path `/oauth/consent`. Check Auth › URL Configuration › Site URL is
   Naked Heart's address (`https://heart.nkd.farm`).
8. **Console** (`Platform/console`): `oauth-consent.html` served at `/oauth/consent`; the AI part of
   `team-ai.html` into the team page (or served as `/team-ai.html` first); fill `SUPABASE_KEY` (the
   publishable key the console already uses). Deploy the console (`deploy-console.ps1`).
9. **Token hook** — Auth › Hooks › Customize access token › Postgres › `public.mcp_token_hook`.
   Then sign in to Naked Heart and Naked Brain normally: they must work as before.
10. **Other Edge Functions**: any that checks the caller and then acts with the service key must
    refuse AI tokens. Add at the top, after reading the bearer token:
    ```ts
    const p = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    if (p.client_id || p.role === 'mcp_reader') return new Response('Not for AI connections', { status: 403 });
    ```
    At least `admin-user`; check all 17 (`assistant`, `photo-chat`, `scout-photo`, … ).
11. **Test with your own team row**: tick MCP for yourself with one family and an end date in a week;
    Claude › Settings › Connectors › Add custom connector › the address; sign in, Allow; ask "describe
    what you can see", then a question; check *What was asked*; untick; the next question must be refused.

**Until steps 9 and 10 are done, tick only AI-only people** (no write rights in Naked Heart): by
Supabase's default an OAuth token carries the person's normal rights at the REST API. The MCP function
itself is read-only either way.

## AI-only people in the rest of Naked Heart (Platform, step 2)

The trigger already makes them `off_tasks` with no hours, so planning, rostering and task ownership
(which check `off_tasks`: `owner_of`, `owner_for_task`, `responsible_for`, `rotation_pick`, `roster`,
`plan_slot`, `sync_since_unit`) leave them out. But **off_tasks people can still pick up a task on the
phone**, and some lists do not look at `off_tasks`. Add `role <> 'ai_only'` where people are offered for
work or counted as staff — on 18 Oct the functions reading `worker` without an `off_tasks` check were:
`people`, `assign_task`, `auto_assign`, `change_people`, `scouting_people`, `labour_hours`,
`labour_week`, `task_times`, `team_problems`, `team_names`, `person_history`, `worker_photos`,
`set_worker_cost`, `batch_cost`, `money`, `reports`, and the phone's people list (`sync_since_unit`
sends `off_tasks` people). On the team page: no task-subfamily chips, working days or hours for an
AI-only row, and no "create login" (their AI signs in by email). Also allow `ai_only` where the team
page lists jobs (`team_setup`, `job_rank` puts unknown roles last, which is right).

## Checks only the live system can answer

- Supabase accepting `role: mcp_reader` from the hook (its docs list only anon/authenticated). If
  OAuth sign-in then fails, remove the `jsonb_set(… role …)` and keep the access check; the MCP path
  stays read-only (it never uses the token's role), and step 10 still covers the other functions.
- `/auth/v1/user` accepting a token whose role is `mcp_reader` (the function's token check).
- Claude and ChatGPT finding the OAuth server from the `WWW-Authenticate` header on the
  `supabase.co/functions/v1/mcp` address. If one does not, put `mcp.nkd.farm` (Cloudflare) in front and
  serve `/.well-known/oauth-protected-resource` at its root; set `MCP_PUBLIC_URL`.
- The ChatGPT menu names for adding a custom MCP connector change often; the page says "developer mode".

## Decisions

- **On the team page, same pattern as task responsibilities** (owner, 18 Oct): fixed lists, clicked
  per job and per person, so hybrid jobs need no new code. Families are finer than the first 4 areas.
- **AI only is a role of its own** (owner, 18 Oct), not a tick on another role.
- **The tick is explicit for everyone**, admins included: no tick, no data, whatever the job allows.
- **Who may change it**: `app.may_manage_people`, the team page's own rule (farm admin, farm manager,
  franchisee and franchisor admins).
- **Supabase Auth's OAuth 2.1 server** (beta, free in beta) instead of an own login.
- **The AI's SQL runs on its own login role** (`mcp_reader`), never on the postgres connection: from a
  postgres connection one `select set_config('role','postgres',…)` inside a query would undo any
  `set role`. As `mcp_reader` there is nothing to switch to.
- **The request's scope is a random id with a 2-minute life**, read by `mcp.farms()`, not the user id:
  a query can change settings, but it cannot guess another request's id.
- **One SELECT, read-only, rolled back, connection closed**: nothing a query sets survives it.
- **Standard libraries are shared** (crops, IPM products and templates, market prices) with anyone
  ticked. If the crop library must stay private from outsiders, make `crops` and `crop_phases`
  family-only in `gen/views.py`.
- **Batch money is in Costs only** (owner, 18 Oct): `crop_plans` has no expected revenue or cost, and
  its planner score loses `price`, `revenue` and `revenue_per_day`; those are in `crop_plan_money`.
- **No franchise job titles** (owner, 18 Oct): a franchisor or franchisee admin who wants AI access is
  put in a farm's team with a normal job (e.g. Farm admin) and ticked like anyone. Managing the AI
  access is still open to them through `app.may_manage_people`.
- Limits: 60 calls a minute per person, 15 s per query, 1000 rows, 150 kB of text per answer.

## Learned the hard way (in this session)

- porsager `postgres`: passing `JSON.stringify(x)` to a `::jsonb` parameter stores a JSON *string*;
  use `sql.json(x)`.
- The worker restart kills a local Postgres in the scratchpad; keep it in `/var/tmp/pgmcp`.
- Members of a farm get memberships on its sister units by a trigger (`membership_sisters`); the test
  stub has no triggers, so the tests add that membership by hand.

## Open

- **Accounting is mostly empty**: `cost_entry`, `sales_order`, `purchase_order` have 0 rows (18 Oct);
  only purchase requests (22), harvests (15), task times and market prices hold data. Where are the
  books (Xero, Sage, Excel)? Either Naked Heart records them, or they are imported into `cost_entry`.
- Full-size photos (Storage `evidence` bucket) are not served, only the 640 px copy in the table.
- The pages are tested with a stand-in for Supabase here (clicks, layout at 1100 and 390 px), not
  against the live one.
