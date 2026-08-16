# Local AI Classroom video backend (FFmpeg + Gemini + TTS).
# Does NOT stop the student web-server. Bind 127.0.0.1 only.
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tool\run_classroom_video_backend.ps1

param(
  [int]$Port = 8791,
  [string]$DefinesFile = 'dart_defines.json'
)

$ErrorActionPreference = 'Stop'
$dart = 'D:\flutter\flutter\bin\dart.bat'
if (-not (Test-Path $dart)) { $dart = 'dart' }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Test-Path $DefinesFile)) {
  Write-Error "Missing $DefinesFile - copy dart_defines.json.example and fill keys."
}

$ffmpeg = Join-Path $repoRoot '.tools\ffmpeg\ffmpeg.exe'
if (-not (Test-Path $ffmpeg)) {
  Write-Warning "FFmpeg not found at .tools\ffmpeg\ffmpeg.exe"
}

Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object {
    if ($_) {
      Write-Host "Freeing port $Port (PID $_)"
      Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
  }

Write-Host "Starting classroom video backend on http://127.0.0.1:$Port"
$env:PORT = "$Port"
& $dart run tool/classroom_video_worker.dart
