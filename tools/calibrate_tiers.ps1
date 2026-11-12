# Fits the human tiers (beginner, normal, good, expert) to their target KM medians
# (30 / 60 / 120 / 250 points, within +-15%) by bisecting each tier's two knobs:
# the reaction to new things (ticks) and the search fineness (a level 0..5).
# Every other human rule is the same for all tiers (MotorTiers.shared in
# tools/fastsim/Human/MotorPlayer.cs). Writes tools/fastsim/Human/tiers.json,
# which the `human:<tier>` bots then play. docs/BOT_TESTING.md, "Tier calibration".
#
#   powershell -ExecutionPolicy Bypass -File tools/calibrate_tiers.ps1
#   powershell -ExecutionPolicy Bypass -File tools/calibrate_tiers.ps1 -Tiers good,expert -Budget 600
#   powershell -ExecutionPolicy Bypass -File tools/calibrate_tiers.ps1 -CSharp              # on C# FastSim instead of FastSim-RS
#   powershell -ExecutionPolicy Bypass -File tools/calibrate_tiers.ps1 -Exe <engine>        # any engine with `measure median`
#   powershell -ExecutionPolicy Bypass -File tools/calibrate_tiers.ps1 -Verify              # then full holdout runs per tier
#
# Each evaluation is `<exe> measure median --bank B --bot tier:react=R,level=L --budget S
# --threads T --out <trials> --json <out>`: room trials from a shared bank, the KM median
# the stratified death rates give, and its interval. Any engine that takes that command
# and writes that JSON ({"median", "lo", "hi", ...}) can run this script: FastSim-RS by
# default (tools/fastsim-rs, the same trials and numbers as C#), C# FastSim with -CSharp or
# when cargo is missing. Every evaluation takes a CPU slot (VARIANT_RULES.md) and frees it.
param(
    [string]$Tiers = "beginner,normal,good,expert",
    # CPU seconds of trials per evaluation; the last evaluation of each tier gets 2x more.
    [double]$Budget = 300,
    [int]$Threads = 4,
    # The engine (default: FastSim-RS, built here; C# FastSim with -CSharp or without cargo).
    [string]$Exe = "",
    [switch]$CSharp,
    # The shared bank (full runs of the default BlindPlanner on dev seeds); made if missing.
    [string]$Bank = "",
    [int]$BankSeeds = 160,
    [string]$Out = "D:\SoftwareProjects\SpikeCage-coord\research\yardstick",
    [string]$Who = "planner-next",
    [int]$MaxSteps = 8,
    # Full runs on the holdout for each fitted tier afterwards (measure report).
    [switch]$Verify,
    # Don't take CPU slots (a machine of your own).
    [switch]$NoSlot
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$targets = @{ beginner = 30; normal = 60; good = 120; expert = 250 }
# Where each tier starts: reaction (ticks) and search level. Good and expert react no
# faster than about 11 ticks (the human floor, the user's ruling); nobody reacts slower than 60.
$start = @{ beginner = @(24, 1); normal = @(20, 2); good = @(15, 3); expert = @(12, 5) }
$reactMin = 11; $reactMax = 60; $levels = 6
$fit = 0.15; $aim = 0.08

if (-not $Exe -and -not $CSharp) { $Exe = & (Join-Path $root "tools/fastsim-rs/exe.ps1") }
if (-not $Exe) {
    $proj = Join-Path $root "tools/fastsim/FastSim.csproj"
    & dotnet build $proj -c Release -nologo -v q | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "FastSim build failed." -ForegroundColor Red; exit 2 }
    $Exe = Join-Path $root "tools/fastsim/bin/Release/net9.0/FastSim.exe"
    if (-not (Test-Path $Exe)) { $Exe = Join-Path $root "tools/fastsim/bin/Release/net9.0/FastSim" }
}
# fastsim-rs runs everything on one thread pool (--jobs); --threads is read too (C# ignores --jobs).
$jobs = @("--jobs", $Threads)
$mdir = Join-Path $Out "measure"
New-Item -ItemType Directory -Force $mdir | Out-Null
# One bank per state of the sim: a room fix makes a new one.
$simRev = (& git -C $root log -1 --format=%h -- sim tools/fastsim/Sim).Trim()
if (-not $Bank) { $Bank = Join-Path $mdir "blind.calib-$simRev.bank.json" }

function With-Slot([scriptblock]$body) {
    if ($NoSlot) { & $body; return }
    $id = (& D:\SoftwareProjects\SpikeCage-coord\slot.ps1 -Take -Who $Who | Select-Object -Last 1)
    try { & $body } finally { & D:\SoftwareProjects\SpikeCage-coord\slot.ps1 -Free -Id $id | Out-Null }
}

if (-not (Test-Path $Bank)) {
    Write-Host "making the bank $Bank (BlindPlanner, dev seeds 10001..$(10000 + $BankSeeds), to 400 points)"
    With-Slot { & $Exe measure bank --bot blind --first 10000 --seeds $BankSeeds --points 400 --threads $Threads @jobs --out $Bank | Out-Host }
    if (-not (Test-Path $Bank)) { Write-Host "no bank made" -ForegroundColor Red; exit 2 }
}

$log = Join-Path $mdir "calibrate-$simRev.log"
function Say($s) { Write-Host $s; Add-Content $log $s }

