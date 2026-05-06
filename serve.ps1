$port = 3000
$root = $PSScriptRoot
$prefix = "http://localhost:$port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Output "Serving $root on $prefix"
$mimeTypes = @{
  '.html'=  'text/html; charset=utf-8'
  '.js'  =  'application/javascript'
  '.css' =  'text/css'
  '.json'=  'application/json'
  '.png' =  'image/png'
  '.jpg' =  'image/jpeg'
  '.svg' =  'image/svg+xml'
  '.ico' =  'image/x-icon'
  '.webp'=  'image/webp'
  '.woff2'= 'font/woff2'
}
while ($listener.IsListening) {
  $ctx  = $listener.GetContext()
  $req  = $ctx.Request
  $resp = $ctx.Response
  $path = $req.Url.LocalPath -replace '^/+',''
  if ($path -eq '' -or $path -eq '/') { $path = 'index.html' }
  $file = Join-Path $root $path
  if (-not (Test-Path $file -PathType Leaf)) { $file = Join-Path $root 'index.html' }
  try {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $ext   = [System.IO.Path]::GetExtension($file).ToLower()
    $resp.ContentType   = if ($mimeTypes[$ext]) { $mimeTypes[$ext] } else { 'application/octet-stream' }
    $resp.ContentLength64 = $bytes.Length
    $resp.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
    $resp.StatusCode = 500
  }
  $resp.Close()
}
