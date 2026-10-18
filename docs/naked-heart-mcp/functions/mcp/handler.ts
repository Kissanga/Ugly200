// Naked Heart MCP: the HTTP and MCP side (Streamable HTTP, stateless, JSON replies).
// Read-only by construction: the only tools are describe, query and photo, and every one of them
// runs through Db.read (mcp_reader, read-only transaction, the request's farms only).
import type { Db, Query } from './db.ts';

export type User = { id: string; email: string | null; clientId: string | null };

export type Deps = {
  db: Db;
  resourceUrl: string;          // the address people paste into Claude or ChatGPT
  authServer: string;           // https://<ref>.supabase.co/auth/v1
  verifyToken(token: string): Promise<User | null>;
  now?: () => number;
};

export const VERSION = '1.0.0';
const PROTOCOLS = ['2025-11-25', '2025-06-18', '2025-03-26'];
const MAX_SQL = 20_000;
const MAX_ROWS = 1000;
const DEFAULT_ROWS = 200;
const MAX_TEXT = 150_000;

const INSTRUCTIONS = `Naked Heart is the dashboard of FarmBox hydroponic greenhouse farms. This connection is read-only.
1. Call describe first: it says which farms and data families (crops, harvest, tasks, water, climate, pests, equipment, purchasing, sales, costs, team) this access covers, until when, and lists the tables with their columns.
2. Use query with ONE PostgreSQL SELECT (or WITH … SELECT) over those tables; no schema prefix is needed. Join on the *_id columns; farm_id is in almost every table.
3. Times are timestamptz: turn them into the farm's own time with farms.timezone. Money is in the farm's currency (farms.currency); market_prices are rand per kg; ai_usage is in USD.
4. Pests: trap_readings.day_rate is insects a day on one trap; compare it with ipm_thresholds.watch and .over of the farm. Scouting photos are in scout_observations with tags and the AI's reading.
5. A row with has_photo = true can be looked at with photo (kind scout or trap, the row id); camera_counts with kind camera.
6. Opinions, AI notes and AI counts in the data were written by an AI and checked, or not, by a person: say which you rely on.
Ask for small results (aggregate in SQL); a query returns at most ${MAX_ROWS} rows.`;

