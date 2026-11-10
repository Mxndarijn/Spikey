# Big playtest sweep on every CPU core: runs many headless copies of
# tools/playtest.gd at once, each on its own slice of seeds, then merges them.
#
#   powershell -ExecutionPolicy Bypass -File tools/sweep.ps1                  # every room, 64 seeds
#   powershell -ExecutionPolicy Bypass -File tools/sweep.ps1 -Seeds 256 -Room sawring
#   powershell -ExecutionPolicy Bypass -File tools/sweep.ps1 -Ticks 6000            # longer room runs
#   powershell -ExecutionPolicy Bypass -File tools/sweep.ps1 -Mode searchruns -Seeds 64 -Ticks 16000
#
# -Ticks: run length for search (default 1500 per room) and searchruns (default 16000).
# -Priority: CPU priority of the copies (default BelowNormal, so the PC stays
#   usable while the sweep runs: the copies only get what nothing else wants).
#   Idle is gentler still; Normal is the old behaviour.
#
# Modes: search (can anyone survive each room?), searchruns (full runs through
# the portals), rooms / runs (PlannerBot). Results: <Out>/summary.json plus one
# JSON per job. Every Godot run is headless: no window opens.
param(
    [string]$Mode = "search",
    [int]$Seeds = 64,
    [string]$Room = "*",
    [int]$Ticks = 0,
    [int]$Jobs = 0,
    [ValidateSet("Idle", "BelowNormal", "Normal")]
    [string]$Priority = "BelowNormal",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Resolve-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $file = Join-Path $root "tools/godot_path.txt"
    if (Test-Path $file) {
        $p = (Get-Content $file -TotalCount 1).Trim()
        if (Test-Path $p) { return $p }
    }
    return $null
}

$godot = Resolve-Godot
if (-not $godot) { Write-Host "Godot not found (set `$env:GODOT or tools/godot_path.txt)." -ForegroundColor Red; exit 2 }
if ($Jobs -le 0) { $Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 2) }
$Jobs = [Math]::Min($Jobs, $Seeds)
if (-not $Out) { $Out = Join-Path ([IO.Path]::GetTempPath()) ("flapjaw_sweep_" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
New-Item -ItemType Directory -Force $Out | Out-Null

# Make sure new class names are known before the copies start.
& $godot --headless --path $root --import *> $null

if ($Mode -eq "searchruns" -and $Ticks -le 0) { $Ticks = 16000 }
$filter = if ($Mode -eq "searchruns") { "$Ticks" } else { $Room }
$per = [Math]::Ceiling($Seeds / $Jobs)
$procs = @()
$start = Get-Date
for ($j = 0; $j -lt $Jobs; $j++) {
    $first = $j * $per
    $count = [Math]::Min($per, $Seeds - $first)
    if ($count -le 0) { break }
    $json = Join-Path $Out "job_$j.json"
    $log = Join-Path $Out "job_$j.log"
    $argList = @("--headless", "--path", "`"$root`"", "-s", "res://tools/playtest.gd", "--",
        $Mode, "`"$json`"", "$count", $filter, "$first", "$Ticks")
    $p = Start-Process -FilePath $godot -ArgumentList $argList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    try { $p.PriorityClass = $Priority } catch { }
    $procs += $p
}
Write-Host "Sweep: $Mode, $Seeds seeds, $($procs.Count) jobs at $Priority priority -> $Out"
$procs | Wait-Process
$secs = [int]((Get-Date) - $start).TotalSeconds

# Merge.
$failures = @()
if ($Mode -eq "search" -or $Mode -eq "rooms") {
    $rooms = [ordered]@{}
    foreach ($f in Get-ChildItem $Out -Filter "job_*.json") {
        $d = Get-Content $f.FullName -Raw | ConvertFrom-Json
        foreach ($r in $d.rooms) {
            if (-not $rooms.Contains($r.id)) { $rooms[$r.id] = @{ runs = 0; bad = 0; seeds = @(); points = 0; fine = 0 } }
            foreach ($x in $r.runs) {
                $rooms[$r.id].runs++
                $rooms[$r.id].points += $x.points
                if ($x.level -gt 0) { $rooms[$r.id].fine++ }
                $isBad = if ($Mode -eq "search") { -not $x.ok } else { $x.dead }
                if ($isBad) { $rooms[$r.id].bad++; $rooms[$r.id].seeds += $x.seed }
            }
        }
    }
    $label = if ($Mode -eq "search") { "impossible" } else { "died" }
    foreach ($id in $rooms.Keys) {
        $r = $rooms[$id]
        $line = "{0,-11} {1} {2,4} / {3,-4} avg points {4,5:N1}" -f $id, $label, $r.bad, $r.runs, ($r.points / [Math]::Max(1, $r.runs))
        # Seeds the coarse search missed and a finer pass needed (narrow ways through).
        if ($r.fine -gt 0) { $line += "  (narrow: $($r.fine))" }
        if ($r.bad -gt 0) {
            Write-Host "$line  seeds $($r.seeds -join ',')" -ForegroundColor Yellow
            $failures += @{ room = $id; seeds = $r.seeds }
        } else { Write-Host $line }
    }
} else {
    $all = @()
    foreach ($f in Get-ChildItem $Out -Filter "job_*.json") {
        $all += (Get-Content $f.FullName -Raw | ConvertFrom-Json).runs
    }
    foreach ($x in $all) {
        $good = if ($Mode -eq "searchruns") { $x.ok } else { -not $x.dead }
        if (-not $good) {
            $where = if ($x.died_in) { $x.died_in -join "/" } else { "" }
            Write-Host ("seed {0}: ended at tick {1} in {2}" -f $x.seed, $x.ticks, $where) -ForegroundColor Yellow
            $failures += @{ seed = $x.seed; ticks = $x.ticks; room = $where }
        }
    }
    Write-Host ("{0} of {1} runs made it" -f ($all.Count - $failures.Count), $all.Count)
}
$summary = @{ mode = $Mode; seeds = $Seeds; jobs = $procs.Count; seconds = $secs; failures = $failures }
$summary | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $Out "summary.json")
Write-Host "Done in $secs s. Summary: $(Join-Path $Out 'summary.json')"
if ($failures.Count -gt 0) { exit 1 }