# The KM median of a tier at (react, level), from the engine. Infinity reads as 1e6.
function Eval-Median([string]$tier, [double]$react, [int]$level, [double]$budget) {
    $bot = "tier:react=$([Math]::Round($react, 1).ToString([Globalization.CultureInfo]::InvariantCulture)),level=$level"
    $trials = Join-Path $mdir "calib-$simRev-$tier.median.tsv"
    $json = Join-Path $mdir "calib-$simRev-$tier.last.json"
    With-Slot { & $Exe measure median --bank $Bank --bot $bot --budget $budget --threads $Threads @jobs --out $trials --json $json | Out-Null }
    $j = Get-Content $json -Raw | ConvertFrom-Json
    $m = if ($null -eq $j.median) { 1e6 } else { [double]$j.median }
    $lo = if ($null -eq $j.lo) { 1e6 } else { [double]$j.lo }
    $hi = if ($null -eq $j.hi) { 1e6 } else { [double]$j.hi }
    Say ("  {0,-8} react {1,5:F1} level {2}: median {3,7:F1} [{4:F1}, {5:F1}], {6} trials, {7} CPU s" -f $tier, $react, $level, $m, $lo, $hi, $j.trials, $j.cpu_s)
    return [pscustomobject]@{ react = $react; level = $level; median = $m; lo = $lo; hi = $hi }
}

$result = [ordered]@{}
foreach ($tier in $Tiers.Split(",") | ForEach-Object { $_.Trim() }) {
    $target = $targets[$tier]
    if (-not $target) { Write-Host "unknown tier $tier" -ForegroundColor Red; exit 2 }
    Say "== $tier (target $target)"
    $react = [double]$start[$tier][0]; $level = [int]$start[$tier][1]
    $best = $null; $lo = $null; $hi = $null
    # 1. The level: at the starting reaction, step the search finer while the bot is too weak
    #    even at the fastest reaction, coarser while it is too strong at the slowest.
    for ($guard = 0; $guard -lt $levels; $guard++) {
        $e = Eval-Median $tier $react $level $Budget
        $best = $e
        if ([Math]::Abs($e.median / $target - 1) -le $aim) { break }
        if ($e.median -lt $target) {
            $fast = Eval-Median $tier $reactMin $level $Budget
            if ($fast.median -ge $target) { $lo = $fast; $hi = $e; break }
            if ($level -eq $levels - 1) { $best = $fast; Say "  $tier is below target even at react $reactMin, level $level"; break }
            $level++; continue
        } else {
            $slow = Eval-Median $tier $reactMax $level $Budget
            if ($slow.median -le $target) { $lo = $e; $hi = $slow; break }
            if ($level -eq 0) { $best = $slow; Say "  $tier is above target even at react $reactMax, level 0"; break }
            $level--; continue
        }
    }
    # 2. The reaction: secant on log(median) between the bracket (lo: faster, stronger; hi: slower, weaker).
    if ($lo -and $hi -and [Math]::Abs($best.median / $target - 1) -gt $aim) {
        for ($step = 0; $step -lt $MaxSteps; $step++) {
            $a = [Math]::Log([Math]::Max(1, $lo.median)); $b = [Math]::Log([Math]::Max(1, $hi.median)); $t = [Math]::Log($target)
            $r = if ($a -ne $b) { $lo.react + ($hi.react - $lo.react) * ($a - $t) / ($a - $b) } else { ($lo.react + $hi.react) / 2 }
            # Keep inside the bracket, a little away from its ends (plain bisection when stuck).
            $span = $hi.react - $lo.react
            $r = [Math]::Min($hi.react - 0.1 * $span, [Math]::Max($lo.react + 0.1 * $span, $r))
            if ($span -lt 0.6) { break }
            $e = Eval-Median $tier $r $level $Budget
            if ([Math]::Abs($e.median / $target - 1) -lt [Math]::Abs($best.median / $target - 1)) { $best = $e }
            if ([Math]::Abs($e.median / $target - 1) -le $aim) { break }
            if ($e.median -ge $target) { $lo = $e } else { $hi = $e }
        }
    }
    # 3. A longer look at the chosen knobs (the trials pile up: this refines that estimate).
    $final = Eval-Median $tier $best.react $best.level (2 * $Budget)
    $fits = [Math]::Abs($final.median / $target - 1) -le $fit
    Say ("  {0}: react {1:F1}, level {2} -> median {3:F1} [{4:F1}, {5:F1}] {6}" -f $tier, $final.react, $final.level, $final.median, $final.lo, $final.hi, $(if ($fits) { "fits" } else { "DOES NOT FIT" }))
    $result[$tier] = [ordered]@{ react = [Math]::Round($final.react, 1); level = $final.level; target = $target
        median = [Math]::Round($final.median, 1); lo = [Math]::Round($final.lo, 1); hi = [Math]::Round($final.hi, 1); fits = $fits }
}

# Tiers fitted before keep their values when only some are run again.
$file = Join-Path $root "tools/fastsim/Human/tiers.json"
$all = [ordered]@{}
if (Test-Path $file) {
    $old = (Get-Content $file -Raw | ConvertFrom-Json).tiers
    foreach ($p in $old.PSObject.Properties) { $all[$p.Name] = $p.Value }
}
foreach ($k in $result.Keys) { $all[$k] = $result[$k] }
$doc = [ordered]@{
    about = "Fitted tier knobs (tools/calibrate_tiers.ps1): reaction to new things (ticks) and search level (MotorTiers.LEVELS). Every other human rule is MotorTiers.shared."
    sim = $simRev; bank = $Bank; date = (Get-Date -Format "yyyy-MM-dd HH:mm"); tiers = $all
}
$doc | ConvertTo-Json -Depth 5 | Set-Content $file -Encoding utf8
Say "wrote $file"

if ($Verify) {
    foreach ($tier in $result.Keys) {
        Say "== verify $tier on the holdout (full runs)"
        $t = "human-$tier"
        With-Slot { & $Exe measure report --bot "human:$tier" --claimed $tier --threads $Threads @jobs --out (Join-Path $mdir "$t.holdout.bank.json") --json (Join-Path $mdir "$t.report.json") | Out-Host }
    }
}
