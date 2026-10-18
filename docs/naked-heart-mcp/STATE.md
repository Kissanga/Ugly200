# Naked Heart MCP — state

Lets a person — internal staff or an outside freelancer — connect **their own Claude or ChatGPT** to
Naked Heart and have it **read** the farm data their access covers, to analyse it. Read-only, per farm,
per area, with an end date or until a manager stops it, and every question logged.

**Status (18 Oct 2026): built and tested here, not deployed.** Nothing was changed on the live
database: the session only read its schema. Goes into the private Platform repo (`supabase/` and
`console/`) to go live — see *Go live* below.

## How it works

```
Claude / ChatGPT ──OAuth 2.1 (Supabase Auth's own OAuth server)──► person signs in, consent page, Allow
        │  token (role mcp_reader, set by the token hook)
        ▼
Edge Function mcp  (https://azfiajzhzewjcblbltmp.supabase.co/functions/v1/mcp)
  1. Supabase Auth checks the token
  2. postgres connection: mcp.begin_request(user) → no access in force = nothing;
     else a request row: the farms per area, valid 2 min, random id
  3. reader connection, LOGGED IN AS mcp_reader: read-only transaction, mcp.request = id,
     runs the AI's one SELECT over the mcp views → rows; always rolled back and closed
  4. postgres connection: mcp.call_log row (who, which AI, the SQL, rows, ok)
```

Tools the AI gets: **describe** (its farms, areas, end date, and every table with its columns),
**query** (one PostgreSQL SELECT over the views, ≤ 1000 rows), **photo** (one scouting / trap /
camera photo as an image, so the AI can look at it).

## Files (`docs/naked-heart-mcp/`)

| File | What |
|---|---|
| `migrations/20261018120000_mcp_access.sql` | schema `mcp`, login role `mcp_reader`, `mcp.access` (who, farm, areas, until, stopped), `mcp.request`, `mcp.call_log`, the token hook, and the managers' functions `mcp_access_give / _stop / _stop_all / _list`, `mcp_call_log`, `mcp_my_access` |
| `migrations/20261018120100_mcp_views.sql` | GENERATED: the 78 views the AI reads. Edit `gen/views.py`, then `python3 gen/views.py` |
| `gen/views.py`, `gen/schema_snapshot.json` | the view list per area, checked against the live columns (snapshot 18 Oct 2026) |
| `functions/mcp/` | the Edge Function: `index.ts` (Deno entry), `handler.ts` (MCP over HTTP), `db.ts` (the two connections) |
| `pages/oauth-consent.html` | the consent page Supabase sends people to (Allow / Deny, shows what they may read) |
| `pages/ai-access.html` | managers: give access (email, areas, until), who has it, Stop, Stop all, what was asked |
| `tests/run_local.sh` | 50 database tests + 24 function tests on a local Postgres 16 stub: `PGHOST=… PGPORT=… PGUSER=postgres tests/run_local.sh` |

## Data areas

| Area | Gives |
|---|---|
| `growing` | crop batches, harvests, tasks and their results, procedures and step values, nutrient recipes, irrigation, sump and sensor readings, devices (no keys), camera counts and growth, assets, maintenance, labour minutes and cost **per day without names** |
| `ipm` | traps and readings (rates, species, AI counts), scouting photos (tags, AI readings), pest cases, programmes, applications, product and template library, the AI zone and greenhouse opinions, greenhouse notes (text only) |
| `money` | items, suppliers (no contacts), purchase requests and orders, sales orders and lines, deliveries, customers (no contacts), costs, stock, market and reference prices, the platform's own AI cost, crop batches and harvests, labour totals |
| `team` | worker names, roles, hourly cost, clock-ins, minutes per worker per task, labour plans, absences (no reason), skills, camera presence counts. Personal data: the page asks before giving it |

Every area also gets the farm's shape: farm, zones, areas, systems, positions (x/y in metres), crops
and phases, targets, holidays. Never in any view: phone, email, address, contact names, keys,
`user_id`/`created_by`, photos (only one at a time through **photo**), and outside `team` no worker id
at all. Tested: a test fails if a view gains such a column.

## Go live (in order)

Work in a session that has the Platform repo, then the owner does the dashboard steps.

1. **Platform repo**: copy `migrations/*` to `Platform/supabase/migrations/` (give them timestamps after
   the newest there), `functions/mcp/` to `Platform/supabase/functions/mcp/`, and add to
   `supabase/config.toml`: `[functions.mcp]` `verify_jwt = false`. Run `tests/run_local.sh` there.
2. **Database**: apply the two migrations (`supabase db push`).
3. **Reader password** — SQL editor, with a long random password that is kept only in step 4:
   `alter role mcp_reader with password '…';`
