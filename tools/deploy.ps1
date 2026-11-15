# Deploys the game server to its k3s VM, the same steps every time (docs/DEPLOY.md):
#   powershell -ExecutionPolicy Bypass -File tools/deploy.ps1 -Env prod
#     1. refuse a tree with uncommitted changes (the image is the commit)
#     2. build and push the server and Godot check images, tagged with the git sha
#     3. cert-manager and the Let's Encrypt issuer (once per cluster; again is harmless)
#     4. kubectl apply -k with the images pinned to that sha and the host set
#     5. wait for the rollout, then a smoke test: /v1/ping answers that sha
#   -Rollback        deploy the sha before the last one (no build)
#   -Sha <sha>       deploy an earlier sha that is in the registry (no build)
#   -Stop            scale the environment to 0 (staging on the 2 GB VM, after testing)
#   -Check           offline only: render both overlays and check them; touches nothing
# Settings come from deploy/overlays/<env>/.env.<env> (copy deploy/.env.example).
# No session runs this against a real cluster: the user does.
param(
    [ValidateSet("prod", "staging")][string]$Env = "staging",
    [string]$Sha = "",
    [switch]$Rollback,
    [switch]$Stop,
    [switch]$Check,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$deploy = Join-Path $repo "deploy"
$namespaces = @{ prod = "flapjaw"; staging = "flapjaw-staging" }
$certManagerDeployments = @("cert-manager", "cert-manager-webhook", "cert-manager-cainjector")

function Fail($text) {
    Write-Host $text -ForegroundColor Red
    exit 1
}

function Read-EnvFile($path) {
    $out = @{}
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $i = $t.IndexOf("=")
        if ($i -lt 1) { continue }
        $out[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $out
}

# The kustomization tools/deploy.ps1 applies: the overlay with the images and host.
function Write-Wrapper($dir, $envName, $registry, $tag, $apiHost) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $rel = "../../overlays/$envName"
    if ((Split-Path -Leaf (Split-Path -Parent $dir)) -ne ".out") { $rel = "../overlays/$envName" }
    $yaml = @"
# Made by tools/deploy.ps1; not checked in.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - $rel
images:
  - name: flapjaw-server
    newName: $registry/flapjaw-server
    newTag: "$tag"
  - name: flapjaw-godot-check
    newName: $registry/flapjaw-godot-check
    newTag: "$tag"
patches:
  - target:
      kind: Ingress
      name: flapjaw-server
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: $apiHost
      - op: replace
        path: /spec/tls/0/hosts/0
        value: $apiHost
"@
    [IO.File]::WriteAllText((Join-Path $dir "kustomization.yaml"), $yaml, (New-Object Text.UTF8Encoding $false))
}

# Checks rendered manifests: every container has a memory limit, no image is
# :latest or unpinned, no placeholder is left. Returns the problems.
function Test-Rendered([string]$yaml) {
    $problems = @()
    foreach ($doc in ($yaml -split "(?m)^---\s*$")) {
        $kind = [regex]::Match($doc, "(?m)^kind:\s*(\S+)").Groups[1].Value
        $name = [regex]::Match($doc, "(?m)^  name:\s*(\S+)").Groups[1].Value
        $images = [regex]::Matches($doc, "(?m)^\s+(- )?image:\s*(\S+)")
        $limits = [regex]::Matches($doc, "(?m)^\s+limits:\s*\r?\n(\s+cpu:.*\r?\n)?\s+memory:")
        if ($images.Count -gt $limits.Count) {
            $problems += "$kind/${name}: a container without a memory limit"
        }
        foreach ($m in $images) {
            $img = $m.Groups[2].Value
            if ($img -match ":latest$" -or $img -notmatch ":") { $problems += "$kind/${name}: image $img is not pinned" }
        }
        # (A Secret names its keys, API_HOST among them; the env file is checked on its own.)
        if ($kind -ne "Secret" -and $doc -match "API_HOST|<[A-Z_]+>") { $problems += "$kind/${name}: a placeholder is left" }
    }
    return $problems
}

function Render($dir) {
    $out = & kubectl kustomize $dir 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "kubectl kustomize $dir failed:`n$($out -join "`n")" }
    return ($out -join "`n")
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { Fail "kubectl is not installed." }

# -Check: both overlays with the example settings, in a temporary copy.
if ($Check) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "flapjaw_deploy_check_$PID"
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Copy-Item -Recurse $deploy $tmp
    $failed = $false
    foreach ($e in @("staging", "prod")) {
        Copy-Item (Join-Path $deploy ".env.example") (Join-Path $tmp "overlays/$e/.env.$e")
        $wrap = Join-Path $tmp ".out/$e"
        Write-Wrapper $wrap $e "registry.example/flapjaw" "0123456789ab" "api.example.com"
        $yaml = Render $wrap
        $problems = @(Test-Rendered $yaml)
        $count = ([regex]::Matches($yaml, "(?m)^kind:")).Count
        if ($problems.Count) {
            $failed = $true
            $problems | ForEach-Object { Write-Host "  $e $_" -ForegroundColor Red }
        } else {
            Write-Host "$e renders: $count objects, every container limited, images pinned"
        }
    }
    $issuer = [IO.File]::ReadAllText((Join-Path $deploy "cluster/cluster-issuer.yaml"))
    if ($issuer -notmatch "email: ACME_EMAIL") { $failed = $true; Write-Host "cluster-issuer.yaml lost its ACME_EMAIL placeholder" -ForegroundColor Red }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    if ($failed) { exit 1 }
    Write-Host "DEPLOY FILES OK" -ForegroundColor Green
    exit 0
}

$overlay = Join-Path $deploy "overlays/$Env"
$envFile = Join-Path $overlay ".env.$Env"
if (-not (Test-Path $envFile)) { Fail "No $envFile yet: copy deploy/.env.example there and fill it in (docs/DEPLOY.md)." }
$settings = Read-EnvFile $envFile
foreach ($k in @("REGISTRY", "API_HOST", "ACME_EMAIL", "POSTGRES_PASSWORD", "DATABASE_URL")) {
    if (-not $settings[$k] -or $settings[$k] -match "<") { Fail "$k is not filled in in $envFile" }
}
if (-not $settings.DATABASE_URL.Contains($settings.POSTGRES_PASSWORD)) {
    Fail "DATABASE_URL must hold the same password as POSTGRES_PASSWORD ($envFile)"
}
if ($settings.KUBECONFIG_FILE) {
    $kc = $settings.KUBECONFIG_FILE
    if (-not [IO.Path]::IsPathRooted($kc)) { $kc = Join-Path $repo $kc }
    if (-not (Test-Path $kc)) { Fail "KUBECONFIG_FILE $kc does not exist (tofu output kubeconfig)" }
    $env:KUBECONFIG = $kc
}
$ns = $namespaces[$Env]
$registry = $settings.REGISTRY.TrimEnd("/")
$out = Join-Path $deploy ".out/$Env"
$history = Join-Path $out "history.txt"

if ($Stop) {
    & kubectl -n $ns scale deployment/flapjaw-server statefulset/postgres --replicas=0
    if ($LASTEXITCODE -ne 0) { Fail "scaling down failed" }
    Write-Host "$Env stopped; deploy it again to start it." -ForegroundColor Green
    exit 0
}

# 1. Which sha.
$build = $true
if ($Rollback) {
    if (-not (Test-Path $history)) { Fail "No deploy history for $Env yet ($history)." }
    $done = @(Get-Content $history | Where-Object { $_.Trim() })
    if ($done.Count -lt 2) { Fail "Nothing to roll back to: $Env has had one deploy." }
    $Sha = $done[$done.Count - 2]
    $build = $false
    Write-Host "Rolling $Env back to $Sha"
} elseif ($Sha) {
    $build = $false
} else {
    Push-Location $repo
    $dirty = git status --porcelain --untracked-files=no
    $Sha = (git rev-parse --short=12 HEAD).Trim()
    Pop-Location
    if ($dirty -and -not $AllowDirty) { Fail "Uncommitted changes: commit first, so the image is exactly a commit (or -AllowDirty)." }
}

# 2. Images.
if ($build) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail "docker is not installed." }
    Push-Location $repo
    foreach ($img in @(@("flapjaw-server", "backend/Dockerfile"), @("flapjaw-godot-check", "deploy/godot-check/Dockerfile"))) {
        $tag = "$registry/$($img[0]):$Sha"
        Write-Host "building $tag"
        & docker build --platform linux/amd64 -f $img[1] --build-arg "GIT_SHA=$Sha" -t $tag .
        if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "building $tag failed" }
        & docker push $tag
        if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "pushing $tag failed (docker login to the registry first)" }
    }
    Pop-Location
}

