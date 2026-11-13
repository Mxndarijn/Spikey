# Playtest sweeps on FastSim-RS, the Rust copy of the sim (tools/fastsim-rs,
# docs/FASTSIM_RS.md). Same modes, seeds and JSON as tools/sweep.ps1, but native
# code. Needs Rust (cargo); no Godot window, no Godot run except for the parity
# check.
#
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1                         # search, every room, 64 seeds
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Seeds 1024 -Room sawring
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode searchruns -Seeds 256 -Ticks 16000
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode runs -Seeds 200   # PlannerBot
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode parity            # check it still matches sim/
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode reaction          # reaction benchmark, 60 arrivals per room
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode odds -Seeds 360   # survival by reaction time in real runs
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode scan -Room gates -Delays 45 -Seeds 4   # entry heights with no way to live
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode parity -Quick     # faster, fewer cases
#   powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check             # the check's bot tests
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
# -Variant (search, rooms, reaction, scan): play that room variant id instead of the
#   one the RNG draws ("all": each variant of each matching room in turn, one
#   report line "room/variant" each). The draw still happens, so the rest of
#   the run's RNG is as in a normal run. Without -Variant nothing changes.
#
# -Mode check: the bot-heavy tests of tools/check.ps1, ported from their
#   GDScript tests (which keep a small sample) with the same rules and more
#   seeds (tools/fastsim-rs/fastsim/src/checks/, tools/fastsim-rs/PORTING.md).
#   -Check picks some (comma list, default all); -Filter keeps those whose name
#   or GD test "path:method" contains it, as tools/check.ps1 -TestFilter.
#   Exits 1 with the failures listed.
#
# -Jobs: threads (default 4).
#
# The Rust sim must match sim/ exactly. After any change in sim/, run -Mode
# parity (tools/fastsim-rs/parity.ps1): it records runs in (headless) Godot,
# replays them in Rust and names the first tick that differs. Port the change
# (tools/fastsim-rs/PORTING.md) until it passes.
param(
    [ValidateSet("search", "searchruns", "rooms", "runs", "parity", "bench", "reaction", "odds", "scan", "check", "runfile", "difficulty")]
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
    # Use the FastSim-RS already built (tools/check.ps1 builds once, then runs
    # parity and the checks side by side).
    [switch]$NoBuild
)

$root = Split-Path -Parent $PSScriptRoot
$jobs = $(if ($Jobs -gt 0) { $Jobs } else { 4 })

if ($Mode -eq "parity") {
    $pa = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "tools/fastsim-rs/parity.ps1"), "-Jobs", $jobs)
    if ($Quick) { $pa += "-Quick" }
    if ($NoBuild) { $pa += "-NoBuild" }
    & powershell @pa
    exit $LASTEXITCODE
}

$rs = & (Join-Path $root "tools/fastsim-rs/exe.ps1") -NoBuild:$NoBuild
if (-not $rs) { Write-Host "FastSim-RS not built (install Rust: docs/FASTSIM_RS.md)." -ForegroundColor Red; exit 2 }

$ra = @()
if ($Mode -eq "check") { $ra = @("check", $Check); if ($Filter) { $ra += @("--filter", $Filter) } }
elseif ($Mode -eq "bench") { $ra = @("bench") }
elseif ($Mode -eq "runfile") {
    if (-not $Out) { Write-Host "-Mode runfile needs -Out <file.json>" -ForegroundColor Red; exit 2 }
    $ra = @("runfile", $Seed, $(if ($Seeds) { $Seeds } else { 1 }), "--out", [IO.Path]::GetFullPath($Out))
}
elseif ($Mode -eq "difficulty") {
    $ra = @("difficulty", $Step)
    if ($Room -ne "*") { $ra += @("--rooms", $Room) }
    if ($Step -eq "measure") {
        $ra += @("--what", $What, "--trials", $(if ($Seeds) { $Seeds } else { 16 }),
            "--out", $(if ($Out) { [IO.Path]::GetFullPath($Out) } else { "difficulty.tsv" }))
        if ($Bots) { $ra += @("--bots", $Bots) }
    }
    if ($Step -eq "show") { $ra += @("--first", $Seed) }
    if ($Step -eq "score") {
        # Join first: in @("--in", (...) -join ",") the comma binds before -join, and the
        # whole list (with "--in") becomes one argument.
        $inFiles = (($In -split ",") | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_) }) -join ","
        $ra += @("--in", $inFiles)
        if ($Out) { $ra += @("--out", [IO.Path]::GetFullPath($Out)) }
    }
}
else {
    $ra = @($Mode)
    switch ($Mode) {
        "search" { $ra += @($(if ($Seeds) { $Seeds } else { 64 }), $Room, $(if ($Ticks) { $Ticks } else { 1500 })) }
        "searchruns" { $ra += @($(if ($Seeds) { $Seeds } else { 64 }), $(if ($Ticks) { $Ticks } else { 16000 })) }
        "rooms" { $ra += @($(if ($Seeds) { $Seeds } else { 4 }), $Room) }
        "runs" { $ra += @($(if ($Seeds) { $Seeds } else { 4 })) }
        "reaction" { $ra += @($(if ($Seeds) { $Seeds } else { 60 }), $Room); if ($Delays) { $ra += $Delays } }
        "odds" { $ra += @($(if ($Seeds) { $Seeds } else { 180 })); if ($Delays) { $ra += $Delays } }
        # One room (default ghostdoors), one reaction time (-Delays, default 45), -Seeds layouts (default 4).
        "scan" { $ra += @($(if ($Room -ne "*") { $Room } else { "ghostdoors" }), $(if ($Delays) { $Delays } else { 45 }), $(if ($Seeds) { $Seeds } else { 4 })) }
    }
    $ra += @("--priority", $Priority.ToLower())
    if ($Out) { $ra += @("--out", $Out) }
    if ($Variant) { $ra += @("--variant", $Variant) }
}
$ra += @("--jobs", $jobs)
& $rs @ra
exit $LASTEXITCODE
