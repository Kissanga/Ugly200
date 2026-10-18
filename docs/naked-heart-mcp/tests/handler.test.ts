// Runs the real functions/mcp handler and db code against the local test database (after
// mcp_test.sql), with only the token check faked. Node 22: node --experimental-strip-types.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import postgres from 'postgres';
import { makeDb } from '../functions/mcp/db.ts';
import { handle, type User } from '../functions/mcp/handler.ts';

const DB = process.env.MCP_TEST_DB ?? 'mcp_test';
const PORT = process.env.PGPORT ?? '5433';
const adminUrl = `postgres://postgres@localhost:${PORT}/${DB}`;
const readerUrl = `postgres://mcp_reader@localhost:${PORT}/${DB}`;
const sql = postgres(adminUrl, { onnotice: () => {} });
const db = makeDb(postgres, adminUrl, readerUrl);

const TESTER = '00000000-0000-0000-0000-0000000000e9';
const CLIENT = '00000000-0000-0000-0000-0000000000c1';
const TOKENS: Record<string, User> = {
  'tok-tester': { id: TESTER, email: 'tester@consult.test', clientId: CLIENT },
  'tok-nobody': { id: '00000000-0000-0000-0000-0000000000e3', email: 'nobody@consult.test', clientId: CLIENT },
};
const deps = {
  db,
  resourceUrl: 'https://ref.supabase.co/functions/v1/mcp',
  authServer: 'https://ref.supabase.co/auth/v1',
  verifyToken: async (t: string) => TOKENS[t] ?? null,
};

await sql`insert into auth.users (id, email, email_confirmed_at) values (${TESTER}, 'tester@consult.test', now()) on conflict do nothing`;
await sql`insert into public.worker (id, farm_id, user_id, name, role, email)
          values ('00000000-0000-0000-0000-0000000060e9', '00000000-0000-0000-0000-00000000f00a', ${TESTER},
                  'Tester', 'ai_only', 'tester@consult.test')`;
await sql`insert into mcp.person (worker_id, ai_access) values ('00000000-0000-0000-0000-0000000060e9', true)`;
await sql`insert into mcp.person_data (worker_id, family)
          values ('00000000-0000-0000-0000-0000000060e9', 'pests'), ('00000000-0000-0000-0000-0000000060e9', 'tasks')`;
after(async () => { await sql.end(); await db.close(); });

let n = 0;
async function rpc(method: string, params: unknown = {}, token = 'tok-tester') {
  const res = await handle(new Request('https://ref.supabase.co/mcp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++n, method, params }),
  }), deps);
  return { status: res.status, body: await res.json() };
}
const call = async (name: string, args: unknown = {}, token = 'tok-tester') => (await rpc('tools/call', { name, arguments: args }, token)).body.result;
const rowsOf = (r: { content: { text: string }[] }) => JSON.parse(r.content[0].text);

test('discovery: protected resource metadata names Supabase Auth', async () => {
  const res = await handle(new Request('https://ref.supabase.co/mcp/.well-known/oauth-protected-resource'), deps);
  const m = await res.json();
  assert.equal(m.resource, deps.resourceUrl);
  assert.deepEqual(m.authorization_servers, [deps.authServer]);
});

test('no token: 401 with the resource_metadata header', async () => {
  const res = await handle(new Request('https://ref.supabase.co/mcp', { method: 'POST', body: '{}' }), deps);
  assert.equal(res.status, 401);
  assert.match(res.headers.get('www-authenticate') ?? '', /^Bearer resource_metadata="https:\/\/ref\.supabase\.co\/functions\/v1\/mcp\/\.well-known\/oauth-protected-resource"$/);
});

test('bad token: 401 invalid_token', async () => {
  const r = await rpc('initialize', {}, 'tok-wrong');
  assert.equal(r.status, 401);
});

test('GET is refused (no SSE stream)', async () => {
  const res = await handle(new Request('https://ref.supabase.co/mcp', { headers: { Authorization: 'Bearer tok-tester' } }), deps);
  assert.equal(res.status, 405);
});

test('initialize answers the asked protocol and gives instructions', async () => {
  const r = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 't', version: '1' } });
  assert.equal(r.body.result.protocolVersion, '2025-06-18');
  assert.match(r.body.result.instructions, /read-only/);
  const r2 = await rpc('initialize', { protocolVersion: '1999-01-01' });
  assert.equal(r2.body.result.protocolVersion, '2025-11-25');
});

test('a notification gets 202 and no body', async () => {
  const res = await handle(new Request('https://ref.supabase.co/mcp', {
    method: 'POST', headers: { Authorization: 'Bearer tok-tester' },
    body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
  }), deps);
  assert.equal(res.status, 202);
});