# 3. Cluster pieces: cert-manager, then its issuer.
& kubectl apply -k (Join-Path $deploy "cluster")
if ($LASTEXITCODE -ne 0) { Fail "applying cert-manager failed" }
foreach ($d in $certManagerDeployments) {
    & kubectl -n cert-manager rollout status "deployment/$d" --timeout=180s
    if ($LASTEXITCODE -ne 0) { Fail "cert-manager did not come up" }
}
$issuer = [IO.File]::ReadAllText((Join-Path $deploy "cluster/cluster-issuer.yaml")).Replace("email: ACME_EMAIL", "email: $($settings.ACME_EMAIL)")
$issuer | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Fail "applying the Let's Encrypt issuer failed" }

# 4. The environment.
& kubectl get namespace $ns 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { & kubectl create namespace $ns | Out-Null }
if ($settings.REGISTRY_USER -and $settings.REGISTRY_TOKEN) {
    $server = $registry.Split("/")[0]
    $secret = & kubectl -n $ns create secret docker-registry flapjaw-registry "--docker-server=$server" "--docker-username=$($settings.REGISTRY_USER)" "--docker-password=$($settings.REGISTRY_TOKEN)" --dry-run=client -o yaml
    $secret | & kubectl apply -f -
}
Write-Wrapper $out $Env $registry $Sha $settings.API_HOST
$yaml = Render $out
$problems = @(Test-Rendered $yaml)
if ($problems.Count) { $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; Fail "the manifests are not ready" }
& kubectl apply -k $out
if ($LASTEXITCODE -ne 0) { Fail "kubectl apply failed" }

