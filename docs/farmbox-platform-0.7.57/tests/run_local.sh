#!/usr/bin/env bash
# Runs the 0.7.57 SQL on a throwaway local Postgres (stub schema, not Supabase).
# Usage: tests/run_local.sh            (needs psql; PGHOST/PGPORT/PGUSER as usual)
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${FBX_TEST_DB:-fbx_test}
LOG=$(mktemp)
psql -d postgres -qc "drop database if exists $DB;" 2>/dev/null || true
psql -d postgres -qc "create database $DB;"
run() { psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$1" 2>&1 | grep -v 'NOTICE\|lib_sop\|lib_crop\|^-\+$\|^(1 row)$\|^$\|^ [0-9a-f-]\{36\}$' || true; }
run stub/00_schema_stub.sql
run tests/01_legacy_rows.sql
run migrations/20260921120000_phase_a_grouped_tasks.sql
run migrations/20260921120100_phase_b_categories_archive.sql
run data/crop_library_0757.sql
if psql -d "$DB" -v ON_ERROR_STOP=1 -f tests/phase_ab_test.sql >"$LOG" 2>&1; then
  grep -o 'PASS.*' "$LOG"
  echo "ALL 0.7.57 TESTS PASSED ($(grep -c 'PASS' "$LOG"))"
else
  grep -o 'PASS.*' "$LOG" || true
  echo "TESTS FAILED:"; grep -m3 'ERROR' "$LOG"; exit 1
fi
