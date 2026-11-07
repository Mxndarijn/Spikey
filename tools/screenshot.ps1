<#
.SYNOPSIS
  Takes a screenshot of the running game without disturbing the desktop.
  The Godot window opens far off-screen, unfocused, and closes itself.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Out C:\temp\shot.png -Frame 200
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Frame = 200
)

$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot) { Write-Host "Godot not found" -ForegroundColor Red; exit 2 }

& $godot --path $root --windowed --position "-20000,-20000" --resolution 405x720 `
    -s res://tools/capture_screen.gd -- $Out $Frame
exit $LASTEXITCODE