# 5. Rollout and smoke test.
& kubectl -n $ns rollout status deployment/flapjaw-server --timeout=300s
if ($LASTEXITCODE -ne 0) {
    & kubectl -n $ns logs deployment/flapjaw-server --tail=40
    Fail "the server did not start. Roll back with: tools/deploy.ps1 -Env $Env -Rollback"
}
$ok = $false
foreach ($i in 1..18) {
    try {
        $ping = Invoke-RestMethod -Uri "https://$($settings.API_HOST)/v1/ping" -TimeoutSec 10
        if ($ping.ok -and $ping.version -eq $Sha) { $ok = $true; break }
        Write-Host "ping answers version $($ping.version), waiting for $Sha"
    } catch {
        Write-Host "ping: $($_.Exception.Message) (the certificate can take a minute the first time)"
    }
    Start-Sleep -Seconds 10
}
if (-not $ok) { Fail "the smoke test failed: https://$($settings.API_HOST)/v1/ping. Roll back with: tools/deploy.ps1 -Env $Env -Rollback" }

$last = ""
if (Test-Path $history) { $last = (Get-Content $history | Where-Object { $_.Trim() } | Select-Object -Last 1) }
if ($last -ne $Sha) { Add-Content -Path $history -Value $Sha }
Write-Host "DEPLOYED $Sha to $Env (https://$($settings.API_HOST))" -ForegroundColor Green
exit 0
