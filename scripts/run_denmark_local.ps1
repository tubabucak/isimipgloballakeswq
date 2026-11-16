# Local test with the 40 Danish lakes (example_climate/, 1991-2000):
# step 2 in parallel, then step 3 for both nutrient sets and all models.
#
#   powershell -ExecutionPolicy Bypass -File scripts\run_denmark_local.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\run_denmark_local.ps1 -Cores 20 -Rscript "D:\R\R-4.6.0\bin\Rscript.exe"
#
#   powershell -ExecutionPolicy Bypass -File scripts\run_denmark_local.ps1 -OutputOnly
#
# Deletes runs/, isimip_global/ and logs/ of earlier tests first (not with
# -OutputOnly, which only writes the ISIMIP files from the saved metrics.rds).

param(
  [int]$Cores = 34,
  [string]$Rscript = "",      # default: newest R in %LOCALAPPDATA%\Programs\R or Program Files\R
  [string]$ForcingDir = "",   # default: <project>\example_climate
  [string]$HypsoNc = "",      # default: <project>\..\ISIMIP4\hypso_area.nc
  [switch]$OutputOnly         # step 3 only, from the metrics.rds of an earlier run
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
Set-Location $project

if ($Rscript -eq "") {
  $r = Get-ChildItem "$env:LOCALAPPDATA\Programs\R\R-*", "$env:ProgramFiles\R\R-*" -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -replace "^R-", "") } | Select-Object -Last 1
  if ($null -eq $r) { throw "No R found; pass -Rscript" }
  $Rscript = Join-Path $r.FullName "bin\Rscript.exe"
}
Write-Host "Using $Rscript"
if ($ForcingDir -eq "") { $ForcingDir = Join-Path $project "example_climate" }
if ($HypsoNc -eq "") { $HypsoNc = Join-Path (Split-Path -Parent $project) "ISIMIP4\hypso_area.nc" }
foreach ($p in @($Rscript, $ForcingDir, $HypsoNc)) {
  if (-not (Test-Path $p)) { throw "Not found: $p" }
}
$env:ISIMIP_FORCING_DIR = $ForcingDir
$env:ISIMIP_HYPSO_NC = $HypsoNc

$rows = @(25472, 25473, 25474, 25475, 25476, 25477, 25478, 25479,
          25824, 25825, 25826, 25827, 25828, 25829, 25830, 25831,
          26161, 26162, 26163, 26164, 26165, 26166, 26167, 26168,
          26497, 26498, 26499, 26500, 26501, 26502, 26503, 26504,
          26849, 26850, 26851, 26852, 26853, 27197, 27198, 27199)

$ErrorActionPreference = "Continue"   # R writes messages to stderr

# ---- Step 2: run the lakes, $Cores at a time ------------------------------
if (-not $OutputOnly) {
  foreach ($d in @("runs", "isimip_global", "logs")) {
    if (Test-Path $d) { Remove-Item -Recurse -Force $d }
  }
  $start = Get-Date
  Write-Host "Running $($rows.Count) lakes on $Cores cores ($start)"
  & $Rscript scripts/run_local.R $Cores @rows
  Write-Host ("Step 2 took {0:N0} min" -f ((Get-Date) - $start).TotalMinutes)
}

# ---- Step 3: ISIMIP files (all Danish lakes have inflow: no default set) --
foreach ($set in @("lownutr", "highnutr")) {
  foreach ($model in @("GLM", "WET", "SELMAPROTBAS", "SIMSTRAT")) {
    Write-Host "ISIMIP output: $set / $model"
    & $Rscript scripts/03_isimip_output.R $set $model
  }
}

Write-Host "Logs: runs\obsclim\gswp3-era5\logs\task_test_*.csv and logs\local_<row>.out"
Write-Host "Files: isimip_global\obsclim\gswp3-era5\"
