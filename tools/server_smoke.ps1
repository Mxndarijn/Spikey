# Smoke test of a deployed game server (docs/DEPLOY.md, release day):
#   powershell -ExecutionPolicy Bypass -File tools/server_smoke.ps1 -Sha <commit>
# Against https://<ApiHost>:
#   1. /v1/ping answers the commit and this checkout's gameplay version
#   2. a new test player signs up
#   3. a golden replay sent as submit_run is checked "ok" within seconds
#   4. a copy with a wrong score is held for the Godot check, which rejects it
#      (the godot-check CronJob runs every 10 minutes; -SkipGodot stops at "held")
#   5. the test player and its runs are deleted again
# -ClearAll: delete every player and run (only before release, when all data
#   is test data). Needs the platform's admin kubeconfig for the database.
param(
    [string]$ApiHost = "flapjaw.mn-platform.tech",
    [string]$Sha = "",
    [string]$AdminKubeconfig = "D:/SoftwareProjects/platform-manager/platform.kubeconfig",
    [switch]$SkipGodot,
    [switch]$ClearAll
)

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$env:KUBECONFIG = $AdminKubeconfig
$failed = @()

function Sql([string]$query) {
    $out = $query | & kubectl -n platform-db exec -i postgres-0 -- psql -U platform -d flapjaw -At -q -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "sql failed: $query" }
    return $out
}

function Api($path, $body, $token = "") {
    $headers = @{ "X-Flapjaw-Api" = "1" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    $json = $body | ConvertTo-Json -Depth 6 -Compress
    return Invoke-RestMethod -Method Post -Uri "https://$ApiHost$path" -Headers $headers -ContentType "application/json" -Body $json
}

if ($ClearAll) {
    $before = Sql "select count(*) from auth.users;"
    Sql @"
delete from auth.users;
truncate backend.transfer_log, net.calls;
"@ | Out-Null
    Write-Host "cleared all test data ($before players and everything that was theirs)" -ForegroundColor Green
    exit 0
}

# 1. Ping.
$gameplay = [int]([regex]::Match((Get-Content (Join-Path $repo "sim/sim_config.gd") -Raw), "GAMEPLAY_VERSION := (\d+)").Groups[1].Value)
$ping = Invoke-RestMethod -Uri "https://$ApiHost/v1/ping" -TimeoutSec 15
Write-Host "ping: version $($ping.version), gameplay $($ping.gameplay_version)"
if (-not $ping.ok) { $failed += "ping not ok" }
if ($Sha -and $ping.version -ne $Sha) { $failed += "the server runs $($ping.version), not $Sha" }
if ($ping.gameplay_version -ne $gameplay) { $failed += "the server checks gameplay $($ping.gameplay_version), this checkout is $gameplay" }

# 2. A test player.
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$key = "Fj-" + (-join ($bytes | ForEach-Object { $_.ToString("x2") }))
$session = Api "/v1/auth/anon" @{ device_key = $key }
$player = $session.player_id
$token = $session.access_token
Write-Host "signed up test player $player"

try {
    # 3 and 4. An honest golden replay of this gameplay version, and a copy with a wrong score.
    $golden = Get-ChildItem (Join-Path $repo "tests/replay/golden") -Filter "g${gameplay}_seed_*.json" | Select-Object -First 1
    if (-not $golden) { throw "no golden replay for gameplay $gameplay" }
    $g = Get-Content $golden.FullName -Raw | ConvertFrom-Json
    foreach ($extra in @(0, 1)) {
        Api "/v1/submit_run" @{
            p_name = "smoketest"; p_flyer = "buzz"; p_score = $g.score + $extra; p_gameplay_version = $g.gameplay_version
            p_seed = $g.seed; p_taps = @($g.taps); p_season = $g.season; p_coins = $g.coins; p_end_tick = $g.end_tick
        } $token | Out-Null
    }
    $status = @()
    foreach ($i in 1..20) {
        $status = @(Sql "select status from public.runs where player_id = '$player' order by id;")
        $queued = Sql "select count(*) from backend.godot_queue q join public.runs r on r.id = q.run_id where r.player_id = '$player';"
        if ($status[0] -ne "pending" -and $queued -eq "1") { break }
        Start-Sleep -Seconds 2
    }
    Write-Host "honest run ($($golden.Name)): $($status[0]); tampered run: $($status[1]), held for Godot: $queued"
    if ($status[0] -ne "ok") { $failed += "the honest run is $($status[0]), not ok" }
    if ($status[1] -ne "pending" -or $queued -ne "1") { $failed += "the tampered run was not held for the Godot check" }
    if (-not $SkipGodot -and $status[1] -eq "pending") {
        # Run the Godot check now instead of waiting for its schedule.
        $job = "smoke-godot-" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        & kubectl -n app-flapjaw create job $job --from=cronjob/godot-check | Out-Null
        # Done when it completed or failed (a failed one says why in its log).
        foreach ($i in 1..60) {
            $state = & kubectl -n app-flapjaw get job $job -o jsonpath="{.status.succeeded}/{.status.failed}"
            if ($state -match "^1/" -or $state -match "/[1-9]") { break }
            Start-Sleep -Seconds 5
        }
        & kubectl -n app-flapjaw logs "job/$job" --tail=5
        $final = @(Sql "select status, coalesce(reason, '') from public.runs where player_id = '$player' order by id;")
        Write-Host "after the Godot check: $($final[1])"
        if ($final[1] -notmatch "^rejected\|score mismatch") { $failed += "the Godot check did not reject the tampered run" }
        & kubectl -n app-flapjaw delete job $job --ignore-not-found | Out-Null
    }
} catch {
    $failed += "$_"
} finally {
    # 5. Leave nothing behind.
    Sql "delete from auth.users where id = '$player';" | Out-Null
    Write-Host "deleted test player $player"
}

if ($failed.Count) {
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "SMOKE TEST FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "SMOKE TEST PASSED ($ApiHost)" -ForegroundColor Green
exit 0