test('tools/list: describe, query, photo, all read-only', async () => {
  const r = await rpc('tools/list');
  const tools = r.body.result.tools;
  assert.deepEqual(tools.map((t: { name: string }) => t.name), ['describe', 'query', 'photo']);
  assert.ok(tools.every((t: { annotations: { readOnlyHint: boolean } }) => t.annotations.readOnlyHint));
});

test('unknown method: -32601', async () => {
  const r = await rpc('resources/list');
  assert.equal(r.body.error.code, -32601);
});

test('describe: the farms, the families and only their tables', async () => {
  const r = await call('describe');
  const t = r.content[0].text as string;
  assert.match(t, /"farm":"Farm A"/);
  assert.match(t, /"farm":"Farm A2"/);
  assert.match(t, /- trap_readings \[pests\]/);
  assert.match(t, /- tasks \[tasks\]/);
  assert.doesNotMatch(t, /- cost_entries/);
  assert.doesNotMatch(t, /- workers/);
});

test('query: counts on farm A and its sister unit A2 only', async () => {
  const r = await call('query', { sql: 'select count(*)::int as n, sum(total)::int as insects from trap_readings;' });
  assert.equal(r.isError, undefined);
  assert.deepEqual(rowsOf(r).rows, [{ n: 3, insects: 47 }]);
});

test('query: a comment at the end does not break the wrapping', async () => {
  const r = await call('query', { sql: 'select 1 as one -- just one' });
  assert.deepEqual(rowsOf(r).rows, [{ one: 1 }]);
});

test('query: max_rows and more_rows', async () => {
  const r = await call('query', { sql: 'select g from generate_series(1, 500) g', max_rows: 10 });
  const b = rowsOf(r);
  assert.equal(b.row_count, 10);
  assert.equal(b.more_rows, true);
});

test('query: not a SELECT is refused before it reaches the database', async () => {
  const r = await call('query', { sql: 'delete from trap_readings' });
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /read-only/);
});

test('query: two statements are refused by the database', async () => {
  const r = await call('query', { sql: "select 1) q0) q; set role postgres; select (select 1" });
  assert.equal(r.isError, true);
});

test('query: writing through a CTE fails', async () => {
  const r = await call('query', { sql: 'with x as (delete from trap_readings returning 1) select * from x' });
  assert.equal(r.isError, true);
});

test('query: the tables themselves are out of reach', async () => {
  const r = await call('query', { sql: 'select count(*) from public.trap_reading' });
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /permission denied/);
  const r2 = await call('query', { sql: 'select count(*) from auth.users' });
  assert.equal(r2.isError, true);
});

test('query: switching role from inside a query fails', async () => {
  const r = await call('query', { sql: "select set_config('role', 'postgres', false)" });
  assert.equal(r.isError, true);
});

test('query: what a query sets does not reach the next one', async () => {
  await call('query', { sql: "select set_config('mcp.request', gen_random_uuid()::text, false), set_config('search_path', 'public', false)" });
  const r = await call('query', { sql: 'select count(*)::int as n from trap_readings' });
  assert.deepEqual(rowsOf(r).rows, [{ n: 3 }]);
});

test('query: a database error comes back as a tool error the AI can read', async () => {
  const r = await call('query', { sql: 'select nope from trap_readings' });
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /column "nope" does not exist/);
});

test('photo: a scouting photo of farm A is an image', async () => {
  const r = await call('photo', { kind: 'scout', id: '00000000-0000-0000-0000-0000000050a1' });
  assert.equal(r.content[0].type, 'image');
  assert.equal(r.content[0].mimeType, 'image/jpeg');
  assert.equal(r.content[0].data, 'U0NPVVQ=');
});

test('photo: a trap card of farm B is not given', async () => {
  const r = await call('photo', { kind: 'trap', id: '00000000-0000-0000-0000-0000000040b1' });
  assert.equal(r.isError, true);
});

test('no access: every tool says so', async () => {
  const r = await call('describe', {}, 'tok-nobody');
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /no AI access/);
});

test('stopped mid-way: the next call is refused', async () => {
  await sql`update mcp.person set ai_access = false where worker_id = '00000000-0000-0000-0000-0000000060e9'`;
  const r = await call('query', { sql: 'select 1' });
  assert.equal(r.isError, true);
  await sql`update mcp.person set ai_access = true where worker_id = '00000000-0000-0000-0000-0000000060e9'`;
});

test('every call is logged with the farm, the AI name and the SQL', async () => {
  const rows = await sql`select tool, client_name, farm_ids, args, ok from mcp.call_log where user_id = ${TESTER} order by id`;
  assert.ok(rows.length >= 15);
  const q = rows.find((r) => r.tool === 'query' && r.ok);
  assert.equal(q?.client_name, 'Claude');
  assert.deepEqual([...q?.farm_ids].sort(), ['00000000-0000-0000-0000-00000000f00a', '00000000-0000-0000-0000-00000000fa02']);
  assert.match(q?.args.sql, /trap_readings/);
  assert.ok(rows.some((r) => !r.ok));
});
