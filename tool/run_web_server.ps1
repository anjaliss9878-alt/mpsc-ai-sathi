# Low-RAM Flutter Web launcher (4 GB laptops).
# Root cause of Chrome failure: DWDS WebkitDebugger.enable TimeoutException -
# Chrome DevTools debug attach is slow/unreliable under memory pressure.
# This script uses -d web-server (no Chrome DWDS handshake).
#
# IMPORTANT: Keep this file ASCII-only. Windows PowerShell parses .ps1 as
# system ANSI (CP1252); UTF-8 em-dashes/approx signs decode into stray quotes
# and cause "string is missing the terminator".
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tool\run_web_server.ps1
#   powershell -ExecutionPolicy Bypass -File tool\run_web_server.ps1 -Port 8080

param(
  [int]$Port = 8080,
  [string]$Hostname = 'localhost',
  [string]$Target = 'lib/main.dart',
  [string]$DefinesFile = 'dart_defines.json'
)

$ErrorActionPreference = 'Stop'
$flutter = 'D:\flutter\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Test-Path $DefinesFile)) {
  Write-Error "Missing $DefinesFile - copy dart_defines.json.example and fill keys."
}

# Free RAM: stop leftover Flutter web sessions and Flutter-owned Chrome profiles.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {
    ($_.Name -match 'dart|flutter') -or
    ($_.Name -eq 'chrome.exe' -and $_.CommandLine -match 'flutter_tools_chrome|flutter_chrome_debug|remote-debugging-port')
  } |
  ForEach-Object {
    Write-Host "Stopping leftover PID $($_.ProcessId) ($($_.Name))"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

# Free the target port if something else holds it.
Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object {
    if ($_) {
      Write-Host "Freeing port $Port (PID $_)"
      Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
  }

Start-Sleep -Seconds 1

$os = Get-CimInstance Win32_OperatingSystem
$freeMb = [math]::Round($os.FreePhysicalMemory / 1024, 0)
Write-Host "Free RAM ~= ${freeMb} MB"
if ($freeMb -lt 800) {
  Write-Warning "Low free RAM (<800 MB). Close Chrome/Edge tabs before continuing."
}

Write-Host ""
$url = 'http://' + $Hostname + ':' + $Port
Write-Host "Starting Flutter web-server at $url"
Write-Host 'Do NOT use: flutter run -d chrome  (DWDS WebkitDebugger.enable times out on 4GB)'
Write-Host "Open the URL only after you see: is being served at $url"
Write-Host ""

& $flutter run -d web-server -t $Target `
  --dart-define-from-file=$DefinesFile `
  --web-hostname=$Hostname `
  --web-port=$Port `
  --no-web-resources-cdn
