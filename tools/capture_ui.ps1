<#
.SYNOPSIS
  Screenshots of every screen (tools/capture_ui.gd) into one folder. Rendering
  needs a real window, so a Godot window shows up off-screen, unfocused and
  muted, and closes itself. Only run this when the user asks for screenshots.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/capture_ui.ps1 -Out docs/ui-rework/after
  powershell -ExecutionPolicy Bypass -File tools/capture_ui.ps1 -Out C:\temp\ui -Only "01_home,03_settings" -World neon
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    # A 9:19.5 phone (1080 x 2340 at 0.6, so it fits a 1440 px tall screen).
    [string]$Resolution = "648x1404",
    [string]$Only = "",
    # A world id (ice, neon...) to shoot every screen in; "" keeps the save's.
    [string]$World = ""
)

$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot) { Write-Host "Godot not found" -ForegroundColor Red; exit 2 }
$outDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Out))
$onlyArg = if ($Only) { $Only } else { "-" }
$worldArg = if ($World) { $World } else { "-" }
& $godot --audio-driver Dummy --path $root --windowed --position "-20000,-20000" --resolution $Resolution `
    -s res://tools/capture_ui.gd -- $outDir $onlyArg $worldArg
exit $LASTEXITCODE
