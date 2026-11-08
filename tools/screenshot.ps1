<#
.SYNOPSIS
  Takes a screenshot of the running game. Rendering needs a real window, so a
  Godot window still shows up briefly (off-screen position, unfocused) and
  closes itself. Only run this when the user asks for screenshots.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Out C:\temp\shot.png -Frame 200
  powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Out C:\temp\ice.png -World ice -Die
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Frame = 200,
    [string]$World = "",
    [switch]$Die
)

$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot) { Write-Host "Godot not found" -ForegroundColor Red; exit 2 }

$dieArg = if ($Die) { "1" } else { "0" }
& $godot --audio-driver Dummy --path $root --windowed --position "-20000,-20000" --resolution 405x720 `
    -s res://tools/capture_screen.gd -- $Out $Frame "$World" $dieArg
exit $LASTEXITCODE
