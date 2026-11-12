# The bot yardstick (docs/YARDSTICK.md): one measure for every playtest bot.
# Same seeds, same tick cap and the same numbers for all: strength (median,
# p25/p75/p90, deaths per point, tier), the rooms that kill it and how human
# it plays (taps/s, tap intervals, height bands, timing against the ideal tap,
# reaction to new things). Writes <bot>_<set>.json per bot and comparison.md
# across every JSON in -Out. FastSim only: no Godot run, no window.
#
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode list
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Bot rl:all             # quick set, seeds 1..100
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Bot planner,gap -Set full   # seeds 1..400
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Bot search -Seeds 32
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode humans -Human <runs.json or folder>
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode compare           # rebuild the table
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode leak -Bot planner  # does it use what it cannot see?
#   powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode stats -Files a.json,b.tsv  # intervals, survival, a vs b
#
# The test protocol (docs/BOT_TESTING.md): one command per stage.
#   -Mode quick   -Bot base,new [-Budget 600]        # stratified screen on dev seeds, minutes
#   -Mode confirm -Bot base,new [-Ratio 0.8]         # sequential (Pocock, 5 looks) until decided
#   -Mode report  -Bot new [-Fair fair.txt]          # holdout seeds 1..400 once: KM tier, beast/infinite, whole-run leak check
#   -Mode leakrun -Bot new                           # the whole-run leak check alone (seeds 900001+)
#
# Runs on FastSim-RS (tools/fastsim-rs, docs/FASTSIM_RS.md) by default, the
# same numbers and files as C# FastSim; -CSharp uses C# FastSim. Bots only C#
# has (rl:*, world:*, mpc*, honest-v1) run on C# automatically.
#
# -Human with -Mode run also compares each bot with those human runs
# (distances and a human-vs-bot classifier). Take a CPU slot for big runs.
param(
    [ValidateSet("run", "list", "compare", "humans", "leak", "stats", "quick", "confirm", "report", "leakrun")]
    [string]$Mode = "run",
    [string]$Bot = "",
    [ValidateSet("quick", "full")]
    [string]$Set = "quick",
    [int]$Seeds = 0,
    [long]$First = 0,
    [long]$Cap = 0,
    [int]$Threads = 16,
    [string]$Human = "",
    # -Mode stats: run sets to read (yardstick JSONs or death atlas TSVs), comma separated;
    # each is compared with the first. -Json writes the numbers too.
    [string]$Files = "",
    [string]$Json = "",
    [int]$TimingRuns = 0,
    # Protocol modes: the snapshot bank (made from the first bot on dev seeds when missing),
    # CPU seconds of trials per bot (quick), the smallest rate ratio worth finding (confirm),
    # a CPU limit (confirm), and the fairness judge's output for "infinite" (report).
    [string]$Bank = "",
    [double]$Budget = 600,
    [double]$Ratio = 0.8,
    [double]$MaxCpu = 0,
    [string]$Fair = "",
    [int]$BankSeeds = 160,
    [string]$Out = "D:\SoftwareProjects\SpikeCage-coord\research\yardstick",
    [ValidateSet("Idle", "BelowNormal", "Normal")]
    [string]$Priority = "BelowNormal",
    [switch]$CSharp
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "tools/fastsim/FastSim.csproj"
$exe = Join-Path $root "tools/fastsim/bin/Release/net9.0/FastSim"

$csOnly = $Bot -match "(^|,)\s*(rl:|world:|mpc|honest-v1)"
$rs = $null
if (-not $CSharp -and -not $csOnly) { $rs = & (Join-Path $root "tools/fastsim-rs/exe.ps1") }
if ($rs) {
    $exe = $rs
    # fastsim-rs: one thread pool for the whole run (--jobs); --threads is read too.
    $rsJobs = @("--jobs", $Threads)
} else {
$rsJobs = @()
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
}

if ($Mode -in @("quick", "confirm", "report", "leakrun")) {
    if ($Bot -eq "") { Write-Host "-Bot is needed" -ForegroundColor Red; exit 2 }
    $mdir = Join-Path $Out "measure"
    New-Item -ItemType Directory -Force $mdir | Out-Null
    $bots = $Bot.Split(",") | ForEach-Object { $_.Trim() }
    $tag = ($bots[0] -replace "[:,=]", "-")
    $common = @("--threads", $Threads, "--priority", $Priority.ToLower()) + $rsJobs
    if ($Mode -in @("quick", "confirm")) {
        if ($Bank -eq "") { $Bank = Join-Path $mdir "$tag.dev.bank.json" }
        if (-not (Test-Path $Bank)) {
            Write-Host "making the snapshot bank $Bank ($($bots[0]), dev seeds 10001..$(10000 + $BankSeeds), to 400 points)"
            & $exe measure bank --bot $bots[0] --first 10000 --seeds $BankSeeds --points 400 --out $Bank @common
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        $pair = ($bots -join "_") -replace "[:,=]", "-"
        if ($Mode -eq "quick") {
            & $exe measure trials --bank $Bank --bots ($bots -join ",") --budget $Budget --out (Join-Path $mdir "$pair.quick.tsv") @common
        } else {
            $x = @("measure", "confirm", "--bank", $Bank, "--bots", ($bots -join ","), "--ratio", $Ratio, "--out", (Join-Path $mdir "$pair.confirm.tsv"))
            if ($MaxCpu -gt 0) { $x += @("--max-cpu", $MaxCpu) }
            & $exe @x @common
        }
        exit $LASTEXITCODE
    }
    if ($Mode -eq "report") {
        foreach ($b in $bots) {
            $t = $b -replace "[:,=]", "-"
            $x = @("measure", "report", "--bot", $b, "--out", (Join-Path $mdir "$t.holdout.bank.json"), "--json", (Join-Path $mdir "$t.report.json"))
            if ($Fair) { $x += @("--fair", $Fair) }
            if ($Cap) { $x += @("--cap", $Cap) }
            & $exe @x @common
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            & $exe measure leak --bot $b --bank (Join-Path $mdir "$t.leak.bank.json") --json (Join-Path $mdir "$t.leak.json") @common
        }
        exit $LASTEXITCODE
    }
    foreach ($b in $bots) {
        $t = $b -replace "[:,=]", "-"
        & $exe measure leak --bot $b --bank (Join-Path $mdir "$t.leak.bank.json") --json (Join-Path $mdir "$t.leak.json") @common
    }
    exit $LASTEXITCODE
}

$a = @("yardstick", $Mode, "--out", $Out, "--threads", $Threads, "--priority", $Priority.ToLower()) + $rsJobs
if ($Mode -eq "leak") { $a += @("--bot", $Bot) }
if ($Mode -eq "stats") { $a += @("--files", $Files); if ($Json) { $a += @("--json", $Json) } }
if ($Mode -eq "run") {
    if ($Bot -eq "") { Write-Host "-Bot is needed (-Mode list shows them)" -ForegroundColor Red; exit 2 }
    $a += @("--bot", $Bot, "--set", $Set)
}
if ($Seeds) { $a += @("--seeds", $Seeds) }
if ($First) { $a += @("--first", $First) }
if ($Cap) { $a += @("--cap", $Cap) }
if ($TimingRuns) { $a += @("--timing-runs", $TimingRuns) }
if ($Human) { $a += @("--human", $Human) }
& $exe @a
exit $LASTEXITCODE
