# FarmBox-Platform 0.7.57 — drop-in package

Built 21 Sept 2026 in a session that could only reach this repo. **Start with
`GO-LIVE-0.7.57.md`.**

```
GO-LIVE-0.7.57.md          ordered commands for the owner's machine + assumptions to check
migrations/                two migrations (Phase A grouped tasks/units/phase procedures; Phase B categories/archive)
data/crop_library_0757.sql 50 crops · 31 procedures with checklists · every phase linked (generated)
data/release_notes_0757.sql
gen/crop_library.js        the generator: edit crops/procedures here, then `node gen/crop_library.js > data/crop_library_0757.sql`
tests/phase_ab_test.sql    9 test blocks (PASS lines); tests/run_local.sh runs the whole chain on a local Postgres
stub/00_schema_stub.sql    the ASSUMED platform schema, for local testing only — never run on Supabase
console/CONSOLE-CHANGES.md fragments for farmbox-console (labels, Archive window, phase procedures, planning, release bump)
```

Local proof (Postgres 16, stub schema): `tests/run_local.sh` → 9/9 PASS.
