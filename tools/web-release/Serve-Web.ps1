[CmdletBinding()]
param(
  [string]$Root,
  [ValidateRange(1024,65535)][int]$Port=8485,
  [ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [switch]$OpenBrowser
)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root=Join-Path $PSScriptRoot 'site' }
$staticRoot=[IO.Path]::GetFullPath($Root).TrimEnd('\')
if (!(Test-Path -LiteralPath (Join-Path $staticRoot 'index.html'))) { throw 'WEB_BUILD_REQUIRED' }
$ref=if ($ProjectRef) { $ProjectRef } else { (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-identity.json') -Raw | ConvertFrom-Json).projectRef }
if ($ref -notmatch '^[a-z0-9]{20}$') { throw 'PUBLIC_PROJECT_REFERENCE_REQUIRED' }
$server=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$Port)
$mime=@{'.html'='text/html; charset=utf-8';'.js'='text/javascript; charset=utf-8';'.mjs'='text/javascript; charset=utf-8';'.json'='application/json';'.wasm'='application/wasm';'.png'='image/png';'.svg'='image/svg+xml';'.ico'='image/x-icon';'.ttf'='font/ttf';'.otf'='font/otf';'.woff2'='font/woff2';'.css'='text/css; charset=utf-8';'.bin'='application/octet-stream'}
$csp="default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://$ref.supabase.co; font-src 'self' data:; connect-src 'self' https://$ref.supabase.co wss://$ref.supabase.co; worker-src 'self' blob:; frame-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
try {
  $server.Start()
  $address="http://127.0.0.1:$Port/"
  Write-Output "Jentra OS Development web app: $address"
  Write-Output 'Loopback only. Close this window to stop. Company account required; no backend is installed by this server.'
  if ($OpenBrowser) { Start-Process $address | Out-Null }
  while ($true) {
    $client=$server.AcceptTcpClient()
    $stream=$null
    try {
      $client.ReceiveTimeout=5000
      $client.SendTimeout=15000
      $stream=$client.GetStream()
      $request=New-Object Text.StringBuilder
      while ($request.Length -lt 16384) {
        $next=$stream.ReadByte()
        if ($next -lt 0) { break }
        [void]$request.Append([char]$next)
        if ($request.ToString().EndsWith("`r`n`r`n")) { break }
      }
      $lines=$request.ToString().Split(@("`r`n"),[StringSplitOptions]::None)
      $parts=$lines[0].Split(' ')
      $status='200 OK'
      $type='text/plain; charset=utf-8'
      $body=[Text.Encoding]::UTF8.GetBytes('Request not supported')
      if ($parts.Length -ne 3 -or $parts[0] -notin @('GET','HEAD') -or !$parts[1].StartsWith('/')) {
        $status='405 Method Not Allowed'
      } elseif (@($lines | Where-Object { $_ -match '^Host:\s*(127\.0\.0\.1|localhost):' + $Port + '\s*$' }).Count -ne 1) {
        $status='400 Bad Request'
      } else {
        $relative=[Uri]::UnescapeDataString(($parts[1] -split '\?',2)[0]).TrimStart('/').Replace('/','\')
        $path=if ([string]::IsNullOrEmpty($relative)) { Join-Path $staticRoot 'index.html' } else { [IO.Path]::GetFullPath((Join-Path $staticRoot $relative)) }
        if (!$path.StartsWith($staticRoot+'\',[StringComparison]::OrdinalIgnoreCase)) {
          $status='403 Forbidden'
        } else {
          if (!(Test-Path -LiteralPath $path -PathType Leaf) -and [string]::IsNullOrEmpty([IO.Path]::GetExtension($path))) { $path=Join-Path $staticRoot 'index.html' }
          if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            $status='404 Not Found'
            $body=[Text.Encoding]::UTF8.GetBytes('File not found')
          } else {
            $body=[IO.File]::ReadAllBytes($path)
            $extension=[IO.Path]::GetExtension($path).ToLowerInvariant()
            $type=if ($mime.ContainsKey($extension)) { $mime[$extension] } else { 'application/octet-stream' }
          }
        }
      }
      $headers="HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nX-Frame-Options: DENY`r`nReferrer-Policy: no-referrer`r`nContent-Security-Policy: $csp`r`nConnection: close`r`n`r`n"
      $headerBytes=[Text.Encoding]::UTF8.GetBytes($headers)
      $stream.Write($headerBytes,0,$headerBytes.Length)
      if ($parts[0] -ne 'HEAD') { $stream.Write($body,0,$body.Length) }
      $stream.Flush()
    } catch {
      # A closed browser request must not stop other static requests. Neither
      # request URLs/bodies nor account data are written to the console.
    } finally {
      if ($stream) { $stream.Dispose() }
      $client.Close()
    }
  }
} finally { $server.Stop() }
