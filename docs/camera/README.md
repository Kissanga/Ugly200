# Reolink Duo 3 in Naked Heart

```
Duo 3 --RTSP--> go2rtc on the Windows 11 PC --> Cloudflare Tunnel (HTTPS + login) --> Cameras card in Naked Heart
```

A browser cannot play the camera's RTSP stream, and an HTTPS dashboard cannot open a camera on the farm network.
go2rtc on the always-on PC turns the stream into something browsers play; the tunnel publishes it over HTTPS
without opening any port on the router. The camera password stays on the PC.

## 1. Camera (Reolink app)

1. Settings > Network > Advanced > **Server Settings**: turn **RTSP** on (port 554).
2. Give the camera a fixed address: on the router, reserve its IP (DHCP reservation). Note it, e.g. `192.168.1.50`.
3. Prefer a dedicated camera user with view-only rights over `admin` (Settings > Users).

## 2. go2rtc on the Windows 11 PC

Copy this `docs/camera` folder to the PC (or `git pull` the repo), open **PowerShell as Administrator** in it:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-camera.ps1 -CameraIp 192.168.1.50 -User admin
```

It asks for the camera password, installs go2rtc in `C:\NakedCam`, starts it at every boot (scheduled task
`NakedCam go2rtc`, restarted if it stops), keeps the PC from sleeping on mains power, and opens the live view
on the PC. If you see the picture there, step 2 is done.

## 3. Cloudflare account and domain

A fixed tunnel address needs a domain on Cloudflare (any cheap domain moved to Cloudflare DNS works).
Put the camera on the **same domain as Naked Heart** if you can (e.g. `heart.example.com` and `cam.example.com`):
the login then works inside the dashboard on every browser, Safari included.

## 4. Tunnel (Cloudflare Zero Trust dashboard)

1. Zero Trust > Networks > **Tunnels** > Create a tunnel > Cloudflared > name `naked-cam`.
2. Choose Windows; copy the install command it shows and run it in PowerShell as Administrator on the PC
   (`cloudflared.exe service install <token>`). The tunnel then runs as a Windows service.
3. **Public hostname**: subdomain `cam`, your domain, **Path** (only these go through, everything else is refused):
   ```
   ^/?(stream\.html|video-stream\.js|video-rtc\.js|api/ws|api/stream\.m3u8|api/hls/.*)$
   ```
   Service: `HTTP` `localhost:1984`.

   The path rule matters: go2rtc's other pages can change its settings. Never publish the whole of go2rtc.

## 5. Login in front of the camera (required)

Zero Trust > Access > **Applications** > Add > Self-hosted: domain `cam.your-domain`, policy *Allow* for the
e-mails of the people who may watch (one-time PIN by e-mail is enough). Without this anyone with the address sees
the farm.

Test: open `https://cam.your-domain/stream.html?src=duo3&mode=mse,hls` on a phone off the farm WiFi.

## 6. The card in Naked Heart

`camera-card.html` is the Cameras card: set `CAM` to `https://cam.your-domain` and mount it on the dashboard
page. It shows the live view; the dashboard never holds the camera password.

## Notes

- The sub stream (H.264, low resolution) is what goes out. The 16MP main stream is H.265, which most browsers
  cannot play; showing it needs ffmpeg on the PC to convert it and much more upload bandwidth.
- iPhone needs iOS 17.1 or later for the MSE player; older ones fall back to HLS (a few seconds of delay).
- Change the camera password: run `install-camera.ps1` again.
- Picture squeezed to 4:3: the Duo 3 tags its sub stream with 3:8 pixels since a reboot; go2rtc.yaml has ffmpeg
  rewrite the tag (copy only). Run `install-camera.ps1` again if an older install is on the PC.
- Remove: `Unregister-ScheduledTask 'NakedCam go2rtc'`, delete `C:\NakedCam`, `cloudflared.exe service uninstall`.

## Uninstall (PowerShell as Administrator)

```powershell
cd C:\
Unregister-ScheduledTask -TaskName 'NakedCam go2rtc' -Confirm:$false -ErrorAction SilentlyContinue
Get-Process go2rtc -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item 'C:\NakedCam' -Recurse -Force
powercfg /change standby-timeout-ac 30
```
