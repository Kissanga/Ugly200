# apply-0757.ps1 — applies the 0.7.57 database package to the LINKED Supabase project.
# Run from the FarmBox-Platform folder after copying this package in:
#   .\apply-0757.ps1              # apply everything, in order, stop on the first error
#   .\apply-0757.ps1 -CheckOnly   # only the read-only schema check (step 0)
# Never uses `supabase db push`.
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Q($sql) { supabase db query --linked $sql; if ($LASTEXITCODE -ne 0) { throw "query failed: $sql" } }
function F($file) {
  Write-Host "`n>> $file" -ForegroundColor Cyan
  supabase db query --linked -f (Join-Path $here $file)
  if ($LASTEXITCODE -ne 0) { throw "failed: $file" }
}

Write-Host "== Step 0: schema check (read-only) ==" -ForegroundColor Yellow
Q "select table_name, string_agg(column_name, ', ' order by ordinal_position) as columns from information_schema.columns where table_schema='public' and table_name in ('zone','position','crop','crop_cycle','crop_phase','sop','sop_version','sop_step','task','farm') group by 1 order by 1"
Q "select proname, pg_get_function_identity_arguments(oid) as args from pg_proc where pronamespace='public'::regnamespace and proname in ('sync_since','sync_since_v1','submit_run','complete_task') order by 1"
Q "select title, base_minutes, minutes_per_unit, unit from sop where trigger_kind='crop_plan' order by title"
Write-Host "`nExpected: zone(id,farm_id,name,area_m2) position(id,zone_id,code,area_m2) crop_cycle(is_default) crop_phase(cycle_id,seq,name,days) sop_version(sop_id,version,approved_at) task(farm_id,title,family,sop_id,sop_version_id,planned_date,area,estimated_minutes,status)" -ForegroundColor DarkGray
if ($CheckOnly) { exit 0 }

Write-Host "`n== Step 3: migrations ==" -ForegroundColor Yellow
F 'migrations\20260921120000_phase_a_grouped_tasks.sql'
supabase migration repair --status applied 20260921120000
F 'migrations\20260921120100_phase_b_categories_archive.sql'
supabase migration repair --status applied 20260921120100

Write-Host "`n== Crop library ==" -ForegroundColor Yellow
F 'data\crop_library_0757.sql'
F 'data\release_notes_0757.sql'

Write-Host "`n== Console: let the editor role write phase procedures ==" -ForegroundColor Yellow
Q "grant insert, update, delete on crop_phase_sop to authenticated"
Q "do `$`$ begin if not exists (select 1 from pg_policies where policyname='crop_phase_sop_edit') then create policy crop_phase_sop_edit on crop_phase_sop for all using (true) with check (true); end if; end `$`$"

Write-Host "`n== Smoke test ==" -ForegroundColor Yellow
Q "select category, count(*) from crop where archived_at is null group by 1 order by 1"
Q "select name, archived_reason from crop where archived_at is not null order by name"
Q "select count(*) as phases_without_procedure from crop_phase ph join crop_cycle cy on cy.id=ph.cycle_id join crop c on c.id=cy.crop_id where c.archived_at is null and not exists (select 1 from crop_phase_sop where phase_id=ph.id)"
Write-Host "`n0.7.57 database applied. Next: console (see console\CONSOLE-CHANGES.md), then deploy-console.ps1." -ForegroundColor Green
