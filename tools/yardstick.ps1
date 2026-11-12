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
# -Human with -Mode run also compares each bot with those human runs
# (distances and a human-vs-bot classifier). Take a CPU slot for big runs.
param(
    [ValidateSet("run", "list", "compare", "humans", "leak", "stats")]
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
    [string]$Out = "D:\SoftwareProjects\SpikeCage-coord\research\yardstick",
    [ValidateSet("Idle", "BelowNormal", "Normal")]
    [string]$Priority = "BelowNormal"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "tools/fastsim/FastSim.csproj"
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

$a = @("yardstick", $Mode, "--out", $Out, "--threads", $Threads, "--priority", $Priority.ToLower())
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
