<#
.SYNOPSIS
  Takes a screenshot of the running game. Rendering needs a real window, so a
  Godot window still shows up briefly (off-screen position, unfocused) and
  closes itself. Only run this when the user asks for screenshots.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Out C:\temp\shot.png -Frame 200
  powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Out C:\temp\ice.png -World ice -Die
  powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Out C:\temp\tall.png -Resolution 390x845 -Screen leaderboard
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Frame = 200,
    [string]$World = "",
    [switch]$Die,
    # Window size in px; 390x845 is a 9:19.5 phone (iPhone 13 in points).
    [string]$Resolution = "405x720",
    # "" plays a run; "home" or "leaderboard" shows that menu instead.
    [string]$Screen = ""
)

$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot) { Write-Host "Godot not found" -ForegroundColor Red; exit 2 }

$dieArg = if ($Die) { "1" } else { "0" }
# Windows PowerShell drops empty arguments, so "-" stands for "none".
$worldArg = if ($World) { $World } else { "-" }
$screenArg = if ($Screen) { $Screen } else { "-" }
& $godot --audio-driver Dummy --path $root --windowed --position "-20000,-20000" --resolution $Resolution `
    -s res://tools/capture_screen.gd -- $Out $Frame $worldArg $dieArg $screenArg
exit $LASTEXITCODE
