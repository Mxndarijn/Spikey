# Playtest sweeps on FastSim, the C# copy of the sim (tools/fastsim). Same
# modes, seeds and JSON as tools/sweep.ps1, but native code: roughly 50 times
# faster per core. Needs the .NET SDK (dotnet); no Godot window, no Godot run
# except for the parity check.
#
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1                         # search, every room, 64 seeds
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Seeds 1024 -Room sawring
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode searchruns -Seeds 256 -Ticks 16000
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode runs -Seeds 200   # PlannerBot
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode parity            # check it still matches sim/
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode reaction          # reaction benchmark, 60 arrivals per room
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode odds -Seeds 360   # survival by reaction time in real runs
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode combos            # Double Trouble fairness gate, every pair
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode parity -Quick     # faster, fewer cases
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check             # the check's bot tests (Checks.cs)
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check -Check arrival,revive -Filter revive
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Room bramble -Variant twin    # one variant
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Room bramble -Variant all     # each variant
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode runfile -Seed 7 -Out run.json  # a bot run as a run file
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode difficulty -Room gates -Out d.tsv   # difficulty measures
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode difficulty -Step score -In d.tsv -Out report
#
# -Mode difficulty (docs/ROOM_DIFFICULTY.md): -Step list|measure|show|score.
#   measure: -What tube,react,bots (default all three), -Room ids or room/variant
#   (comma list, default every room), -Seeds room entries per room (default 16),
#   -Bots (default beginner,normal,good,expert,beast,honest), -Out a TSV (rows
#   already there are kept: a stopped run carries on). score: -In TSVs, -Out a
#   report name (writes .md and .json).
#
# -Variant (search, rooms, reaction): play that room variant id instead of the
#   one the RNG draws ("all": each variant of each matching room in turn, one
#   report line "room/variant" each). The draw still happens, so the rest of
#   the run's RNG is as in a normal run. Without -Variant nothing changes.
#
# -Mode check: the bot-heavy tests of tools/check.ps1, ported from their
#   GDScript tests (which keep a small sample) with the same rules and more
#   seeds: passable, arrival, points, revive, pairs (tools/fastsim/Checks.cs).
#   -Check picks some (comma list, default all); -Filter keeps those whose name
#   or GD test "path:method" contains it, as tools/check.ps1 -TestFilter.
#   Exits 1 with the failures listed.
#
# -Jobs: worker processes (default: a quarter of the cores, so the PC stays usable).
#
# The C# sim must match sim/ exactly. After any change in sim/, run -Mode
# parity: it records runs in (headless) Godot and replays them in C#, and
# names the first tick that differs. Port the change (tools/fastsim/PORTING.md)
# until it passes.
param(
    [ValidateSet("search", "searchruns", "rooms", "runs", "parity", "bench", "reaction", "odds", "combos", "check", "runfile", "difficulty")]
    [string]$Mode = "search",
    [int]$Seeds = 0,
    [string]$Room = "*",
    [string]$Variant = "",
    # check: which checks (comma list) and a -TestFilter style filter.
    [string]$Check = "all",
    [string]$Filter = "",
    [int]$Ticks = 0,
    # reaction / odds: reaction times to play, in ticks ("0,60").
    [string]$Delays = "",
    [int]$Jobs = 0,
    [ValidateSet("Idle", "BelowNormal", "Normal")]
    [string]$Priority = "BelowNormal",
    [string]$Out = "",
    # runfile: the run's seed (the bot's seed is -Seeds, default 1).
    [long]$Seed = 1,
    [switch]$Quick,
    # difficulty: the step, the measures, the bots and the input TSVs.
    [string]$Step = "measure",
    [string]$What = "tube,react,bots",
    [string]$Bots = "",
    [string]$In = "",
    # Use the FastSim already built (tools/check.ps1 builds once, then runs
    # parity and the checks side by side).
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "tools/fastsim/FastSim.csproj"
# FastSim.exe on Windows, FastSim elsewhere (CI runs on Linux).
$exe = Join-Path $root "tools/fastsim/bin/Release/net9.0/FastSim"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "dotnet not found: install the .NET 9 SDK to use FastSim." -ForegroundColor Red
    exit 2
}
if (-not $NoBuild) {
    & dotnet build $proj -c Release -nologo -v q | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & dotnet build $proj -c Release -nologo -v q
        Write-Host "FastSim build failed." -ForegroundColor Red
        exit 2
    }
}
if (Test-Path "$exe.exe") { $exe = "$exe.exe" }