4. **Secret** — Edge Functions › Secrets: `MCP_READER_DB_URL` = the *Session pooler* string from
   Connect, with user `mcp_reader.azfiajzhzewjcblbltmp` and that password.
5. **Deploy**: `supabase functions deploy mcp --no-verify-jwt`.
6. **Auth › OAuth Server**: enable; dynamic client registration ON (Claude and ChatGPT register
   themselves); Authorization Path `/oauth/consent`. Check Auth › URL Configuration › Site URL is
   Naked Heart's address (`https://heart.nkd.farm`).
7. **Pages** into `Platform/console`: `oauth-consent.html` served at `/oauth/consent`,
   `ai-access.html` at `/ai-access.html`; fill `SUPABASE_KEY` (the publishable key the console
   already uses). Deploy the console (`deploy-console.ps1`).
8. **Token hook** — Auth › Hooks › Customize access token › Postgres › `public.mcp_token_hook`.
   Then sign in to Naked Heart and Naked Brain normally: they must work as before.
9. **Other Edge Functions**: any that checks the caller and then acts with the service key must
   refuse AI tokens. Add at the top, after reading the bearer token:
   ```ts
   const p = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
   if (p.client_id || p.role === 'mcp_reader') return new Response('Not for AI connections', { status: 403 });
   ```
   At least `admin-user`; check all 17 (`assistant`, `photo-chat`, `scout-photo`, … ).
10. **Test with your own account**: in AI access give yourself `ipm` for 1 week; Claude › Settings ›
    Connectors › Add custom connector › the address; sign in, Allow; ask "describe what you can see",
    then a question; check *What was asked*; press Stop; the next question must be refused.

**Until step 8 and 9 are done, give access only to people without write rights in Naked Heart**
(outside freelancers): by Supabase's default an OAuth token carries the person's normal rights at the
REST API. The MCP function itself is read-only either way.

## Checks only the live system can answer

- Supabase accepting `role: mcp_reader` from the hook (its docs list only anon/authenticated). If
  OAuth sign-in then fails, remove the `jsonb_set(… role …)` and keep the access check; the MCP path
  stays read-only (it never uses the token's role), and step 9 still covers the other functions.
- `/auth/v1/user` accepting a token whose role is `mcp_reader` (the function's token check).
- Claude and ChatGPT finding the OAuth server from the `WWW-Authenticate` header on the
  `supabase.co/functions/v1/mcp` address. If one does not, put `mcp.nkd.farm` (Cloudflare) in front and
  serve `/.well-known/oauth-protected-resource` at its root; set `MCP_PUBLIC_URL`.
- The ChatGPT menu names for adding a custom MCP connector change often; the page says "developer mode".

## Decisions

- **Supabase Auth's OAuth 2.1 server** (beta, free in beta) instead of an own login: people sign in
  with their Naked Heart account; freelancers need one (the access can be given to an email before
  the account exists; it binds when that email is confirmed).
- **Access is explicit for everyone**, managers included: no `mcp.access` row, no data.
- **The AI's SQL runs on its own login role** (`mcp_reader`), never on the postgres connection: from a
  postgres connection one `select set_config('role','postgres',…)` inside a query would undo any
  `set role`. As `mcp_reader` there is nothing to switch to.
- **The request's scope is a random id with a 2-minute life**, read by `mcp.farms()`, not the user id:
  a query can change settings, but it cannot guess another request's id.
- **One SELECT, read-only, rolled back, connection closed**: the extended protocol refuses a second
  statement; nothing a query sets (settings, temp tables) survives into the next call.
- **Standard libraries are shared** (crops, IPM products and templates, market prices) with anyone who
  has access. If the crop library must stay private from outsiders, make `crops` and `crop_phases`
  farm-only in `gen/views.py`.
- Limits: 60 calls a minute per person, 15 s per query, 1000 rows, 150 kB of text per answer.

## Learned the hard way (in this session)

- porsager `postgres`: passing `JSON.stringify(x)` to a `::jsonb` parameter stores a JSON *string*;
  use `sql.json(x)`.
- The worker restart kills a local Postgres in the scratchpad; keep it in `/var/tmp/pgmcp`.

## Open

- **Accounting is mostly empty**: `cost_entry`, `sales_order`, `purchase_order` have 0 rows (18 Oct);
  only purchase requests (22), harvests (15), task times and market prices hold data. Where are the
  books (Xero, Sage, Excel)? Either Naked Heart records them, or they are imported into `cost_entry`.
- Full-size photos (Storage `evidence` bucket) are not served, only the 640 px copy in the table.
- The two pages are tested only for syntax here, not against the live Supabase; later they could
  become a Naked Heart card.
- `mcp_access_give` is open to every Naked Heart manager role (`farm_admin`, `farm_manager`, `office`,
  franchisor). Narrow it to `farm_admin` if wanted.