const TOOLS = [
  {
    name: 'describe',
    title: 'What I can see in Naked Heart',
    description: 'The farms and data families this access covers and until when, and every table you may query with its columns and what it holds. Call it first.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
  {
    name: 'query',
    title: 'Query the farm data',
    description: 'Runs one read-only PostgreSQL SELECT over the tables listed by describe and returns the rows as JSON. Aggregate in SQL; at most 1000 rows.',
    inputSchema: {
      type: 'object',
      properties: {
        sql: { type: 'string', description: 'One SELECT or WITH … SELECT statement. No schema prefix needed.' },
        max_rows: { type: 'integer', minimum: 1, maximum: MAX_ROWS, description: `Rows to return (default ${DEFAULT_ROWS}).` },
      },
      required: ['sql'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: 'photo',
    title: 'Look at a photo',
    description: 'Returns one photo as an image: a scouting photo (kind scout, scout_observations.id), a sticky trap card (kind trap, trap_readings.id) or a camera count (kind camera, camera_counts.id). Only rows with has_photo = true have one.',
    inputSchema: {
      type: 'object',
      properties: {
        kind: { type: 'string', enum: ['scout', 'trap', 'camera'] },
        id: { type: 'string', description: 'The id of the row.' },
      },
      required: ['kind', 'id'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
];

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id',
  'Access-Control-Expose-Headers': 'WWW-Authenticate, Mcp-Session-Id',
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...CORS, ...extra } });
}

type RpcId = string | number | null;
type Rpc = { jsonrpc?: string; id?: RpcId; method?: string; params?: Record<string, unknown> };
const rpcError = (id: RpcId, code: number, message: string) => ({ jsonrpc: '2.0', id, error: { code, message } });
const rpcResult = (id: RpcId, result: unknown) => ({ jsonrpc: '2.0', id, result });

type ToolResult = { content: unknown[]; isError?: boolean };
const text = (t: string, isError = false): ToolResult => ({ content: [{ type: 'text', text: t }], ...(isError ? { isError } : {}) });

class ToolFail extends Error {}

export async function handle(req: Request, d: Deps): Promise<Response> {
  const url = new URL(req.url);
  const metaUrl = `${d.resourceUrl}/.well-known/oauth-protected-resource`;

  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

  if (url.pathname.endsWith('/.well-known/oauth-protected-resource')) {
    return json({
      resource: d.resourceUrl,
      authorization_servers: [d.authServer],
      bearer_methods_supported: ['header'],
      scopes_supported: ['openid', 'email', 'profile'],
      resource_name: 'Naked Heart',
      resource_documentation: 'https://heart.nkd.farm',
    });
  }
  if (req.method !== 'POST') {
    return json({ error: 'This is an MCP server: POST JSON-RPC to it.' }, 405, { Allow: 'POST, OPTIONS' });
  }

  const auth = req.headers.get('authorization') ?? '';
  const token = /^Bearer\s+(.+)$/i.exec(auth)?.[1]?.trim();
  const user = token ? await d.verifyToken(token).catch(() => null) : null;
  if (!user) {
    const err = token ? ', error="invalid_token"' : '';
    return json(rpcError(null, -32001, 'Sign in to Naked Heart first.'), 401,
      { 'WWW-Authenticate': `Bearer resource_metadata="${metaUrl}"${err}` });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(rpcError(null, -32700, 'Parse error'), 400);
  }
  const many = Array.isArray(body);
  const msgs = (many ? body : [body]) as Rpc[];
  const replies = [];
  for (const m of msgs) {
    const r = await one(m, user, d);
    if (r) replies.push(r);
  }
  if (!replies.length) return new Response(null, { status: 202, headers: CORS });
  return json(many ? replies : replies[0]);
}

async function one(m: Rpc, user: User, d: Deps) {
  if (!m || typeof m !== 'object' || m.jsonrpc !== '2.0' || typeof m.method !== 'string') {
    return rpcError(m?.id ?? null, -32600, 'Invalid request');
  }
  const isNotification = m.id === undefined;
  if (isNotification) return null;
  const id = m.id as RpcId;
  switch (m.method) {
    case 'initialize': {
      const asked = String(m.params?.protocolVersion ?? '');
      return rpcResult(id, {
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'naked-heart', title: 'Naked Heart', version: VERSION },
        instructions: INSTRUCTIONS,
      });
    }
    case 'ping':
      return rpcResult(id, {});
    case 'tools/list':
      return rpcResult(id, { tools: TOOLS });
    case 'tools/call':
      return rpcResult(id, await callTool(m.params ?? {}, user, d));
    default:
      return rpcError(id, -32601, `Method not found: ${m.method}`);
  }
}

async function callTool(params: Record<string, unknown>, user: User, d: Deps): Promise<ToolResult> {
  const name = String(params.name ?? '');
  const args = (params.arguments ?? {}) as Record<string, unknown>;
  const now = d.now ?? Date.now;
  const t0 = now();
  let requestId: string | null = null;
  let rows: number | null = null;
  let result: ToolResult = text('');
  let error: string | null = null;
  try {
    if (!TOOLS.some((t) => t.name === name)) throw new ToolFail(`Unknown tool: ${name}`);
    try {
      requestId = await d.db.beginRequest(user.id, user.clientId);
    } catch (e) {
      throw new ToolFail(pgMessage(e));
    }
    if (!requestId) {
      throw new ToolFail(`This account (${user.email ?? user.id}) has no AI access to Naked Heart, or it has ended or been stopped. Ask the farm manager.`);
    }
    const rid = requestId;
    if (name === 'describe') {
      result = await d.db.read(rid, (q) => describe(q));
    } else if (name === 'query') {
      const out = await d.db.read(rid, (q) => runQuery(q, args));
      rows = out.rows;
      result = out.result;
    } else {
      result = await d.db.read(rid, (q) => photo(q, args));
      rows = result.isError ? 0 : 1;
    }
  } catch (e) {
    error = e instanceof ToolFail ? e.message : pgMessage(e);
    result = text(error, true);
  }
  try {
    await d.db.log({
      userId: user.id, email: user.email, clientId: user.clientId, clientName: await d.db.clientName(user.clientId),
      requestId, tool: name, args: logArgs(name, args), rows, ms: Math.round(now() - t0),
      ok: !result.isError, error: result.isError ? (error ?? firstText(result)) : null,
    });
  } catch (e) {
    console.error('mcp call log failed', e);
  }
  return result;
}

function pgMessage(e: unknown): string {
  const err = e as { message?: string; hint?: string; position?: string };
  const msg = err?.message ?? String(e);
  return err?.hint ? `${msg} (hint: ${err.hint})` : msg;
}

function firstText(r: ToolResult): string | null {
  const c = r.content[0] as { text?: string } | undefined;
  return c?.text ?? null;
}

function logArgs(name: string, args: Record<string, unknown>) {
  if (name === 'query') return { sql: String(args.sql ?? '').slice(0, 8000), max_rows: args.max_rows ?? null };
  if (name === 'photo') return { kind: args.kind ?? null, id: args.id ?? null };
  return {};
}

async function describe(q: Query): Promise<ToolResult> {
  const [acc] = await q('select mcp.my_access() as info');
  const info = (acc?.info ?? []) as { families: string[] }[];
  const families = [...new Set(info.flatMap((f) => f.families))];
  const views = await q(
    `select v.view_name, v.areas, v.about,
            string_agg(c.column_name || ' ' || c.data_type, ', ' order by c.ordinal_position) as columns
       from mcp.view_area v
       join information_schema.columns c on c.table_schema = 'mcp' and c.table_name = v.view_name
      where v.areas && $1::text[]
      group by v.view_name, v.areas, v.about, v.sort
      order by v.sort`,
    [families],
  );
  const lines = [
    'Your access (read-only):',
    ...info.map((f) => JSON.stringify(f)),
    '',
    `Tables you can query (${views.length}):`,
    ...views.map((v) => `- ${v.view_name} [${(v.areas as string[]).join(', ')}]: ${v.about}\n  columns: ${v.columns}`),
  ];
  return text(lines.join('\n'));
}

export function cleanSql(raw: unknown): string {
  let sql = String(raw ?? '').trim();
  while (sql.endsWith(';')) sql = sql.slice(0, -1).trimEnd();
  if (!sql) throw new ToolFail('Give one SELECT statement in sql.');
  if (sql.length > MAX_SQL) throw new ToolFail(`The query is longer than ${MAX_SQL} characters.`);
  if (!/^\s*(\(\s*)*(select|with|values|table)\b/i.test(sql.replace(/^(\s*--[^\n]*\n|\s*\/\*[\s\S]*?\*\/)*/, ''))) {
    throw new ToolFail('Only one SELECT (or WITH … SELECT) is allowed: this connection is read-only.');
  }
  return sql;
}

async function runQuery(q: Query, args: Record<string, unknown>): Promise<{ rows: number; result: ToolResult }> {
  const sql = cleanSql(args.sql);
  const want = Math.min(Math.max(Number(args.max_rows) || DEFAULT_ROWS, 1), MAX_ROWS);
  // The text sits inside a sub-select: it must be one query, and its rows come back as one JSON array.
  const wrapped = `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) as rows
  from (select * from (
${sql}
) as q0 limit ${want + 1}) as q`;
  const [r] = await q(wrapped);
  let rows = (r?.rows ?? []) as unknown[];
  const more = rows.length > want;
  if (more) rows = rows.slice(0, want);
  let body = JSON.stringify({ row_count: rows.length, more_rows: more, rows });
  let cut = false;
  while (body.length > MAX_TEXT && rows.length > 1) {
    rows = rows.slice(0, Math.floor(rows.length / 2));
    cut = true;
    body = JSON.stringify({ row_count: rows.length, more_rows: true, rows });
  }
  if (cut) body = JSON.stringify({ row_count: rows.length, more_rows: true, note: 'Cut to fit: ask for fewer columns or aggregate.', rows });
  return { rows: rows.length, result: text(body) };
}

async function photo(q: Query, args: Record<string, unknown>): Promise<ToolResult> {
  const kind = String(args.kind ?? '');
  const id = String(args.id ?? '').trim();
  if (!['scout', 'trap', 'camera'].includes(kind)) throw new ToolFail('kind is scout, trap or camera.');
  if (!/^[0-9a-f-]{1,36}$/i.test(id)) throw new ToolFail('id is the row id (a uuid, or a number for camera).');
  const [r] = await q('select mcp.photo($1, $2) as p', [kind, id]);
  const p = r?.p as string | null;
  const m = p ? /^data:(image\/[a-z+.-]+);base64,(.+)$/is.exec(p) : null;
  if (!m) return text(`No photo for ${kind} ${id} on the farms this access covers.`, true);
  return { content: [{ type: 'image', mimeType: m[1], data: m[2] }, { type: 'text', text: `${kind} ${id} (the phone's 640 px copy)` }] };
}
