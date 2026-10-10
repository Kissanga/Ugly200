# Sets up the Reolink Duo 3 relay on the always-on Windows 11 PC.
# Run in PowerShell as Administrator, from this folder:
#   powershell -ExecutionPolicy Bypass -File .\install-camera.ps1 -CameraIp 192.168.1.50
#Requires -RunAsAdministrator
param(
  [Parameter(Mandatory = $true)][string]$CameraIp,
  [string]$User = 'admin',
  [string]$Dir = 'C:\NakedVision'
)
$ErrorActionPreference = 'Stop'
$task = 'NakedVision go2rtc'
# Naked Vision was called NakedCam until Oct 2026: an install under the old name is moved, not downloaded again
$oldTask = 'NakedCam go2rtc'; $oldDir = 'C:\NakedCam'

Write-Host "1/6 Checking the camera at $CameraIp ..."
if (-not (Test-NetConnection $CameraIp -Port 554 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
  throw "The camera does not answer on port 554. In the Reolink app: Settings > Network > Advanced > Server Settings, turn RTSP on; check the IP."
}

$secure = Read-Host "Reolink password for '$User'" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))

Write-Host "2/6 Downloading go2rtc ..."
foreach ($t in $task, $oldTask) {
  if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $t }
}
Get-Process go2rtc -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
if ((Test-Path $oldDir) -and -not (Test-Path $Dir)) {
  Write-Host "    moving $oldDir to $Dir"
  Move-Item $oldDir $Dir
}
if (Get-ScheduledTask -TaskName $oldTask -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $oldTask -Confirm:$false }
New-Item -ItemType Directory -Force $Dir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$zip = Join-Path $env:TEMP 'go2rtc_win64.zip'
Invoke-WebRequest 'https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_win64.zip' -OutFile $zip -UseBasicParsing
Expand-Archive $zip $Dir -Force
Remove-Item $zip
$ff = Join-Path $Dir 'ffmpeg.exe'
if (-not (Test-Path $ff)) {
  # go2rtc's ffmpeg fixes the Duo 3's pixel-shape tag (go2rtc.yaml); copy only, no re-encoding
  Write-Host "    ... and ffmpeg (about 150 MB, once)"
  $fz = Join-Path $env:TEMP 'ffmpeg-win64.zip'
  Invoke-WebRequest 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile $fz -UseBasicParsing
  $fx = Join-Path $env:TEMP 'ffmpeg-win64'
  Expand-Archive $fz $fx -Force
  Copy-Item (Get-ChildItem $fx -Recurse -Filter ffmpeg.exe | Select-Object -First 1).FullName $ff
  Remove-Item $fz, $fx -Recurse -Force
}

Write-Host "3/6 Writing $Dir\go2rtc.yaml (only SYSTEM and Administrators can read it) ..."
$cfgPath = Join-Path $Dir 'go2rtc.yaml'
$cfg = (Get-Content (Join-Path $PSScriptRoot 'go2rtc.yaml') -Raw).
  Replace('CAMERA_USER', [Uri]::EscapeDataString($User)).
  Replace('CAMERA_PASS', [Uri]::EscapeDataString($plain)).
  Replace('CAMERA_IP', $CameraIp).
  Replace('FFMPEG_BIN', ($ff -replace '\\', '/'))
$cfg | Set-Content -Encoding ASCII $cfgPath
$plain = $null
# SIDs, not names: group names change with the Windows language (Administrateurs, Administratoren ...)
icacls $cfgPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null

Write-Host "4/6 Starting go2rtc at every boot, restarting it if it stops ..."
$action = New-ScheduledTaskAction -Execute (Join-Path $Dir 'go2rtc.exe') -Argument "-config `"$cfgPath`"" -WorkingDirectory $Dir
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $task

Write-Host "5/6 Keeping the PC awake on mains power ..."
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

Write-Host "6/6 Checking the stream ..."
Start-Sleep -Seconds 4
try {
  Invoke-WebRequest 'http://127.0.0.1:1984/api/streams' -UseBasicParsing | Out-Null
  Write-Host "go2rtc is running. Opening the live view on this PC ..." -ForegroundColor Green
  Start-Process 'http://127.0.0.1:1984/stream.html?src=duo3&mode=mse'
} catch {
  throw "go2rtc did not start. Run '$Dir\go2rtc.exe -config $cfgPath' by hand to see the error."
}
Write-Host "Next: README.md step 4 (Cloudflare Tunnel)."
