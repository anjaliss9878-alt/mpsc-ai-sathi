# Starts the local AI lesson/TTS/render worker only when it is not healthy.
# Used by the recommended VS Code Student launch configuration.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host 'Ensuring AI classroom worker'

$portOpen = $false
try {
  $tcp = [System.Net.Sockets.TcpClient]::new()
  $connect = $tcp.ConnectAsync('127.0.0.1', 8791)
  $portOpen = $connect.Wait(2000) -and $tcp.Connected
  $tcp.Dispose()
} catch {
  $portOpen = $false
}
if ($portOpen) {
  Write-Host 'AI classroom worker already ready'
  exit 0
}

try {
  $health = Invoke-WebRequest `
    -Uri 'http://127.0.0.1:8791/health' `
    -UseBasicParsing `
    -TimeoutSec 2
  if ($health.StatusCode -eq 200 -and "$($health.Content)" -match '"ok"\s*:\s*true') {
    Write-Host 'AI classroom worker already ready'
    exit 0
  }
} catch {
  # The worker is not running; start it below.
}

& (Join-Path $PSScriptRoot 'run_classroom_video_backend.ps1')
