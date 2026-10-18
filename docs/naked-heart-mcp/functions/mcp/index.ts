// Naked Heart MCP — Supabase Edge Function `mcp`. Lets a person's own Claude or ChatGPT read the farm
// data their access covers, read-only. Deploy WITHOUT the gateway JWT check: the function answers
// 401 with the OAuth discovery header itself, which MCP clients need.
//   supabase functions deploy mcp --no-verify-jwt
// Secrets (Edge Functions > Secrets): MCP_READER_DB_URL — the mcp_reader connection string, with its
// password; only on Supabase. SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_DB_URL are already there.
// Optional: MCP_PUBLIC_URL when the server is reached through another address (e.g. mcp.nkd.farm).
import postgres from 'npm:postgres@3.4.9';
import { makeDb } from './db.ts';
import { handle, type User } from './handler.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const db = makeDb(postgres, Deno.env.get('SUPABASE_DB_URL')!, Deno.env.get('MCP_READER_DB_URL')!);
const resourceUrl = (Deno.env.get('MCP_PUBLIC_URL') ?? `${SUPABASE_URL}/functions/v1/mcp`).replace(/\/$/, '');

function claims(token: string): Record<string, unknown> {
  try {
    const part = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(part + '='.repeat((4 - (part.length % 4)) % 4)));
  } catch {
    return {};
  }
}

// Supabase Auth checks the token (signature, expiry, session not signed out); only then are its
// claims read for the OAuth client id.
async function verifyToken(token: string): Promise<User | null> {
  const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { Authorization: `Bearer ${token}`, apikey: ANON_KEY } });
  if (!r.ok) return null;
  const u = await r.json();
  if (!u?.id) return null;
  const c = claims(token);
  return { id: u.id, email: u.email ?? null, clientId: typeof c.client_id === 'string' ? c.client_id : null };
}

Deno.serve((req) => handle(req, { db, resourceUrl, authServer: `${SUPABASE_URL}/auth/v1`, verifyToken }));
