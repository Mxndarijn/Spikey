<#
.SYNOPSIS
  Runs every check. Nothing counts as done until this passes.

.DESCRIPTION
  1. Lint + format check (gdtoolkit; missing gdtoolkit fails the check)
  2. Godot headless import (builds the class cache)
  3. Load every script and scene
  4. Tests: unit, sim purity, golden replays, room rule checks, run side by
     side in -Jobs headless Godot processes (default: one per core, at most 24;
     -Jobs 1 runs them all in one process). No bot plays here (step 6).
  5. FastSim parity: tools/fastsim (the C# copy of sim/) still matches sim/,
     tick for tick, in every room and variant, out of portals, after revives
     and from every sim the checks start from, and its bots and searches
     choose what the GDScript ones do
  6. FastSim checks: every test that plays a bot (searches, PlannerBot, gap
     seeker, random tapper: tools/fastsim/Checks.cs), in -FastSimJobs worker
     processes (default: -Jobs)

  -TestFilter limits step 4 to tests whose "path:method" contains it, and
  step 6 to checks named so or replacing such a test (for example
  "arrival", "variants_passable"); step 5 runs only with no filter or
  "fastsim".

  Godot is found via $env:GODOT, then tools/godot_path.txt, then `godot` on PATH.
  On Windows point it at the *_console.exe build so output shows up.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/check.ps1
  powershell -ExecutionPolicy Bypass -File tools/check.ps1 -TestFilter replay
  powershell -ExecutionPolicy Bypass -File tools/check.ps1 -Jobs 1
  powershell -ExecutionPolicy Bypass -File tools/check.ps1 -Jobs 8 -FastSimJobs 4
#>
param(
    [string]$TestFilter = "",
    [int]$Jobs = 0,
    [int]$FastSimJobs = 0
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
    Write-Host "gdtoolkit not installed: pip install --user `"gdtoolkit==4.*`"" -ForegroundColor Red
    $failed += "lint and format (gdtoolkit not installed)"
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
if ($Jobs -le 0) { $Jobs = [Math]::Min([Environment]::ProcessorCount, 24) }
$testArgs = @("--jobs", $Jobs)
if ($TestFilter) { $testArgs += $TestFilter }
& $godot --headless --path $root -s res://tests/run_tests.gd -- @testArgs
if ($LASTEXITCODE -ne 0) { $failed += "tests" }

# 5. FastSim (the C# copy of sim/ for fast bots) still matches sim/. Skipped
# with a -TestFilter unless the filter is "fastsim".
$hasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
$fastsim = Join-Path $root "tools/fastsim.ps1"
if ($FastSimJobs -le 0) { $FastSimJobs = $Jobs }
if (-not $TestFilter -or $TestFilter -eq "fastsim") {
    Write-Step "FastSim parity"
    if ($hasDotnet) {
        & powershell -ExecutionPolicy Bypass -File $fastsim -Mode parity -Quick -Jobs $FastSimJobs
        if ($LASTEXITCODE -ne 0) { $failed += "fastsim parity (port the sim/ change to tools/fastsim, see PORTING.md)" }
    } else {
        Write-Host "dotnet not installed: install the .NET 9 SDK" -ForegroundColor Red
        $failed += "fastsim parity (dotnet not installed)"
    }
}

# 6. The bot-heavy tests on FastSim (tools/fastsim/Checks.cs). With a
# -TestFilter only the checks it names or whose GD test it matches.
Write-Step "FastSim checks"
if ($hasDotnet) {
    $fa = @("-Mode", "check", "-Jobs", $FastSimJobs)
    if ($TestFilter) { $fa += @("-Filter", $TestFilter) }
    & powershell -ExecutionPolicy Bypass -File $fastsim @fa
    if ($LASTEXITCODE -ne 0) { $failed += "fastsim checks" }
} else {
    Write-Host "dotnet not installed: install the .NET 9 SDK" -ForegroundColor Red
    $failed += "fastsim checks (dotnet not installed)"
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "CHECK FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
exit 0
