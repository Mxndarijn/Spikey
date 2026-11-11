# The RL bot (docs/RL_BOT.md): a small policy trained on FastSim, played at
# five skill tiers (beginner, normal, good, expert, beast). A playtest tool:
# it never changes sim/ or gameplay. Weights and tiers: tools/rlbot/.
#
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode measure                  # every tier, 400 seeds
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode measure -Tier good -Seeds 1000 -Out good.json
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45         # fresh training
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45 -Resume # go on
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode teach -Minutes 45 [-Resume]  # then learn from the teacher
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode calibrate                # refit the tier handicaps
#   powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode speed                    # ticks per second
#
# -Threads: at most 4 (default 4). Training saves after every generation and
# stops after -Minutes, so split long training into chunks with -Resume.
param(
    [ValidateSet("train", "teach", "calibrate", "measure", "speed")]
    [string]$Mode = "measure",
    [string]$Tier = "all",
    [int]$Seeds = 0,
    [long]$First = 0,
    [long]$Cap = 0,
    [double]$Minutes = 45,
    [switch]$Resume,
    [int]$Threads = 4,
    [double]$Expert = 0,
    # train: PPO settings (defaults in tools/fastsim/RL/Ppo.cs).
    [double]$Lr = 0,
    [int]$Envs = 0,
    [double]$Entropy = -1,
    [string]$Out = "",
    [ValidateSet("Idle", "BelowNormal", "Normal")]
    [string]$Priority = "BelowNormal"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "tools/fastsim/FastSim.csproj"
$exe = Join-Path $root "tools/fastsim/bin/Release/net9.0/FastSim"
$dir = Join-Path $root "tools/rlbot"

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

$a = @("rl", $Mode, "--dir", $dir, "--threads", $Threads, "--priority", $Priority.ToLower())
switch ($Mode) {
    "train" {
        $a += @("--minutes", $Minutes)
        if ($Resume) { $a += @("--resume", "1") }
        if ($Cap) { $a += @("--cap", $Cap) }
        if ($Lr) { $a += @("--lr", $Lr) }
        if ($Envs) { $a += @("--envs", $Envs) }
        if ($Entropy -ge 0) { $a += @("--entropy", $Entropy) }
    }
    "teach" {
        $a += @("--minutes", $Minutes)
        if ($Resume) { $a += @("--resume", "1") }
        if ($Cap) { $a += @("--cap", $Cap) }
        if ($Lr) { $a += @("--lr", $Lr) }
    }
    "calibrate" {
        if ($Seeds) { $a += @("--seeds", $Seeds) }
        if ($Cap) { $a += @("--cap", $Cap) }
        if ($Expert) { $a += @("--expert", $Expert) }
    }
    "measure" {
        $a += @("--tier", $Tier, "--first", $First)
        if ($Seeds) { $a += @("--seeds", $Seeds) }
        if ($Cap) { $a += @("--cap", $Cap) }
        if ($Out) { $a += @("--out", $Out) }
    }
}
& $exe @a
exit $LASTEXITCODE
