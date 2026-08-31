# Local AI Classroom video backend (FFmpeg + Gemini + TTS).
# Does NOT stop the student web-server. Bind 127.0.0.1 only.
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tool\run_classroom_video_backend.ps1
#
# The worker imports Flutter (generated_lesson.dart). Plain `dart run` hits
# an FFI compiler crash on this SDK, so we compile with Flutter's
# frontend_server and execute the dill with flutter_tester.

param(
  [int]$Port = 8791,
  [string]$DefinesFile = 'dart_defines.json'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$flutterRoot = 'D:\flutter\flutter'
$dartBat = Join-Path $flutterRoot 'bin\dart.bat'
if (-not (Test-Path $dartBat)) {
  $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCmd) {
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCmd.Source)
  }
}

$cache = Join-Path $flutterRoot 'bin\cache'
$dartAot = Join-Path $cache 'dart-sdk\bin\dartaotruntime.exe'
$frontend = Join-Path $cache 'artifacts\engine\windows-x64\frontend_server_aot.dart.snapshot'
$sdkRoot = Join-Path $cache 'artifacts\engine\common\flutter_patched_sdk'
$tester = Join-Path $cache 'artifacts\engine\windows-x64\flutter_tester.exe'
$icu = Join-Path $cache 'artifacts\engine\windows-x64\icudtl.dat'
$packages = Join-Path $repoRoot '.dart_tool\package_config.json'
$dill = Join-Path $repoRoot 'build\classroom_video_worker.dill'
$entry = Join-Path $repoRoot 'tool\classroom_video_worker.dart'

foreach ($path in @($dartAot, $frontend, $sdkRoot, $tester, $icu, $packages, $entry)) {
  if (-not (Test-Path $path)) {
    Write-Error "Missing required Flutter/worker file: $path"
  }
}

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

$buildDir = Join-Path $repoRoot 'build'
if (-not (Test-Path $buildDir)) {
  New-Item -ItemType Directory -Path $buildDir | Out-Null
}

Write-Host "Compiling classroom video worker with Flutter frontend_server..."
& $dartAot $frontend `
  --sdk-root $sdkRoot `
  --target=flutter `
  --packages $packages `
  --output-dill $dill `
  $entry
if ($LASTEXITCODE -ne 0) {
  Write-Error "frontend_server compile failed with exit $LASTEXITCODE"
}

Write-Host "Starting classroom video backend on http://127.0.0.1:$Port"
$env:PORT = "$Port"
& $tester --disable-vm-service --icu-data-file-path=$icu --run-forever --non-interactive $dill
