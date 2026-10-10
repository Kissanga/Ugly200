# Deep check of the camera relay on the farm PC: what go2rtc is set to, whether it runs, and the real size and
# shape of each camera stream (main = Clear, sub = Fluent, ext = Balanced) as ffmpeg reads them.
# Run in PowerShell as Administrator:  powershell -ExecutionPolicy Bypass -File .\check-camera.ps1
# Prints no password: it is read from C:\NakedCam\go2rtc.yaml and masked in everything shown.
#Requires -RunAsAdministrator
param([string]$Dir = 'C:\NakedCam')
$ErrorActionPreference = 'Continue'
$cfgPath = Join-Path $Dir 'go2rtc.yaml'
if (-not (Test-Path $cfgPath)) { throw "No $cfgPath: go2rtc is not installed on this PC." }
$cfg = Get-Content $cfgPath -Raw
if ($cfg -notmatch 'rtsp://([^:@/\s]+):([^@\s]+)@([\d.]+):(\d+)/(\w+?)(_main|_sub|_ext)') { throw "No camera address found in $cfgPath" }
$user, $pass, $ip, $port, $base = $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5]
$mask = { param($s) ($s -replace [regex]::Escape($pass), '***') }

Write-Host "`n== go2rtc settings ($cfgPath, password masked)" -ForegroundColor Cyan
& $mask $cfg

Write-Host "`n== go2rtc program" -ForegroundColor Cyan
Get-ScheduledTask 'NakedCam go2rtc' -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize
Get-Process go2rtc -ErrorAction SilentlyContinue | Select-Object Id, StartTime | Format-Table -AutoSize
& (Join-Path $Dir 'go2rtc.exe') -version 2>&1 | Select-Object -First 2

Write-Host "`n== go2rtc's view of the stream" -ForegroundColor Cyan
try { & $mask (Invoke-WebRequest 'http://127.0.0.1:1984/api/streams' -UseBasicParsing).Content } catch { "go2rtc does not answer: $_" }

Write-Host "`n== cloudflared tunnel service" -ForegroundColor Cyan
Get-Service cloudflared -ErrorAction SilentlyContinue | Select-Object Name, Status | Format-Table -AutoSize

$ff = Join-Path $Dir 'ffmpeg.exe'
if (-not (Test-Path $ff)) {
  Write-Host "`n(downloading ffmpeg once, about 150 MB, to read the streams)"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $fz = Join-Path $env:TEMP 'ffmpeg-win64.zip'; $fx = Join-Path $env:TEMP 'ffmpeg-win64'
  Invoke-WebRequest 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile $fz -UseBasicParsing
  Expand-Archive $fz $fx -Force
  Copy-Item (Get-ChildItem $fx -Recurse -Filter ffmpeg.exe | Select-Object -First 1).FullName $ff
  Remove-Item $fz, $fx -Recurse -Force
}

foreach ($s in '_sub', '_ext', '_main') {
  $url = "rtsp://${user}:${pass}@${ip}:${port}/${base}$s"
  Write-Host "`n== camera stream $base$s" -ForegroundColor Cyan
  $out = & $ff -hide_banner -rtsp_transport tcp -timeout 8000000 -i $url -frames:v 1 -f null - 2>&1 | Out-String
  ($out -split "`n" | Where-Object { $_ -match 'Stream #|Input #|error|Error|401|404|refused' } | Select-Object -First 6) |
    ForEach-Object { & $mask $_ }
}
Write-Host "`nDone. Copy everything above (no password in it) and send it." -ForegroundColor Green
