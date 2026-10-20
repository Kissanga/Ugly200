// Naked Heart MCP — Cloudflare Worker for https://mcp.nkd.farm
//
// Gives the MCP server a short address on the farm's own domain. Everything is passed to the Supabase
// Edge Function `mcp` as it came (the person's sign-in token included); the Worker keeps no secret and
// sees nothing it stores. It answers two things itself, so Claude and ChatGPT stay on mcp.nkd.farm:
//   /.well-known/oauth-protected-resource  — "this server is https://mcp.nkd.farm, sign in at Supabase Auth"
//   the WWW-Authenticate header of a 401   — rewritten to point at that page instead of the supabase.co one
// and, for older MCP clients that look for the sign-in server at the root of the address,
//   /.well-known/oauth-authorization-server — Supabase Auth's own metadata, passed through.
// The supabase.co address keeps working unchanged: nothing on Supabase is changed by this Worker.
//
// Deploy: Cloudflare dashboard › Workers & Pages › Create › Worker (name naked-heart-mcp) › Edit code ›
// paste this file › Deploy; then the Worker's Settings › Domains & Routes › Add › Custom domain ›
// mcp.nkd.farm. See ../STATE.md.

const PROJECT = 'https://azfiajzhzewjcblbltmp.supabase.co';
const UPSTREAM = `${PROJECT}/functions/v1/mcp`;
const AUTH_SERVER = `${PROJECT}/auth/v1`;
const AUTH_METADATA = `${PROJECT}/.well-known/oauth-authorization-server/auth/v1`;
const OPENID_CONFIG = `${AUTH_SERVER}/.well-known/openid-configuration`;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id',
  'Access-Control-Expose-Headers': 'WWW-Authenticate, Mcp-Session-Id',
};

// What the Supabase function must not receive from the open internet: the browser's cookies and
// Cloudflare's own headers about the visitor.
const DROP = ['cookie', 'host', 'cf-connecting-ip', 'cf-ipcountry', 'cf-ray', 'cf-visitor', 'x-real-ip', 'x-forwarded-for'];

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...CORS, ...extra } });
}

async function passThrough(url, cacheSeconds) {
  const r = await fetch(url, { headers: { Accept: 'application/json' } });
  return new Response(r.body, {
    status: r.status,
    headers: { 'Content-Type': r.headers.get('Content-Type') || 'application/json', 'Cache-Control': `public, max-age=${cacheSeconds}`, ...CORS },
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const self = `https://${url.host}`;
    const path = url.pathname.replace(/\/+$/, '') || '/';
    const metaUrl = `${self}/.well-known/oauth-protected-resource`;

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    if (path === '/.well-known/oauth-protected-resource' || path.startsWith('/.well-known/oauth-protected-resource/')) {
      return json({
        resource: self,
        authorization_servers: [AUTH_SERVER],
        bearer_methods_supported: ['header'],
        scopes_supported: ['openid', 'email', 'profile'],
        resource_name: 'Naked Heart',
        resource_documentation: 'https://heart.nkd.farm',
      }, 200, { 'Cache-Control': 'public, max-age=300' });
    }
    if (path === '/.well-known/oauth-authorization-server' || path.startsWith('/.well-known/oauth-authorization-server/')) {
      return passThrough(AUTH_METADATA, 3600);
    }
    if (path === '/.well-known/openid-configuration') return passThrough(OPENID_CONFIG, 3600);
    if (path !== '/' && path !== '/mcp') {
      return json({ error: 'Not found. The Naked Heart MCP server is https://mcp.nkd.farm' }, 404);
    }

    const headers = new Headers(request.headers);
    for (const h of DROP) headers.delete(h);
    const upstream = await fetch(UPSTREAM + url.search, {
      method: request.method,
      headers,
      body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body,
      redirect: 'manual',
    });

    const out = new Response(upstream.body, upstream);
    for (const [k, v] of Object.entries(CORS)) out.headers.set(k, v);
    const challenge = upstream.headers.get('WWW-Authenticate');
    if (challenge) {
      out.headers.set('WWW-Authenticate', challenge.replace(/resource_metadata="[^"]*"/, `resource_metadata="${metaUrl}"`));
    }
    return out;
  },
};