if ($Mode -eq "parity") {
    $godot = $env:GODOT
    if (-not $godot -or -not (Test-Path $godot)) {
        $file = Join-Path $root "tools/godot_path.txt"
        if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
    }
    if (-not $godot -or -not (Test-Path $godot)) { Write-Host "Godot not found (set `$env:GODOT or tools/godot_path.txt)." -ForegroundColor Red; exit 2 }
    # Recorded in several headless Godot processes at once (each its share of
    # the cases), then joined into one file.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "fastsim_parity_$PID"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $cases = Join-Path $tmp "cases.txt"
    $parts = if ($Jobs -gt 0) { [Math]::Min($Jobs, 8) } else { 4 }
    $procs = @()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt $parts; $k++) {
        $gdArgs = @("--headless", "--path", "`"$root`"", "-s", "res://tools/fastsim_parity.gd", "--",
            "`"$(Join-Path $tmp "part_$k.txt")`"", $(if ($Quick) { "quick" } else { "full" }), $k, $parts)
        $procs += Start-Process -FilePath $godot -ArgumentList $gdArgs -NoNewWindow -PassThru `
            -RedirectStandardOutput (Join-Path $tmp "out_$k.txt") -RedirectStandardError (Join-Path $tmp "err_$k.txt")
    }
    $procs | Wait-Process
    $ErrorActionPreference = "Continue"
    $lines = @()
    for ($k = 0; $k -lt $parts; $k++) {
        # Godot prints harmless warnings on stderr at exit; show only what matters.
        Get-Content (Join-Path $tmp "out_$k.txt"), (Join-Path $tmp "err_$k.txt") -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "SCRIPT ERROR|Parse Error" } | ForEach-Object { Write-Host $_ }
        $part = Join-Path $tmp "part_$k.txt"
        if (-not (Test-Path $part)) { Write-Host "Recording the parity cases failed (part $k)." -ForegroundColor Red; exit 2 }
        $lines += Get-Content $part | Where-Object { $_ }
    }
    [IO.File]::WriteAllLines($cases, [string[]]$lines)
    Write-Host ("fastsim parity: {0} cases recorded in {1:F0} s ({2} Godot processes)" -f $lines.Count, $clock.Elapsed.TotalSeconds, $parts)
    $pa = @("parity", $cases, "--priority", $Priority.ToLower())
    if ($Jobs -gt 0) { $pa += @("--jobs", $Jobs) }
    & $exe @pa
    $code = $LASTEXITCODE
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    exit $code
}

if ($Mode -eq "check") {
    $ca = @("check", $Check, "--priority", $Priority.ToLower())
    if ($Jobs -gt 0) { $ca += @("--jobs", $Jobs) }
    if ($Filter) { $ca += @("--filter", $Filter) }
    & $exe @ca
    exit $LASTEXITCODE
}

if ($Mode -eq "difficulty") {
    $da = @("difficulty", $Step, "--priority", $Priority.ToLower())
    if ($Room -ne "*") { $da += @("--rooms", $Room) }
    if ($Step -eq "measure") {
        $da += @("--what", $What, "--trials", $(if ($Seeds) { $Seeds } else { 16 }), "--jobs", $(if ($Jobs -gt 0) { $Jobs } else { 4 }),
            "--out", $(if ($Out) { [IO.Path]::GetFullPath($Out) } else { "difficulty.tsv" }))
        if ($Bots) { $da += @("--bots", $Bots) }
    }
    if ($Step -eq "show") { $da += @("--first", $Seed) }
    if ($Step -eq "score") {
        $da += @("--in", (($In -split ",") | ForEach-Object { [IO.Path]::GetFullPath($_) }) -join ",")
        if ($Out) { $da += @("--out", [IO.Path]::GetFullPath($Out)) }
    }
    & $exe @da
    exit $LASTEXITCODE
}

if ($Mode -eq "runfile") {
    if (-not $Out) { Write-Host "-Mode runfile needs -Out <file.json>" -ForegroundColor Red; exit 2 }
    & $exe runfile $Seed $(if ($Seeds) { $Seeds } else { 1 }) --out ([IO.Path]::GetFullPath($Out))
    exit $LASTEXITCODE
}

$a = @($Mode)
switch ($Mode) {
    "search" { $a += @($(if ($Seeds) { $Seeds } else { 64 }), $Room, $(if ($Ticks) { $Ticks } else { 1500 })) }
    "searchruns" { $a += @($(if ($Seeds) { $Seeds } else { 64 }), $(if ($Ticks) { $Ticks } else { 16000 })) }
    "rooms" { $a += @($(if ($Seeds) { $Seeds } else { 4 }), $Room) }
    "runs" { $a += @($(if ($Seeds) { $Seeds } else { 4 })) }
    "reaction" { $a += @($(if ($Seeds) { $Seeds } else { 60 }), $Room); if ($Delays) { $a += $Delays } }
    "odds" { $a += @($(if ($Seeds) { $Seeds } else { 180 })); if ($Delays) { $a += $Delays } }
    # Arrivals for the portal check: -Ticks (default 240).
    "combos" { $a += @($(if ($Seeds) { $Seeds } else { 256 }), $(if ($Ticks) { $Ticks } else { 240 })) }
}
$a += @("--priority", $Priority.ToLower())
if ($Jobs -gt 0) { $a += @("--jobs", $Jobs) }
if ($Out) { $a += @("--out", $Out) }
if ($Variant) { $a += @("--variant", $Variant) }
& $exe @a
exit $LASTEXITCODE
