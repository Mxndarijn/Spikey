<#
.SYNOPSIS
  Grabs JPG frames of every world background (tools/capture_worlds.gd): the
  Leaderboards screen and a seeded run, on a hidden Windows desktop like
  tools/render_run.ps1 (no window on the user's screen, no focus, muted).
  Draws for real (GPU): only when the user asked for frames. Take the GPU lock.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/capture_worlds.ps1 -Out C:\frames\w -Tag short
  powershell -ExecutionPolicy Bypass -File tools/capture_worlds.ps1 -Out C:\frames\w -Tag tall -Resolution 540x1170 -Notch 44
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Tag = "shot",
    # Fake notch: the safe area starts this many canvas px down.
    [int]$Notch = 0,
    [string]$Worlds = "",
    [string]$Resolution = "540x960",
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot -or -not (Test-Path $godot)) { Write-Host "Godot not found." -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$exe = $godot -replace "_console\.exe$", ".exe"
if (-not (Test-Path $exe)) { $exe = $godot }
$log = Join-Path $Out "godot_$Tag.log"
$q = { param($p) '"' + $p + '"' }
$userArgs = @((& $q $Out), (& $q $Tag), "$Notch")
if ($Worlds) { $userArgs += (& $q $Worlds) }
$gdArgs = (@(
    "--audio-driver", "Dummy", "--path", (& $q $root), "--rendering-driver", "opengl3",
    "--windowed", "--resolution", $Resolution, "--fixed-fps", "60", "--disable-vsync",
    "--log-file", (& $q $log), "-s", "res://tools/capture_worlds.gd", "--"
) + $userArgs) -join " "
Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot "render/hidden_desktop.cs") -Raw)
$code = [FlapjawHiddenDesktop]::Run($exe, $gdArgs, $root, $TimeoutMinutes * 60000)
$n = @(Get-ChildItem $Out -Filter "*__$Tag`__*.jpg").Count
Write-Host "capture: exit $code, $n frames in $Out"
if (Test-Path $log) { Get-Content $log | Where-Object { "$_" -match "ERROR|SCRIPT|captured" } | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" } }
exit $code
