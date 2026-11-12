# The FastSim-RS binary for tools/fastsim.ps1 and tools/yardstick.ps1:
# builds it (unless -NoBuild) and prints its path, or prints nothing when cargo
# is not installed or the build fails (the callers then use C# FastSim).
#   $rs = & tools/fastsim-rs/exe.ps1 [-NoBuild]
param([switch]$NoBuild)
# Compiler warnings go to stderr: never let a caller's "Stop" turn them into errors.
$ErrorActionPreference = "Continue"
$exe = Join-Path $PSScriptRoot "target/release/fastsim-rs.exe"
if (-not $NoBuild) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build.ps1") -NoSlot 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if ($LASTEXITCODE -ne 3) { Write-Host "FastSim-RS build failed: using C# FastSim" -ForegroundColor Yellow }
        return
    }
}
if (Test-Path $exe) { return $exe }
