# Tests supabase/functions (the Edge Functions) with Deno in Docker:
#   powershell -ExecutionPolicy Bypass -File tools/functions_test.ps1
# Firebase, Google and the database are stand-ins inside the tests; no network
# is used beyond pulling the Deno image the first time.
param([string]$Repo = (Split-Path -Parent $PSScriptRoot))

docker version --format "{{.Server.Version}}" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker is not running. Start Docker Desktop and try again." -ForegroundColor Red
    exit 2
}
$functions = Join-Path $Repo "supabase\functions"
cmd /c "docker run --rm -v `"${functions}:/functions:ro`" denoland/deno:alpine deno test --no-lock /functions 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "FUNCTION TESTS FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "ALL FUNCTION TESTS PASSED" -ForegroundColor Green
exit 0
