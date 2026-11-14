<#
.SYNOPSIS
  Renders one recorded run (a run file, docs/RENDERING.md) to an mp4 and/or
  PNG frames with the real game, or only checks it (-Check).

.DESCRIPTION
  1. Always first: a headless check. Godot plays the run file in the real game
     (main.tscn, like a leaderboard replay) and compares its end with the sim
     replay and the file's claimed score, coins, end tick and checksum. Fails
     on any mismatch and on a gameplay_version this build doesn't play.
  2. Unless -Check: Godot plays it again in Movie Maker mode (one PNG per sim
     tick, 60 fps) on a separate, hidden Windows desktop: the window exists
     only there, so nothing shows on the user's screen or taskbar and it never
     takes focus. Sound is muted. ffmpeg then joins the frames into an mp4.
  Rendering draws for real (GPU), so render only when the user asked for it.
  -Check never draws and is always safe.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/render_run.ps1 -Run C:\runs\bot.run.json -Check
  powershell -ExecutionPolicy Bypass -File tools/render_run.ps1 -Run C:\runs\bot.run.json -Out C:\runs\bot.mp4
  powershell -ExecutionPolicy Bypass -File tools/render_run.ps1 -Run C:\runs\bot.run.json -Frames C:\runs\bot_frames
#>
param(
    [Parameter(Mandatory = $true)][string]$Run,
    # The video to write (.mp4).
    [string]$Out = "",
    # A folder to keep the PNG frames in (frame00000000.png, one per tick).
    [string]$Frames = "",
    # Check only: headless, no frames.
    [switch]$Check,
    # Frame size in px. 9:16 like the game's 360x640 world.
    [string]$Resolution = "540x960",
    # How long to keep filming after the run ends (the crash, the score).
    [double]$HoldSeconds = 1.5,
    # Godot's rendering driver: opengl3, or opengl3_angle (Direct3D under the hood).
    [ValidateSet("opengl3", "opengl3_angle")][string]$Driver = "opengl3",
    # live: the HUD a player sees in a run (score, coins, pause); replay: the
    # replay overlay ("Replay: name, score", then "name scored N").
    [ValidateSet("live", "replay")][string]$Hud = "live",
    # H.264 quality (lower is better and bigger): 18 for short clips, 23-26 for long runs.
    [int]$Crf = 18,
    # Where to write the JSON summary of the check (and of the render).
    [string]$Summary = "",
    [int]$TimeoutMinutes = 60
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
    $file = Join-Path $PSScriptRoot "godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot -or -not (Test-Path $godot)) { Write-Host "Godot not found (set `$env:GODOT or tools/godot_path.txt)." -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Run)) { Write-Host "No run file at $Run" -ForegroundColor Red; exit 2 }
if (-not $Check -and -not $Out -and -not $Frames) { Write-Host "Give -Out <file.mp4>, -Frames <folder> or -Check." -ForegroundColor Red; exit 2 }
$runPath = (Resolve-Path $Run).Path
$hold = [int][Math]::Round($HoldSeconds * 60)
$work = Join-Path ([IO.Path]::GetTempPath()) ("flapjaw_render_" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

function Read-Summary([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return Get-Content $path -Raw | ConvertFrom-Json
}

function Show-Summary($s, [string]$what) {
    if ($null -eq $s) { Write-Host "${what}: no summary written (Godot failed to start the script)" -ForegroundColor Red; return }
    if ($s.ok) {
        Write-Host ("{0}: ok  score={1} coins={2} end_tick={3} checksum={4} frames={5}" -f $what, $s.score, $s.coins, $s.end_tick, $s.checksum, $s.frames) -ForegroundColor Green
    } else {
        Write-Host ("{0}: FAILED  {1}" -f $what, $s.reason) -ForegroundColor Red
    }
}

try {
    # A fresh checkout has no class cache yet: import it first (headless).
    if (-not (Test-Path (Join-Path $root ".godot/global_script_class_cache.cfg"))) {
        Write-Host "render: importing the project (fresh checkout)..."
        $ErrorActionPreference = "Continue"
        & $godot --headless --path $root --import 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
    }
    # 1. Headless check: never draws, never opens a window.
    $checkSummary = Join-Path $work "check.json"
    $ErrorActionPreference = "Continue"
    $log = & $godot --headless --audio-driver Dummy --path $root --fixed-fps 60 `
        -s res://tools/render_run.gd -- $runPath $checkSummary $hold $Hud 2>&1
    $ErrorActionPreference = "Stop"
    # Leak notes at exit are harmless; show script errors only.
    $log | Where-Object { "$_" -match "SCRIPT ERROR|Parse Error" } | ForEach-Object { Write-Host $_ }
    $s = Read-Summary $checkSummary
    Show-Summary $s "check"
    if ($Summary) { Copy-Item $checkSummary $Summary -Force -ErrorAction SilentlyContinue }
    if ($null -eq $s -or -not $s.ok) { exit 1 }
    if ($Check) { exit 0 }

    # 2. Film it on a hidden desktop.
    $frameDir = if ($Frames) { $Frames } else { Join-Path $work "frames" }
    New-Item -ItemType Directory -Force $frameDir | Out-Null
    $frameDir = (Resolve-Path $frameDir).Path
    Get-ChildItem $frameDir -Filter "frame*.png" -ErrorAction SilentlyContinue | Remove-Item -Force
    $renderSummary = Join-Path $work "render.json"
    $godotLog = Join-Path $work "godot.log"
    # The console wrapper would start the real exe as a child; start the real one.
    $exe = $godot -replace "_console\.exe$", ".exe"
    if (-not (Test-Path $exe)) { $exe = $godot }
    $q = { param($p) '"' + $p + '"' }
    $gdArgs = @(
        "--audio-driver", "Dummy", "--path", (& $q $root), "--rendering-driver", $Driver,
        "--windowed", "--resolution", $Resolution, "--fixed-fps", "60",
        "--write-movie", (& $q (Join-Path $frameDir "frame.png")), "--log-file", (& $q $godotLog),
        "-s", "res://tools/render_run.gd", "--", (& $q $runPath), (& $q $renderSummary), $hold, $Hud
    ) -join " "
    # render/hidden_desktop.cs is a small Win32 helper (CreateDesktop), compiled here by
    # PowerShell; it is not part of FastSim (the bot sim is Rust, tools/fastsim-rs).
    Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot "render/hidden_desktop.cs") -Raw)
    Write-Host "render: filming on a hidden desktop ($Resolution, 60 fps)..."
    $code = [FlapjawHiddenDesktop]::Run($exe, $gdArgs, $root, $TimeoutMinutes * 60000)
    $r = Read-Summary $renderSummary
    Show-Summary $r "render"
    if ($Summary -and (Test-Path $renderSummary)) { Copy-Item $renderSummary $Summary -Force }
    if ($code -ne 0 -or $null -eq $r -or -not $r.ok) {
        if (Test-Path $godotLog) { Get-Content $godotLog -Tail 20 | ForEach-Object { Write-Host "  $_" } }
        Write-Host "render: Godot exited with $code" -ForegroundColor Red
        exit 1
    }
    $pngs = @(Get-ChildItem $frameDir -Filter "frame*.png" | Sort-Object Name)
    if ($pngs.Count -lt $r.frames - 1) {
        Write-Host ("render: only {0} frames written for {1} played" -f $pngs.Count, $r.frames) -ForegroundColor Red
        exit 1
    }
    # A frame of one flat color is a tiny PNG: the hidden desktop didn't draw.
    $middle = $pngs[[int]($pngs.Count / 2)]
    if ($middle.Length -lt 8000) {
        Write-Host "render: the frames are empty (nothing was drawn). Try -Driver opengl3_angle." -ForegroundColor Red
        exit 1
    }
    Write-Host ("render: {0} frames in {1}" -f $pngs.Count, $frameDir)

    if ($Out) {
        $ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
        if (-not $ffmpeg) { Write-Host "ffmpeg not found on PATH: keep the frames with -Frames instead." -ForegroundColor Red; exit 2 }
        $outDir = Split-Path -Parent ([IO.Path]::GetFullPath($Out))
        if ($outDir) { New-Item -ItemType Directory -Force $outDir | Out-Null }
        $ErrorActionPreference = "Continue"
        & $ffmpeg -hide_banner -loglevel error -y -framerate 60 -i (Join-Path $frameDir "frame%08d.png") `
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset medium -pix_fmt yuv420p -crf $Crf $Out
        $ErrorActionPreference = "Stop"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Out)) { Write-Host "ffmpeg failed" -ForegroundColor Red; exit 1 }
        Write-Host "render: wrote $Out" -ForegroundColor Green
    }
    exit 0
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
