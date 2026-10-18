// Database side of the Naked Heart MCP function. Takes the postgres library as an argument so the
// same code runs on Supabase (Deno, npm:postgres) and in tests/handler.test.ts (Node).
//
// Two connections, never mixed:
//   admin  = SUPABASE_DB_URL (postgres): opens requests and writes the call log. No AI text runs here.
//   reader = MCP_READER_DB_URL (logs in as mcp_reader): runs the AI's SQL, read-only, and is always
//            rolled back and closed, so nothing a query sets survives it.

// deno-lint-ignore no-explicit-any
type Postgres = any;

export type LogEntry = {
  userId: string | null;
  email: string | null;
  clientId: string | null;
  clientName: string | null;
  requestId: string | null;
  tool: string;
  args: unknown;
  rows: number | null;
  ms: number;
  ok: boolean;
  error: string | null;
};

export type Query = (text: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

export type Db = {
  beginRequest(userId: string, clientId: string | null): Promise<string | null>;
  clientName(clientId: string | null): Promise<string | null>;
  log(e: LogEntry): Promise<void>;
  read<T>(requestId: string, fn: (q: Query) => Promise<T>): Promise<T>;
  close(): Promise<void>;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ROLLBACK = Symbol('rollback');

export function makeDb(postgres: Postgres, adminUrl: string, readerUrl: string): Db {
  const admin = postgres(adminUrl, { max: 2, prepare: false, idle_timeout: 20, connect_timeout: 10, onnotice: () => {} });
  const names = new Map<string, string | null>();

  return {
    async beginRequest(userId, clientId) {
      const [r] = await admin`select mcp.begin_request(${userId}::uuid, ${clientId}) as id`;
      return r?.id ?? null;
    },

    async clientName(clientId) {
      if (!clientId || !UUID.test(clientId)) return null;
      if (names.has(clientId)) return names.get(clientId) ?? null;
      let name: string | null = null;
      try {
        const [r] = await admin`select client_name from auth.oauth_clients where id = ${clientId}::uuid`;
        name = r?.client_name ?? null;
      } catch { /* the OAuth tables are Supabase's: a missing one only loses the name */ }
      names.set(clientId, name);
      return name;
    },

    async log(e) {
      await admin`
        insert into mcp.call_log (user_id, email, client_id, client_name, farm_ids, tool, args, rows, ms, ok, error)
        values (${e.userId}::uuid, ${e.email}, ${e.clientId}, ${e.clientName},
                coalesce((select array_agg(distinct x::uuid)
                            from mcp.request r, jsonb_each(r.farms) f(k, v), jsonb_array_elements_text(f.v) x
                           where r.id = ${e.requestId}::uuid), '{}'),
                ${e.tool}, ${admin.json(e.args ?? null)},
                ${e.rows}, ${e.ms}, ${e.ok}, ${e.error})`;
    },

    async read(requestId, fn) {
      const reader = postgres(readerUrl, { max: 1, prepare: false, connect_timeout: 10, idle_timeout: 5, onnotice: () => {} });
      let out: unknown;
      try {
        await reader.begin('read only', async (tx: Postgres) => {
          await tx`select set_config('mcp.request', ${requestId}, true), set_config('statement_timeout', '15s', true)`;
          // tx.unsafe uses the extended protocol: one statement only, never a script.
          out = await fn((text, params = []) => tx.unsafe(text, params));
          throw ROLLBACK;
        });
      } catch (err) {
        if (err !== ROLLBACK) throw err;
      } finally {
        await reader.end({ timeout: 1 });
      }
      return out as never;
    },

    async close() {
      await admin.end({ timeout: 1 });
    },
  };
}
