#!/usr/bin/env bash
# Runs the Naked Heart MCP migrations and tests on a throwaway local Postgres (stub, not Supabase).
# Usage: tests/run_local.sh     (needs psql, python3, node 22; PGHOST/PGPORT/PGUSER as usual,
#                                 and a server that lets mcp_reader log in without a password)
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${MCP_TEST_DB:-mcp_test}
LOG=$(mktemp)
psql -d postgres -qc "drop database if exists $DB;" 2>/dev/null || true
psql -d postgres -qc "drop role if exists mcp_reader;" 2>/dev/null || true
psql -d postgres -qc "create database $DB;"
run() { PGOPTIONS="-c client_min_messages=warning" psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$1" >/dev/null; }
run tests/stub_supabase.sql
python3 tests/gen_stub.py | psql -d "$DB" -v ON_ERROR_STOP=1 -q >/dev/null
python3 gen/views.py >/dev/null
run migrations/20261018120000_mcp_access.sql
run migrations/20261018120100_mcp_views.sql
run migrations/20261018120000_mcp_access.sql       # both can run twice
run migrations/20261018120100_mcp_views.sql

fail() { echo "TESTS FAILED:"; grep -m3 -E 'ERROR|FAIL' "$LOG"; exit 1; }
psql -d "$DB" -v ON_ERROR_STOP=1 -f tests/mcp_test.sql >"$LOG" 2>&1 || fail
get() { psql -d "$DB" -tAc "select v from test_ctx where k = '$1'"; }
psql -d "$DB" -U mcp_reader -v ON_ERROR_STOP=1 -v jane="$(get jane)" -v acc="$(get acc)" \
     -v random="$(get random)" -v expired="$(get expired)" -f tests/reader_test.sql >>"$LOG" 2>&1 || fail
grep -o 'PASS.*' "$LOG"
echo "SQL: $(grep -c 'PASS' "$LOG") passed"

if [ -d tests/node_modules ] || (cd tests && npm install --silent --no-audit --no-fund --no-package-lock >/dev/null 2>&1); then
  MCP_TEST_DB=$DB node --experimental-strip-types --no-warnings tests/handler.test.ts
else
  echo "skipped the MCP function test: could not install the postgres package"
fi
