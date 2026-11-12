# FastSim-RS parity: records tools/fastsim_parity.gd's cases in headless Godot
# and replays them in Rust (fastsim-rs parity), like `tools/fastsim.ps1 -Mode parity`.
#   powershell -ExecutionPolicy Bypass -File tools/fastsim-rs/parity.ps1 [-Quick] [-Jobs 8] [-NoBuild] [-Keep <file>] [-Cases <file>]
# -Cases replays an existing recording instead of recording. Exit 3: cargo not installed (skip).
param([switch]$Quick, [int]$Jobs = 8, [switch]$NoBuild, [string]$Keep = "", [string]$Cases = "")
$root = Resolve-Path (Join-Path $PSScriptRoot "../..")
$exe = Join-Path $PSScriptRoot "target/release/fastsim-rs.exe"
if (-not $NoBuild) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build.ps1") -NoSlot
    if ($LASTEXITCODE -eq 3) { exit 3 }
    if ($LASTEXITCODE -ne 0) { Write-Host "FastSim-RS build failed." -ForegroundColor Red; exit 2 }
}
if (-not (Test-Path $exe)) { Write-Host "fastsim-rs.exe not built" -ForegroundColor Red; exit 2 }
if ($Cases) { & $exe parity $Cases --jobs $Jobs; exit $LASTEXITCODE }
$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot)) {
    $file = Join-Path $root "tools/godot_path.txt"
    if (Test-Path $file) { $godot = (Get-Content $file -TotalCount 1).Trim() }
}
if (-not $godot -or -not (Test-Path $godot)) { Write-Host "Godot not found (set `$env:GODOT or tools/godot_path.txt)." -ForegroundColor Red; exit 2 }
$tmp = Join-Path ([IO.Path]::GetTempPath()) "fastsim_rs_parity_$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$parts = [Math]::Max(1, [Math]::Min($Jobs, 8))
$clock = [Diagnostics.Stopwatch]::StartNew()
$procs = @()
for ($k = 0; $k -lt $parts; $k++) {
    $gdArgs = @("--headless", "--path", "`"$root`"", "-s", "res://tools/fastsim_parity.gd", "--",
        "`"$(Join-Path $tmp "part_$k.txt")`"", $(if ($Quick) { "quick" } else { "full" }), $k, $parts)
    $procs += Start-Process -FilePath $godot -ArgumentList $gdArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $tmp "out_$k.txt") -RedirectStandardError (Join-Path $tmp "err_$k.txt")
}
$procs | Wait-Process
$lines = @()
for ($k = 0; $k -lt $parts; $k++) {
    Get-Content (Join-Path $tmp "out_$k.txt"), (Join-Path $tmp "err_$k.txt") -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "SCRIPT ERROR|Parse Error" } | ForEach-Object { Write-Host $_ }
    $part = Join-Path $tmp "part_$k.txt"
    if (-not (Test-Path $part)) { Write-Host "Recording the parity cases failed (part $k)." -ForegroundColor Red; exit 2 }
    $lines += Get-Content $part | Where-Object { $_ }
}
$cases = Join-Path $tmp "cases.txt"
[IO.File]::WriteAllLines($cases, [string[]]$lines)
Write-Host ("fastsim-rs parity: {0} cases recorded in {1:F0} s" -f $lines.Count, $clock.Elapsed.TotalSeconds)
if ($Keep) { Copy-Item $cases $Keep -Force }
& $exe parity $cases --jobs $Jobs
$code = $LASTEXITCODE
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
exit $code
