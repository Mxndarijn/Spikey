# Tests the game server (backend/, docs/SERVER_MIGRATION.md):
#   powershell -ExecutionPolicy Bypass -File tools/backend_test.ps1 [-Jobs 4] [-NoDb]
# Unit tests always; with Docker running also the integration tests in
# backend/tests/ against a fresh throwaway Postgres 16 (every migration in
# backend/migrations/). Nothing touches a live database. -NoDb: unit tests only.
param([int]$Jobs = 4, [switch]$NoDb, [int]$Port = 55432)

$repo = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $repo "backend\Cargo.toml"
$name = "flapjaw-servertest"

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "cargo not installed: install Rust (docs/FASTSIM_RS.md)" -ForegroundColor Red
    exit 3
}

$useDb = -not $NoDb
if ($useDb) {
    docker version --format "{{.Server.Version}}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker is not running: unit tests only (start Docker Desktop for the integration tests)." -ForegroundColor Yellow
        $useDb = $false
    }
}

if ($useDb) {
    docker rm -f $name 2>$null | Out-Null
    docker run -d --name $name -e POSTGRES_PASSWORD=test -p "127.0.0.1:${Port}:5432" postgres:16-alpine | Out-Null
    $ready = $false
    foreach ($i in 1..40) {
        docker exec $name pg_isready -U postgres 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    # The image restarts Postgres once after its first-run setup.
    Start-Sleep -Seconds 3
    if (-not $ready) {
        Write-Host "Postgres did not start" -ForegroundColor Red
        docker rm -f $name 2>$null | Out-Null
        exit 1
    }
    # The tests run as the shared platform runs the server (platform-manager,
    # tools/new-app.ps1): an ordinary role that owns only its own database, with
    # the three roles the migrations grant to (anon, authenticated, service_role)
    # made beforehand by the platform. That is stricter than a superuser, so it
    # covers a server of its own too.
    $setup = @"
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create role flapjaw login password 'app' connection limit 20;
create database flapjaw owner flapjaw;
revoke connect on database flapjaw from public;
"@
    $setup | docker exec -i $name psql -U postgres -d postgres -q -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "making the app role failed" -ForegroundColor Red
        docker rm -f $name 2>$null | Out-Null
        exit 1
    }
    $env:DATABASE_URL = "postgres://flapjaw:app@127.0.0.1:${Port}/flapjaw"
} else {
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
}

cargo test -j $Jobs --manifest-path $manifest
$code = $LASTEXITCODE

if ($useDb) { docker rm -f $name 2>$null | Out-Null }
if ($code -ne 0) {
    Write-Host "SERVER TESTS FAILED" -ForegroundColor Red
    exit 1
}
if ($useDb) {
    Write-Host "ALL SERVER TESTS PASSED (unit and integration)" -ForegroundColor Green
} else {
    Write-Host "SERVER UNIT TESTS PASSED (integration tests skipped: no Docker)" -ForegroundColor Yellow
}
exit 0
