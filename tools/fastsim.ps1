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
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Room bramble -Variant twin    # one variant
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Room bramble -Variant all     # each variant
#
# -Variant (search, rooms, reaction): play that room variant id instead of the
#   one the RNG draws ("all": each variant of each matching room in turn, one
#   report line "room/variant" each). The draw still happens, so the rest of
#   the run's RNG is as in a normal run. Without -Variant nothing changes.
#
# -Jobs: worker processes (default: a quarter of the cores, so the PC stays usable).
#
# The C# sim must match sim/ exactly. After any change in sim/, run -Mode
# parity: it records runs in (headless) Godot and replays them in C#, and
# names the first tick that differs. Port the change (tools/fastsim/PORTING.md)
# until it passes.
param(
    [ValidateSet("search", "searchruns", "rooms", "runs", "parity", "bench", "reaction", "odds", "combos")]
    [string]$Mode = "search",
    [int]$Seeds = 0,
    [string]$Room = "*",
    [string]$Variant = "",
    [int]$Ticks = 0,
    # reaction / odds: reaction times to play, in ticks ("0,60").
    [string]$Delays = "",
    [int]$Jobs = 0,
    [ValidateSet("Idle", "BelowNormal", "Normal")]
    [string]$Priority = "BelowNormal",
    [string]$Out = "",
    [switch]$Quick
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
& dotnet build $proj -c Release -nologo -v q | Out-Null
if ($LASTEXITCODE -ne 0) {
    & dotnet build $proj -c Release -nologo -v q
    Write-Host "FastSim build failed." -ForegroundColor Red
    exit 2
}
if (Test-Path "$exe.exe") { $exe = "$exe.exe" }

if ($Mode -eq "parity") {
    $godot = $env:GODOT
    if (-not $godot -or -not (Test-Path $godot)) {
        $file = Join-Path $root "tools/godot_path.txt"
        if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
    }
    if (-not $godot -or -not (Test-Path $godot)) { Write-Host "Godot not found (set `$env:GODOT or tools/godot_path.txt)." -ForegroundColor Red; exit 2 }
    $cases = Join-Path ([IO.Path]::GetTempPath()) "fastsim_parity.txt"
    $gdArgs = @("--headless", "--path", $root, "-s", "res://tools/fastsim_parity.gd", "--", $cases)
    if ($Quick) { $gdArgs += "quick" }
    # Godot prints harmless warnings on stderr at exit; don't stop on them.
    $ErrorActionPreference = "Continue"
    & $godot @gdArgs 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -match "fastsim parity|SCRIPT ERROR|Parse Error" } | ForEach-Object { Write-Host $_ }
    if (-not (Test-Path $cases)) { Write-Host "Recording the parity cases failed." -ForegroundColor Red; exit 2 }
    $pa = @("parity", $cases, "--priority", $Priority.ToLower())
    if ($Jobs -gt 0) { $pa += @("--jobs", $Jobs) }
    & $exe @pa
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
