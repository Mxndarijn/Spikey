# Tests supabase/migrations against a real Postgres (needs Docker running):
#   powershell -ExecutionPolicy Bypass -File tools/db_test.ps1
# A fresh throwaway container, small stand-ins for what Supabase adds
# (supabase/tests/00_stubs.sql), every migration in order, then every
# supabase/tests/NN_test_*.sql. Nothing touches the live project.
param([string]$Repo = (Split-Path -Parent $PSScriptRoot))

$tests = Join-Path $Repo "supabase\tests"
$name = "flapjaw-migtest"
$failed = $false

docker version --format "{{.Server.Version}}" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker is not running. Start Docker Desktop and try again." -ForegroundColor Red
    exit 2
}

function Invoke-Sql($file) {
    docker cp $file "${name}:/tmp/run.sql" 2>$null | Out-Null
    return cmd /c "docker exec $name psql -U postgres -v ON_ERROR_STOP=1 -f /tmp/run.sql 2>&1"
}

docker rm -f $name 2>$null | Out-Null
docker run -d --name $name -e POSTGRES_PASSWORD=test postgres:16-alpine | Out-Null
foreach ($i in 1..30) {
    docker exec $name pg_isready -U postgres 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 1
}
# The image restarts Postgres once after its first-run setup.
Start-Sleep -Seconds 3

$out = Invoke-Sql (Join-Path $tests "00_stubs.sql")
if ($out | Select-String "ERROR") { $out | Select-Object -Last 8; $failed = $true }

if (-not $failed) {
    $tmp = Join-Path $env:TEMP "flapjaw_migration.sql"
    foreach ($m in (Get-ChildItem (Join-Path $Repo "supabase\migrations\*.sql") | Sort-Object Name)) {
        # pg_net only exists on Supabase; the stubs stand in for it.
        $text = [IO.File]::ReadAllText($m.FullName) -replace "create extension if not exists pg_net;", ""
        [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
        $out = Invoke-Sql $tmp
        if ($out | Select-String "ERROR") {
            Write-Host "MIGRATION FAILED: $($m.Name)" -ForegroundColor Red
            $out | Select-Object -Last 8
            $failed = $true
            break
        }
        Write-Host "applied $($m.Name)"
    }
}

if (-not $failed) {
    foreach ($t in (Get-ChildItem (Join-Path $tests "*_test_*.sql") | Sort-Object Name)) {
        $out = Invoke-Sql $t.FullName
        $ok = ($out | Select-String "NOTICE:  ok  ").Count
        $bad = $out | Select-String -CaseSensitive -Pattern "FAIL |ERROR:"
        $done = $out | Select-String -CaseSensitive -Pattern "ALL DATABASE TESTS PASSED"
        if (-not $bad -and -not $done) {
            Write-Host "$($t.Name) stopped before its end" -ForegroundColor Red
            $failed = $true
        }
        if ($bad) {
            $bad | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
            $failed = $true
        }
        Write-Host "$($t.Name): $ok checks ok"
    }
}

docker rm -f $name 2>$null | Out-Null
if ($failed) {
    Write-Host "DATABASE TESTS FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "ALL DATABASE TESTS PASSED" -ForegroundColor Green
exit 0
