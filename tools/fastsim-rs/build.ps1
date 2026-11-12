# Builds FastSim-RS (release: lto, codegen-units 1, target-cpu=native).
#   powershell -ExecutionPolicy Bypass -File tools/fastsim-rs/build.ps1 [-NoSlot]
# Exit 3 when cargo is not installed (callers skip the Rust steps then).
param([switch]$NoSlot)
$ErrorActionPreference = "Stop"
$cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
if (Test-Path $cargoBin) { $env:Path = "$cargoBin;" + $env:Path }
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { Write-Host "cargo not installed"; exit 3 }
$manifest = Join-Path $PSScriptRoot "Cargo.toml"
$slot = "D:\SoftwareProjects\SpikeCage-coord\slot.ps1"
$id = $null
if (-not $NoSlot -and (Test-Path $slot)) { $id = & $slot -Take -Who rust-port }
try {
    $ErrorActionPreference = "Continue"
    cargo build --release --quiet --manifest-path $manifest
    $code = $LASTEXITCODE
} finally {
    if ($id) { & $slot -Free -Id $id }
}
exit $code
