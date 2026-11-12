<#
.SYNOPSIS
  Runs every check. Nothing counts as done until this passes.

.DESCRIPTION
  1. Lint + format check (gdtoolkit; missing gdtoolkit fails the check)
  2. Godot headless import (builds the class cache)
  3. Load every script and scene
  4. Tests: unit, sim purity, golden replays, room rule checks, run side by
     side in -Jobs headless Godot processes (default: one per core, at most 8:
     more only adds Godot start-ups now that no bot plays here;
     -Jobs 1 runs them all in one process). No bot plays here (step 6).
  5. FastSim parity: tools/fastsim (the C# copy of sim/) still matches sim/,
     tick for tick, in every room and variant, out of portals, after revives
     and from every sim the checks start from, and its bots and searches
     choose what the GDScript ones do
  5b. FastSim-RS parity: tools/fastsim-rs (the Rust copy, docs/FASTSIM_RS.md)
     replays the same recording; skipped cleanly when cargo is not installed
  6. FastSim checks: every test that plays a bot (searches, PlannerBot, gap
     seeker, random tapper: tools/fastsim/Checks.cs), in -FastSimJobs worker
     processes

  The steps run side by side where they can: lint, format and the FastSim
  checks (which need no Godot) start at once; once the import is done, the
  tests, the load step and the parity recording run together. Each step's
  output is shown under its own heading, in the order above. The tests get
  -Jobs Godot processes; the others add a few processes at below-normal
  priority (-FastSimJobs, default half of -Jobs, for the FastSim checks; two
  for the parity recording).

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
$clock = [Diagnostics.Stopwatch]::StartNew()

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

# Background steps: each a process whose output goes to files, shown once it
# is done (Show-Step).
$logDir = Join-Path ([IO.Path]::GetTempPath()) "flapjaw_check_$PID"
New-Item -ItemType Directory -Force $logDir | Out-Null
$steps = @{}

function Start-Step($key, $file, [string[]]$argList) {
    $quoted = $argList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
    $out = Join-Path $logDir "$key.out.txt"
    $err = Join-Path $logDir "$key.err.txt"
    $p = Start-Process -FilePath $file -ArgumentList $quoted -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    # Windows PowerShell only keeps the exit code if the handle was read.
    $null = $p.Handle
    $steps[$key] = @{ Process = $p; Out = $out; Err = $err; Clock = [Diagnostics.Stopwatch]::StartNew() }
}

function Set-BelowNormal($key) {
    try { $steps[$key].Process.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
}

# Waits for a background step, prints its output and returns its exit code.
# Its stderr is shown only when it failed (Godot prints harmless leak
# warnings there at exit).
function Show-Step($key) {
    $s = $steps[$key]
    $s.Process.WaitForExit()
    $code = $s.Process.ExitCode
    $lines = @(Get-Content $s.Out -ErrorAction SilentlyContinue)
    if ($code -ne 0) { $lines += @(Get-Content $s.Err -ErrorAction SilentlyContinue) }
    foreach ($l in $lines) { Write-Host $l }
    return $code
}

$godot = Resolve-Godot
if (-not $godot) {
    Write-Host "Godot not found. Set `$env:GODOT or write its path to tools/godot_path.txt." -ForegroundColor Red
    exit 2
}
Write-Host "Godot: $godot"
$gdDirs = @("sim", "game", "meta", "services", "tests", "tools", "server") | ForEach-Object { Join-Path $root $_ }
if ($Jobs -le 0) { $Jobs = [Math]::Min([Environment]::ProcessorCount, 8) }
if ($FastSimJobs -le 0) { $FastSimJobs = [Math]::Max(2, [int]($Jobs / 2)) }
$fastsim = Join-Path $root "tools/fastsim.ps1"
$runParity = -not $TestFilter -or $TestFilter -eq "fastsim"

# FastSim is built once, here, so parity and the checks can share it.
$hasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
$fastsimBuilt = $false
if ($hasDotnet) {
    & dotnet build (Join-Path $root "tools/fastsim/FastSim.csproj") -c Release -nologo -v q | Out-Null
    $fastsimBuilt = $LASTEXITCODE -eq 0
}

# FastSim-RS (the Rust copy, docs/FASTSIM_RS.md): built here too; no cargo = skipped.
$fastsimRs = Join-Path $root "tools/fastsim-rs"
$cargoBin = Join-Path $env:USERPROFILE ".cargoin"
if (Test-Path $cargoBin) { $env:Path = "$cargoBin;" + $env:Path }
$hasCargo = [bool](Get-Command cargo -ErrorAction SilentlyContinue)
$fastsimRsBuilt = $false
if ($hasCargo -and $runParity) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $fastsimRs "build.ps1") -NoSlot 2>&1 | Out-Null
    $fastsimRsBuilt = $LASTEXITCODE -eq 0
}

# 1 and 6 start now: they need no Godot.
$gdlint = Resolve-Tool "gdlint"
$gdformat = Resolve-Tool "gdformat"
if ($gdlint -and $gdformat) {
    Start-Step "lint" $gdlint $gdDirs
    Start-Step "format" $gdformat (@("--check", "--line-length", "100") + $gdDirs)
}
if ($fastsimBuilt) {
    $fa = @("-ExecutionPolicy", "Bypass", "-File", $fastsim, "-Mode", "check", "-NoBuild", "-Jobs", $FastSimJobs)
    if ($TestFilter) { $fa += @("-Filter", $TestFilter) }
    Start-Step "checks" "powershell" $fa
}

