# Naked Vision (cameras) — where things stand (10 Oct 2026)

Read this first when picking the cameras up again. How-to steps are in `README.md`; this file is what was
actually built, the decisions taken, and what is still open. No password or token is in this repo, and none
should ever be: the camera password lives only in `C:\NakedVision\go2rtc.yaml` on the farm PC, the tunnel token
only in the farm PC's `cloudflared` Windows service.

## What runs

```
Reolink Duo 3 (FarmLab)  --RTSP sub-->  go2rtc + ffmpeg on the farm PC  --Cloudflare Tunnel-->  cam.nkd.farm
192.168.0.250 (static)                  C:\NakedVision, 127.0.0.1:1984          (e-mail login)       |
                                                                                                  v
                                                    Naked Heart overview, FarmLab: the "Duo 3 · live" tile
```

| Part | Where | State |
|---|---|---|
| Camera | Reolink **Duo 3** at **192.168.0.250**, static IP set on the camera (the rain *the101 pro* 5G router has no DHCP reservation), router 192.168.0.1 | RTSP on (554), ONVIF on (8000), HTTPS on, HTTP/RTMP off |
| Camera streams | Clear `h264Preview_01_main` **H.265 7680x2160** 20 fps 10 Mbps · Fluent `h264Preview_01_sub` **H.264 1536x432** 20 fps 1 Mbps · no `_ext` | Clear kept for AI; Fluent is what goes out |
| Farm PC | the always-on Windows 11 PC (not the office laptop: the first install went on the wrong PC and was removed) | go2rtc 1.9.14, task `NakedVision go2rtc` (SYSTEM, at boot); `cloudflared` service; sleep off on mains |
| go2rtc settings | `go2rtc.yaml` here = template; installer fills it | API and RTSP on 127.0.0.1 only; WebRTC off; stream `duo3` |
| Domain | **nkd.farm** on Cloudflare (bought at GoDaddy, nameservers moved; Netlify website records kept DNS-only) | active |
| Tunnel | Cloudflare One (Zero Trust) tunnel `naked-cam` | route `cam.nkd.farm` → `http://localhost:1984`, path `^/?(stream\.html|video-stream\.js|video-rtc\.js|api/ws|api/stream\.m3u8|api/hls/.*)$` — everything else 404, so go2rtc's settings pages are never public |
| Login | Access application on `cam.nkd.farm`, policy "Family" (7 e-mails), One-time PIN | works; `https://cam.nkd.farm/` alone answers 404 by design |
| Live page | `https://cam.nkd.farm/stream.html?src=duo3&mode=mse,hls` | |
| Naked Heart | `js/cameras.js` + 3 small edits (dashboard.js, styles.css `.cam-*`, sw.js precache), 0.7.230–0.7.233: tile two wide in the overview tiles, plays on open, stops when the tab is hidden, only on unit code `FL` (FarmLab), ⤢ opens the page in a tab | live **only in the published copy** `nkdfarm/farmbox-console` — see Open 0 |

## Things learned the hard way

- **The Duo 3 tags its Fluent stream with 3:8 pixels since a reboot**: browsers then show 1536x432 as 4:3
  (Chrome `videoWidth` 1536x1152) — a squeezed panorama while every setting reads right. go2rtc now runs the
  stream through ffmpeg as a **copy** with `h264_metadata=sample_aspect_ratio=1/1` (no re-encoding). Tested with
  go2rtc 1.9.14 against a simulated camera sending the same tag. If a firmware update fixes the camera, the stream
  line can go back to plain `rtsp://…/h264Preview_01_sub` (then go2rtc needs no ffmpeg and RTSP can be off).
- A camera reboot can also reset Fluent's resolution: check it is still 1536x432.
- PowerShell: `"$var:"` is read as a drive — write `"${var}:"`. raw.githubusercontent caches a branch file for
  minutes: give the farm PC links by commit id.
- Windows on the farm PC is not English: grant by SID (`*S-1-5-32-544`), never by group name.
- The farm is on 5G (CGNAT): nothing can come in; the tunnel only goes out. Upload is the scarce thing.
- iPhone/Safari would not show the Access login inside the tile while Naked Heart was on github.io: ⤢ (own tab) works.
- The farm PC folder was `C:\NakedCam` until the rename to Naked Vision; the installer moves an old install.

## Open

0. **The camera tile is not in Naked Heart's source.** It was pushed to `nkdfarm/farmbox-console` (the published
   copy) because this session could not reach the private Platform repo. A deploy from `Platform/console` already
   wiped it once (restored in farmbox-console 51b2ae6). Bring it into Platform: copy `js/cameras.js` from
   farmbox-console commit 9614a43, and port its edits to `js/dashboard.js` (import + `wrap.append(...cameraTiles(data.farm))`
   at the end of `tiles()`), `styles.css` (the `.tile.cam-tile` / `.cam-*` rules) and `sw.js` (`./js/cameras.js` in SHELL).

1. **Camera firmware** — check Device → Info for the hardware no. and update (see the Reolink support page for
   Duo 3 PoE). Afterwards try the plain stream line to see if the 3:8 tag is gone.
2. **AI capture from the Clear stream** — proposed, not built: a private go2rtc stream `duo3_hq` on `_main`, a
   *Capture* button (and maybe hourly captures) on the tile asking the farm PC for one 7680x2160 photo
   (`/api/frame.jpeg?src=duo3_hq`, path to add to the tunnel rule), saved per farm and sent to the photo AI.
   Owner still to say: manual or scheduled, and what the AI should look for.
3. **NVIDIA (Jetson) box for YOLO** — planned: it would replace the farm PC (go2rtc + cloudflared + YOLO in Docker,
   cameras listed in Naked Heart). For 10 cameras: PoE cameras on a PoE switch, or a Reolink NVR.
4. **heart.nkd.farm** — Naked Brain is on `brain.nkd.farm`, Naked Heart on `heart.nkd.farm` (Oct 2026): the camera
   and the dashboard are now one site (nkd.farm), so the Access login should work inside the tile on iPhone too —
   to check.

## Scripts here

- `install-camera.ps1 -CameraIp 192.168.0.250 -User admin` — (re)installs go2rtc + ffmpeg, asks the password, writes
  `C:\NakedVision\go2rtc.yaml`, scheduled task, power settings. Safe to run again.
- `check-camera.ps1` — read-only report: settings (password masked), go2rtc and tunnel status, and each camera
  stream's real size read by ffmpeg.
- Uninstall: see the end of `README.md`.
