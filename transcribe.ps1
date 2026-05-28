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

# ── GROQ KEY ────────────────────────────────────────────────────
if (Test-Path $ConfigFile) {
    $ApiKey = Get-Content $ConfigFile -Raw
} else {
    $ApiKey = Read-Host "Enter your Groq API key (saved to $ConfigFile)"
    $ApiKey | Out-File $ConfigFile -Encoding utf8 -NoNewline
}
$ApiKey = $ApiKey.Trim()

# ── FFMPEG CHECK ─────────────────────────────────────────────────
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "ffmpeg not found. Installing via winget..." -ForegroundColor Yellow
    winget install --id Gyan.FFmpeg -e --silent
    $env:PATH += ";C:\Program Files\ffmpeg\bin"
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Error "ffmpeg install failed. Install manually from https://ffmpeg.org/download.html"
        exit 1
    }
}

# ── VALIDATE INPUT ────────────────────────────────────────────────
$File = Resolve-Path $File -ErrorAction Stop | Select-Object -ExpandProperty Path
if (-not (Test-Path $File)) { Write-Error "File not found: $File"; exit 1 }

# ── EXTRACT AUDIO ─────────────────────────────────────────────────
$Tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".wav")
Write-Host "Extracting audio..." -ForegroundColor Cyan
ffmpeg -y -i $File -ar 16000 -ac 1 -c:a pcm_s16le $Tmp -loglevel error
if ($LASTEXITCODE -ne 0) { Write-Error "ffmpeg failed to extract audio."; exit 1 }

# ── CHUNK IF TOO LARGE ────────────────────────────────────────────
$FileSize = (Get-Item $Tmp).Length
$Chunks = @()

if ($FileSize -gt $MaxBytes) {
    Write-Host "File is large ($([math]::Round($FileSize/1MB,1)) MB), splitting into chunks..." -ForegroundColor Yellow
    $Duration  = [double](ffmpeg -i $Tmp 2>&1 | Select-String "Duration" | ForEach-Object { $_ -replace ".*Duration: (\d+):(\d+):([\d.]+).*", '$1*3600+$2*60+$3' } | Invoke-Expression)
    $ChunkSecs = [math]::Floor($Duration * $MaxBytes / $FileSize) - 5
    $i = 0
    for ($Start = 0; $Start -lt $Duration; $Start += $ChunkSecs) {
        $ChunkFile = "$env:TEMP\chunk_$i.wav"
        ffmpeg -y -i $Tmp -ss $Start -t $ChunkSecs $ChunkFile -loglevel error
        $Chunks += $ChunkFile
        $i++
    }
} else {
    $Chunks = @($Tmp)
}

# ── TRANSCRIBE ────────────────────────────────────────────────────
$Transcript = ""
$Total = $Chunks.Count
for ($i = 0; $i -lt $Total; $i++) {
    $Chunk = $Chunks[$i]
    if ($Total -gt 1) { Write-Host "Transcribing chunk $($i+1)/$Total..." -ForegroundColor Cyan }
    else               { Write-Host "Transcribing..." -ForegroundColor Cyan }

    $Form = [System.Net.Http.MultipartFormDataContent]::new()
    $Form.Add([System.Net.Http.StringContent]::new("whisper-large-v3-turbo"), "model")
    $Form.Add([System.Net.Http.StringContent]::new($Lang), "language")
    $Form.Add([System.Net.Http.StringContent]::new("text"), "response_format")
    $Bytes   = [System.IO.File]::ReadAllBytes($Chunk)
    $Content = [System.Net.Http.ByteArrayContent]::new($Bytes)
    $Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("audio/wav")
    $Form.Add($Content, "file", [System.IO.Path]::GetFileName($Chunk))

    $Client = [System.Net.Http.HttpClient]::new()
    $Client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $ApiKey)

    try {
        $Response = $Client.PostAsync("https://api.groq.com/openai/v1/audio/transcriptions", $Form).Result
        $Body = $Response.Content.ReadAsStringAsync().Result
        if (-not $Response.IsSuccessStatusCode) {
            Write-Error "Groq API error: $Body"
            exit 1
        }
        $Transcript += $Body.Trim() + " "
    } finally {
        $Client.Dispose()
    }
}

# ── SAVE OUTPUT ───────────────────────────────────────────────────
$Transcript = $Transcript.Trim()

if (-not $Out) {
    $Out = [System.IO.Path]::ChangeExtension($File, ".txt")
}
$Transcript | Out-File $Out -Encoding utf8
Write-Host ""
Write-Host "Done! Transcript saved to: $Out" -ForegroundColor Green
Write-Host ""
Write-Host $Transcript

# ── CLEANUP ───────────────────────────────────────────────────────
Remove-Item $Tmp -ErrorAction SilentlyContinue
$Chunks | Where-Object { $_ -ne $Tmp } | Remove-Item -ErrorAction SilentlyContinue
