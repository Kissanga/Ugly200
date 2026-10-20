// The mcp.nkd.farm Worker, with fetch to Supabase faked. Node 22: node tests/worker.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../cloudflare/mcp-worker.js';

const calls = [];
globalThis.fetch = async (url, init = {}) => {
  calls.push({ url: String(url), init });
  if (String(url).includes('/.well-known/oauth-authorization-server/auth/v1')) {
    return new Response(JSON.stringify({ issuer: 'https://azfiajzhzewjcblbltmp.supabase.co/auth/v1' }), { headers: { 'Content-Type': 'application/json' } });
  }
  const auth = new Headers(init.headers).get('authorization');
  if (!auth) {
    return new Response(JSON.stringify({ error: 'sign in' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json',
        'WWW-Authenticate': 'Bearer resource_metadata="https://azfiajzhzewjcblbltmp.supabase.co/functions/v1/mcp/.well-known/oauth-protected-resource"' },
    });
  }
  const body = init.body ? await new Response(init.body).text() : '';
  return new Response(JSON.stringify({ echo: body, auth }), { headers: { 'Content-Type': 'application/json' } });
};

const req = (path, init) => worker.fetch(new Request('https://mcp.nkd.farm' + path, init));

test('protected resource metadata names mcp.nkd.farm and Supabase Auth', async () => {
  for (const p of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp']) {
    const m = await (await req(p)).json();
    assert.equal(m.resource, 'https://mcp.nkd.farm');
    assert.deepEqual(m.authorization_servers, ['https://azfiajzhzewjcblbltmp.supabase.co/auth/v1']);
  }
});

test('no token: 401 points to the mcp.nkd.farm metadata', async () => {
  const r = await req('/', { method: 'POST', body: '{}' });
  assert.equal(r.status, 401);
  assert.equal(r.headers.get('www-authenticate'), 'Bearer resource_metadata="https://mcp.nkd.farm/.well-known/oauth-protected-resource"');
  assert.equal(r.headers.get('access-control-expose-headers'), 'WWW-Authenticate, Mcp-Session-Id');
});

test('a call goes to the Supabase function with its token and body, without cookies', async () => {
  calls.length = 0;
  const r = await req('/', { method: 'POST', headers: { Authorization: 'Bearer tok', Cookie: 'x=1', 'Content-Type': 'application/json' },
    body: '{"jsonrpc":"2.0","id":1,"method":"ping"}' });
  const b = await r.json();
  assert.equal(calls[0].url, 'https://azfiajzhzewjcblbltmp.supabase.co/functions/v1/mcp');
  assert.equal(b.auth, 'Bearer tok');
  assert.equal(b.echo, '{"jsonrpc":"2.0","id":1,"method":"ping"}');
  assert.equal(new Headers(calls[0].init.headers).get('cookie'), null);
});

test('/mcp works as well as the root', async () => {
  calls.length = 0;
  await req('/mcp', { method: 'POST', headers: { Authorization: 'Bearer tok' }, body: '{}' });
  assert.equal(calls[0].url, 'https://azfiajzhzewjcblbltmp.supabase.co/functions/v1/mcp');
});

test('older clients find the sign-in server at the root', async () => {
  const m = await (await req('/.well-known/oauth-authorization-server')).json();
  assert.equal(m.issuer, 'https://azfiajzhzewjcblbltmp.supabase.co/auth/v1');
});

test('anything else is 404, and CORS preflight is answered', async () => {
  assert.equal((await req('/admin')).status, 404);
  assert.equal((await req('/', { method: 'OPTIONS' })).status, 204);
});
