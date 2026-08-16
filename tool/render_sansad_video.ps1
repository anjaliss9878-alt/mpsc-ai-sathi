# Renders the premium ~2-minute संसद AI teaching MP4 via Canvas + Cloud TTS + FFmpeg.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutter = 'D:\flutter\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

if (-not (Test-Path '.tools\ffmpeg\ffmpeg.exe')) {
  Write-Error 'Missing .tools\ffmpeg\ffmpeg.exe'
}
if (-not (Test-Path 'dart_defines.json')) {
  Write-Error 'Missing dart_defines.json (Google Cloud TTS credentials required).'
}

Write-Host 'Rendering संसद premium MP4 (Canvas + TTS + FFmpeg)...'
& $flutter test tool/render_sansad_video.dart --dart-define-from-file=dart_defines.json
$code = $LASTEXITCODE

$asset = Join-Path $root 'assets\rendered_videos\sansad_2min.mp4'
if (Test-Path $asset) {
  Write-Host "OK asset: $asset"
  Get-Item $asset | Format-List FullName, Length, LastWriteTime
} else {
  Write-Warning 'assets/rendered_videos/sansad_2min.mp4 not found yet — check print RENDERED_OK path above.'
}
exit $code
