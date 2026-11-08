<#
.SYNOPSIS
  Runs every check. Nothing counts as done until this passes.

.DESCRIPTION
  1. Lint + format check (gdtoolkit; skipped with a warning if not installed)
  2. Godot headless import (builds the class cache)
  3. Load every script and scene
  4. Tests: unit, sim purity, golden replays, bot simulations

  Godot is found via $env:GODOT, then tools/godot_path.txt, then `godot` on PATH.
  On Windows point it at the *_console.exe build so output shows up.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/check.ps1
  powershell -ExecutionPolicy Bypass -File tools/check.ps1 -TestFilter replay
#>
param(
    [string]$TestFilter = ""
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$failed = @()

function Write-Step($name) { Write-Host "`n== $name ==" -ForegroundColor Cyan }

function Resolve-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) {
        $p = (Get-Content $file -TotalCount 1).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$godot = Resolve-Godot
if (-not $godot) {
    Write-Host "Godot not found. Set `$env:GODOT or write its path to tools/godot_path.txt." -ForegroundColor Red
    exit 2
}
Write-Host "Godot: $godot"
$gdDirs = @("sim", "game", "meta", "services", "tests", "tools", "server") | ForEach-Object { Join-Path $root $_ }

# 1. Lint + format
Write-Step "Lint and format"
function Resolve-Tool($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # pip install --user puts scripts in a folder that is often not on PATH.
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $dir = & $py.Source -c "import sysconfig,os; print(sysconfig.get_path('scripts', os.name + '_user'))" 2>$null
        if ($dir) {
            $exe = Join-Path $dir.Trim() "$name.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    return $null
}
$gdlint = Resolve-Tool "gdlint"
$gdformat = Resolve-Tool "gdformat"
if ($gdlint -and $gdformat) {
    & $gdlint @gdDirs
    if ($LASTEXITCODE -ne 0) { $failed += "lint" }
    & $gdformat --check --line-length 100 @gdDirs
    if ($LASTEXITCODE -ne 0) { $failed += "format (run: gdformat --line-length 100 sim game meta services tests tools server)" }
} else {
    Write-Host "SKIPPED: gdtoolkit not installed (pip install --user `"gdtoolkit==4.*`")" -ForegroundColor Yellow
}

# 2. Import
Write-Step "Import"
& $godot --headless --path $root --import 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $failed += "import" } else { Write-Host "ok" }

# 3. Load everything
Write-Step "Load all scripts and scenes"
& $godot --headless --path $root -s res://tools/ci/load_all.gd
if ($LASTEXITCODE -ne 0) { $failed += "load" }

# 4. Tests
Write-Step "Tests"
if ($TestFilter) {
    & $godot --headless --path $root -s res://tests/run_tests.gd -- $TestFilter
} else {
    & $godot --headless --path $root -s res://tests/run_tests.gd
}
if ($LASTEXITCODE -ne 0) { $failed += "tests" }

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "CHECK FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
exit 0
