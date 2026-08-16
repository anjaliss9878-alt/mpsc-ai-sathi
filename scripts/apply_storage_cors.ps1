# Applies Web CORS to the Firebase Storage bucket so Flutter Web uploads
# from localhost / custom origins are not blocked by the browser.
#
# Prerequisites: Google Cloud SDK (gsutil) installed and authenticated.
#   https://cloud.google.com/sdk/docs/install
#
# Usage (from repo root):
#   .\scripts\apply_storage_cors.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$corsFile = Join-Path $repoRoot 'cors.json'
$buckets = @(
  'gs://mpsc-3f4ef.firebasestorage.app',
  'gs://mpsc-3f4ef.appspot.com'
)

if (-not (Get-Command gsutil -ErrorAction SilentlyContinue)) {
  Write-Error 'gsutil not found. Install Google Cloud SDK, run "gcloud auth login", then retry.'
}

if (-not (Test-Path $corsFile)) {
  Write-Error "Missing cors.json at $corsFile"
}

$applied = $false
foreach ($bucket in $buckets) {
  Write-Host "Trying CORS on $bucket ..."
  & gsutil cors set $corsFile $bucket
  if ($LASTEXITCODE -eq 0) {
    Write-Host "CORS applied to $bucket"
    & gsutil cors get $bucket
    $applied = $true
    break
  }
}

if (-not $applied) {
  Write-Error 'Failed to apply CORS. Enable Firebase Storage first, then re-run.'
}