# 2. Import (everything below that runs Godot needs it).
$sw = [Diagnostics.Stopwatch]::StartNew()
& $godot --headless --path $root --import 2>&1 | Out-Null
$importOk = $LASTEXITCODE -eq 0
$importTime = $sw.Elapsed.TotalSeconds

# 3 and 5 run beside the tests.
if ($importOk) {
    Start-Step "load" $godot @("--headless", "--path", $root, "-s", "res://tools/ci/load_all.gd")
    Set-BelowNormal "load"
    if ($runParity -and $fastsimBuilt) {
        Start-Step "parity" "powershell" @("-ExecutionPolicy", "Bypass", "-File", $fastsim, "-Mode", "parity", "-Quick", "-NoBuild", "-Jobs", "2")
        Set-BelowNormal "parity"
    }
    if ($runParity -and $fastsimRsBuilt) {
        Start-Step "parity-rs" "powershell" @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $fastsimRs "parity.ps1"), "-Quick", "-NoBuild", "-Jobs", "2")
        Set-BelowNormal "parity-rs"
    }
}

# 1. Lint + format
Write-Step "Lint and format"
if ($gdlint -and $gdformat) {
    if ((Show-Step "lint") -ne 0) { $failed += "lint" }
    if ((Show-Step "format") -ne 0) { $failed += "format (run: gdformat --line-length 100 sim game meta services tests tools server)" }
} else {
    Write-Host "gdtoolkit not installed: pip install --user `"gdtoolkit==4.*`"" -ForegroundColor Red
    $failed += "lint and format (gdtoolkit not installed)"
}

# 2. Import
Write-Step "Import"
if ($importOk) { Write-Host ("ok ({0:F0} s)" -f $importTime) } else { $failed += "import" }

# 4. Tests, shown as they run.
Write-Step "Tests"
if ($importOk) {
    $testArgs = @("--jobs", $Jobs)
    if ($TestFilter) { $testArgs += $TestFilter }
    & $godot --headless --path $root -s res://tests/run_tests.gd -- @testArgs
    if ($LASTEXITCODE -ne 0) { $failed += "tests" }
} else {
    Write-Host "skipped: the import failed" -ForegroundColor Red
}

# 3. Load everything
Write-Step "Load all scripts and scenes"
if ($importOk) {
    if ((Show-Step "load") -ne 0) { $failed += "load" }
} else {
    Write-Host "skipped: the import failed" -ForegroundColor Red
}

# 5. FastSim (the C# copy of sim/ for fast bots) still matches sim/.
if ($runParity) {
    Write-Step "FastSim parity"
    if (-not $hasDotnet) {
        Write-Host "dotnet not installed: install the .NET 9 SDK" -ForegroundColor Red
        $failed += "fastsim parity (dotnet not installed)"
    } elseif (-not $fastsimBuilt) {
        & dotnet build (Join-Path $root "tools/fastsim/FastSim.csproj") -c Release -nologo -v q
        $failed += "fastsim parity (FastSim build failed)"
    } elseif ($steps.ContainsKey("parity")) {
        if ((Show-Step "parity") -ne 0) { $failed += "fastsim parity (port the sim/ change to tools/fastsim, see PORTING.md)" }
    } else {
        Write-Host "skipped: the import failed" -ForegroundColor Red
        $failed += "fastsim parity (skipped)"
    }
}

# 5b. FastSim-RS (the Rust copy) matches sim/ too. No cargo: skipped, not failed.
if ($runParity) {
    Write-Step "FastSim-RS parity"
    if (-not $hasCargo) {
        Write-Host "skipped: cargo not installed (tools/fastsim-rs, docs/FASTSIM_RS.md)" -ForegroundColor Yellow
    } elseif (-not $fastsimRsBuilt) {
        & powershell -ExecutionPolicy Bypass -File (Join-Path $fastsimRs "build.ps1") -NoSlot
        $failed += "fastsim-rs parity (FastSim-RS build failed)"
    } elseif ($steps.ContainsKey("parity-rs")) {
        if ((Show-Step "parity-rs") -ne 0) { $failed += "fastsim-rs parity (port the sim/ change to tools/fastsim-rs, see docs/FASTSIM_RS.md)" }
    } else {
        Write-Host "skipped: the import failed" -ForegroundColor Red
        $failed += "fastsim-rs parity (skipped)"
    }
}

# 6. Every bot test, on FastSim (tools/fastsim/Checks.cs). With a
# -TestFilter only the checks it names or whose old test it matches.
Write-Step "FastSim checks"
if (-not $hasDotnet) {
    Write-Host "dotnet not installed: install the .NET 9 SDK" -ForegroundColor Red
    $failed += "fastsim checks (dotnet not installed)"
} elseif (-not $fastsimBuilt) {
    $failed += "fastsim checks (FastSim build failed)"
} else {
    if ((Show-Step "checks") -ne 0) { $failed += "fastsim checks" }
}

Remove-Item -Recurse -Force $logDir -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("Check took {0:F0} s" -f $clock.Elapsed.TotalSeconds)
if ($failed.Count -gt 0) {
    Write-Host "CHECK FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
exit 0
