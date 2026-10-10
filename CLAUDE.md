# Ugly200 — start here

This repository is **Naked Brain**, the farm's phone app (one page: `index.html`, `sw.js`, `version.json`),
published at `brain.nkd.farm`. It is also where the notes for the farm's other projects are kept, in `docs/`.

## Related repositories
- `nkdfarm/farmbox-console` — **Naked Heart**, the desktop dashboard (static site, `js/` modules).
- A private repository holds the database (Supabase migrations, functions); it is not reachable from every session.

## Project notes — read the one for the job before doing anything
| Project | Read first |
|---|---|
| Cameras (Reolink Duo 3 → go2rtc on the farm PC → Cloudflare tunnel `cam.nkd.farm` → Naked Heart tile) | `docs/camera/STATE.md` |
| FarmBox platform 0.7.57 package (crop library, grouped tasks) | `docs/farmbox-platform-0.7.57/README.md` |

## Keeping the notes useful
- Each project keeps a `docs/<project>/STATE.md`: what runs, where, the decisions taken, what was learned the hard
  way, and what is still open. Update it at the end of every session that changes the project, in the same commit.
- Never put a password, token or key in the repo. Say where it lives instead (e.g. "only on the farm PC").
- The owner works through the Claude app and TeamViewer on the farm PC: give PowerShell to paste, links by commit id
  (raw.githubusercontent caches branches), and test scripts here before handing them over.
