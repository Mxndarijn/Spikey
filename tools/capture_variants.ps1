<#
.SYNOPSIS
  Grabs JPG frames of every room variant (tools/capture_variants.gd) on a
  hidden Windows desktop, the way tools/render_run.ps1 films: no window on the
  user's screen, no focus, muted. Draws for real (GPU): only when the user
  asked for frames. Take the GPU lock around it.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/capture_variants.ps1 -Out C:\frames\meadow -World meadow
  powershell -ExecutionPolicy Bypass -File tools/capture_variants.ps1 -Out C:\frames\x -Rooms crowded,lava
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$World = "",
    [string]$Rooms = "",
    # Grab a frame every this many ticks from 60 to 240 (0 = the usual 15 moments).
    [int]$Every = 0,
    [string]$Resolution = "540x960",
    [int]$TimeoutMinutes = 90
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
$log = Join-Path $Out "godot.log"
$q = { param($p) '"' + $p + '"' }
$userArgs = @((& $q $Out), (& $q $World))
$userArgs += (& $q $Rooms)
if ($Every -gt 0) { $userArgs += "$Every" }
$gdArgs = (@(
    "--audio-driver", "Dummy", "--path", (& $q $root), "--rendering-driver", "opengl3",
    "--windowed", "--resolution", $Resolution, "--fixed-fps", "60", "--disable-vsync",
    "--log-file", (& $q $log), "-s", "res://tools/capture_variants.gd", "--"
) + $userArgs) -join " "
# render/hidden_desktop.cs is a small Win32 helper (CreateDesktop), compiled here by
# PowerShell; it is not part of FastSim (the bot sim is Rust, tools/fastsim-rs).
Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot "render/hidden_desktop.cs") -Raw)
$code = [FlapjawHiddenDesktop]::Run($exe, $gdArgs, $root, $TimeoutMinutes * 60000)
$n = @(Get-ChildItem $Out -Filter "*.jpg").Count
Write-Host "capture: exit $code, $n frames in $Out"
if (Test-Path $log) { Get-Content $log | Where-Object { "$_" -match "ERROR|gave up|captured" } | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" } }
exit $code
