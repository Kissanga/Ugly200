# Ugly200 — start here

This repository is **Naked Brain**, the farm's phone app (one page: `index.html`, `sw.js`, `version.json`),
published at `brain.nkd.farm`. It is also where the notes for the farm's other projects are kept, in `docs/`.

## The three projects
| Name | What | Source of truth | Published | Folder on the office PC |
|---|---|---|---|---|
| **Naked Brain** | phone app | this repo (`Kissanga/Ugly200`) | `brain.nkd.farm` | `C:\Users\Francesco\NakedBrain` |
| **Naked Heart** | desktop dashboard | the private **Platform** repo, `console/` (with `supabase/migrations`) — read `Platform/CLAUDE.md` | `heart.nkd.farm`, via `deploy-console.ps1` to `nkdfarm/farmbox-console` | `Platform` |
| **Naked Vision** | cameras | notes and scripts: `docs/camera/` here | `cam.nkd.farm` | farm PC: `C:\NakedVision` |

`nkdfarm/farmbox-console` is only the **published copy** of Naked Heart: a change made there and not in
`Platform/console` is wiped by the next deploy. Change Naked Heart in Platform, then deploy.

## Project notes — read the one for the job before doing anything
| Project | Read first |
|---|---|
| Naked Vision — cameras (Reolink Duo 3 → go2rtc on the farm PC → Cloudflare tunnel `cam.nkd.farm` → Naked Heart tile) | `docs/camera/STATE.md` |
| FarmBox platform 0.7.57 package (crop library, grouped tasks) | `docs/farmbox-platform-0.7.57/README.md` |

## Keeping the notes useful
- Each project keeps a `docs/<project>/STATE.md`: what runs, where, the decisions taken, what was learned the hard
  way, and what is still open. Update it at the end of every session that changes the project, in the same commit.
- Never put a password, token or key in the repo. Say where it lives instead (e.g. "only on the farm PC").
- The owner works through the Claude app and TeamViewer on the farm PC: give PowerShell to paste, links by commit id
  (raw.githubusercontent caches branches), and test scripts here before handing them over.
