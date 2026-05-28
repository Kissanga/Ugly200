# transcribe.ps1 — Video/Audio to text via Groq Whisper
# Usage: .\transcribe.ps1 video.mp4
#        .\transcribe.ps1 video.mp4 -Lang it
#        .\transcribe.ps1 video.mp4 -Out transcript.txt

param(
    [Parameter(Mandatory)][string]$File,
    [string]$Lang = "en",
    [string]$Out = ""
)

$ConfigFile = "$env:USERPROFILE\.groq_key"
$MaxBytes   = 24MB   # Groq limit is 25 MB

# ── GROQ KEY ─────────────────────────────────────────────────────
if (Test-Path $ConfigFile) {
    $ApiKey = (Get-Content $ConfigFile -Raw).Trim()
} else {
    $ApiKey = Read-Host "Enter your Groq API key (saved to $ConfigFile)"
    $ApiKey | Out-File $ConfigFile -Encoding utf8 -NoNewline
}

# ── VALIDATE INPUT ────────────────────────────────────────────────
$File = Resolve-Path $File -ErrorAction Stop | Select-Object -ExpandProperty Path
$FileSize = (Get-Item $File).Length

# ── SPLIT LARGE FILES (ffmpeg required only here) ─────────────────
$Chunks = @()
if ($FileSize -gt $MaxBytes) {
    Write-Host "File is $([math]::Round($FileSize/1MB,1)) MB — splitting via ffmpeg..." -ForegroundColor Yellow
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Host "Installing ffmpeg via winget..." -ForegroundColor Yellow
        winget install --id Gyan.FFmpeg -e --silent
        $env:PATH += ";C:\Program Files\ffmpeg\bin"
        if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            Write-Error "ffmpeg not found. Install from https://ffmpeg.org/download.html"
            exit 1
        }
    }
    # Get duration without re-encoding
    $Duration = [double](ffmpeg -i $File 2>&1 | Select-String "Duration" |
                ForEach-Object { $_ -replace ".*Duration: (\d+):(\d+):([\d.]+).*",'$1*3600+$2*60+$3' } |
                Invoke-Expression)
    # Estimate chunk size from file size ratio; use 5 min chunks as safe default
    $ChunkSecs = [math]::Max(60, [math]::Floor($Duration * $MaxBytes / $FileSize) - 5)
    $Ext = [System.IO.Path]::GetExtension($File)
    $i = 0
    for ($Start = 0; $Start -lt $Duration; $Start += $ChunkSecs) {
        $ChunkFile = "$env:TEMP\chunk_$i$Ext"
        # -c copy = no re-encoding, instant split
        ffmpeg -y -ss $Start -i $File -t $ChunkSecs -c copy $ChunkFile -loglevel error
        $Chunks += $ChunkFile
        $i++
    }
} else {
    $Chunks = @($File)   # send video/audio directly — no extraction needed
}

# ── TRANSCRIBE ────────────────────────────────────────────────────
$Transcript = ""
$Total = $Chunks.Count
for ($i = 0; $i -lt $Total; $i++) {
    $Chunk = $Chunks[$i]
    if ($Total -gt 1) { Write-Host "Transcribing chunk $($i+1)/$Total..." -ForegroundColor Cyan }
    else               { Write-Host "Transcribing..." -ForegroundColor Cyan }

    $Bytes   = [System.IO.File]::ReadAllBytes($Chunk)
    $Content = [System.Net.Http.ByteArrayContent]::new($Bytes)
    $Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

    $Form = [System.Net.Http.MultipartFormDataContent]::new()
    $Form.Add([System.Net.Http.StringContent]::new("whisper-large-v3-turbo"), "model")
    $Form.Add([System.Net.Http.StringContent]::new($Lang), "language")
    $Form.Add([System.Net.Http.StringContent]::new("text"), "response_format")
    $Form.Add($Content, "file", [System.IO.Path]::GetFileName($Chunk))

    $Client = [System.Net.Http.HttpClient]::new()
    $Client.DefaultRequestHeaders.Authorization =
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $ApiKey)

    try {
        $Response = $Client.PostAsync("https://api.groq.com/openai/v1/audio/transcriptions", $Form).Result
        $Body = $Response.Content.ReadAsStringAsync().Result
        if (-not $Response.IsSuccessStatusCode) { Write-Error "Groq API error: $Body"; exit 1 }
        $Transcript += $Body.Trim() + " "
    } finally {
        $Client.Dispose()
    }
}

# ── SAVE OUTPUT ───────────────────────────────────────────────────
$Transcript = $Transcript.Trim()
if (-not $Out) { $Out = [System.IO.Path]::ChangeExtension($File, ".txt") }
$Transcript | Out-File $Out -Encoding utf8

Write-Host ""
Write-Host "Done! Saved to: $Out" -ForegroundColor Green
Write-Host ""
Write-Host $Transcript

# ── CLEANUP CHUNKS ────────────────────────────────────────────────
$Chunks | Where-Object { $_ -ne $File } | Remove-Item -ErrorAction SilentlyContinue
