# The MPC bot (docs/MPC_BOT.md): plans taps over the bird's own movement
# against hazards moved on from what it has seen. It never looks into the
# future of the run. A playtest tool: it never changes sim/ or gameplay.
#
#   powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1                         # 400 full runs
#   powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1 -Seeds 100 -Sigma 3 -React 17 -MinGap 8
#   powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1 -Room stalker -Seeds 200  # one room (practice)
#   powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1 -Mode speed
#
# -Set "grow=0.2,soft=10": planner knobs (tools/fastsim/Mpc/Planner.cs, MpcParams).
# -Slot: take a CPU slot from the coordinator's slot.ps1 for the run (give its path).
param(
    [ValidateSet("measure", "speed")]
    [string]$Mode = "measure",
    [int]$Seeds = 400,
    [long]$First = 0,
    [long]$Cap = 0,
    [int]$Threads = 8,
    [double]$Sigma = 0,
    [int]$React = 0,
    [int]$MinGap = 1,
    [string]$Room = "",
    [string]$Set = "",
    [string]$Out = "",
    [string]$Slot = "",
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

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$a = @("mpc", $Mode, "--threads", $Threads, "--priority", $Priority.ToLower(), "--seeds", $Seeds, "--first", $First,
    "--sigma", $Sigma.ToString($inv), "--react", $React, "--mingap", $MinGap)
if ($Cap) { $a += @("--cap", $Cap) }
if ($Room) { $a += @("--room", $Room) }
if ($Set) { $a += @("--set", $Set) }
if ($Out) { $a += @("--out", $Out) }

$id = $null
if ($Slot) { $id = & $Slot -Take -Who mpc-planner }
try {
    & $exe @a
    $code = $LASTEXITCODE
}
finally {
    if ($id) { & $Slot -Free -Id $id | Out-Null }
}
exit $code
