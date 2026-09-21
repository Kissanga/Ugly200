# Prompt for the local Claude Code session (paste as the first message)

Open Claude Code in the FarmBox-Platform folder on the owner's machine, then paste:

---

Finalize FarmBox 0.7.57 and Naked Brain 0.11.6 for testing. Work autonomously, do not ask questions; make reasonable assumptions and report what you did.

Context: a cloud session built the whole 0.7.57 package but could not reach Supabase, this repo or farmbox-console. Everything it made is in `C:\Users\Francesco\Ugly200\docs\farmbox-platform-0.7.57` (pull `Kissanga/Ugly200 main` first). Read its `README.md` and `GO-LIVE-0.7.57.md`, then read this repo's `CLAUDE.md` for conventions (fresh-container test suite: migrations/*.sql, seed.sql, data/*.sql, tests/rls_test.sql; never `supabase db push`).

Do, in order:

1. **Schema check.** Run `apply-0757.ps1 -CheckOnly` (or the two queries at the top of GO-LIVE step 0). Compare the live column and function names with the ASSUMED ones listed there. Fix any difference inside the two migrations, the library generator (`gen/crop_library.js`, then regenerate `data/crop_library_0757.sql`) and `tests/phase_ab_test.sql`. Reconcile the 21 existing per-batch procedure titles with the library titles so links reuse them instead of creating twins. Map the sub-family names to Settings › Task families.
2. **Copy into this repo**: `migrations/20260921120000_phase_a_grouped_tasks.sql`, `migrations/20260921120100_phase_b_categories_archive.sql`, `data/crop_library_0757.sql`, `data/release_notes_0757.sql`, `tests/phase_ab_test.sql` (fold into the rls_test PASS style if that is the convention). Add every new function and its public wrapper to the "door into public" list the tests check.
3. **Run the fresh-container suite locally.** Expected: the previous 118 PASS plus the 9 new blocks. Fix until green.
4. **Apply to the linked project**: `apply-0757.ps1`, or the manual sequence in GO-LIVE step 3 (`supabase db query --linked -f …` then `supabase migration repair --status applied …`). Run the smoke queries. Plan one real crop with `plan_crop()` and inspect `task` + `task_position`.
5. **Console (farmbox-console clone)**: mount `console/farmbox-crops.js` on the Crop database page as described in `console/CONSOLE-CHANGES.md` (one container, one script tag, `FarmBoxCrops.mount({ el, sb, canEdit, openProcedure })`), map the five `--fbc-*` CSS variables to the console theme, replace the remaining `vines`/`fruiting` codes, show `task_position` rows under a task in the task list. Bump the release: `VERSION` in `console/js/update.js`, `version.json`, `?v=0.7.57` in `index.html`, `CACHE` in `sw.js`. Run `deploy-console.ps1`.
6. **Phone**: Naked Brain 0.11.6 is already on `Kissanga/Ugly200 main`; open it on the phone, "Update now", sign in, sync, and check a planned crop shows one card per crop × zone × date with its positions and minutes, and that a checklist shows step titles with a Details tap.
7. **Commit** each repo with clear messages. Report: what was applied, the test counts, anything you changed from the package and why.

---
