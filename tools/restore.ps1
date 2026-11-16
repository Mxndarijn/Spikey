# Restores the game's database from a nightly backup (docs/DEPLOY.md, rebuilding
# from scratch):
#   powershell -ExecutionPolicy Bypass -File tools/restore.ps1 -Env prod [-Dump <name>]
# Without -Dump the newest dump in the bucket. Steps: the server stops (scaled
# to 0), a Job downloads the dump and loads it (it was made with --clean, so it
# replaces what is there), the server starts again and migrates anything newer.
# Settings come from deploy/overlays/<env>/.env.<env>. Run by the user, never
# by a session.
param(
    [ValidateSet("prod", "staging")][string]$Env = "prod",
    [string]$Dump = ""
)

# Programs report through their exit codes (checked after each); their stderr
# (docker build progress, kubectl notes) must not stop Windows PowerShell.
$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$namespaces = @{ prod = "flapjaw"; staging = "flapjaw-staging" }
$ns = $namespaces[$Env]
$envFile = Join-Path $repo "deploy/overlays/$Env/.env.$Env"

function Fail($text) {
    Write-Host $text -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $envFile)) { Fail "No $envFile (docs/DEPLOY.md)." }
$settings = @{}
foreach ($line in [IO.File]::ReadAllLines($envFile)) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#") -or $t.IndexOf("=") -lt 1) { continue }
    $settings[$t.Substring(0, $t.IndexOf("=")).Trim()] = $t.Substring($t.IndexOf("=") + 1).Trim()
}
if ($settings.KUBECONFIG_FILE) {
    $kc = $settings.KUBECONFIG_FILE
    if (-not [IO.Path]::IsPathRooted($kc)) { $kc = Join-Path $repo $kc }
    $env:KUBECONFIG = $kc
}

# The Job: find the dump (the newest unless one is named), then load it.
$pick = if ($Dump) { "key=`"$Dump`"" } else { 'key=$(aws s3 ls "s3://$BUCKET/$NAMESPACE/" --endpoint-url "$ENDPOINT" | sort | tail -n 1 | awk ''{print $4}'')' }
$job = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: restore
  namespace: $ns
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: restore
        db-client: "true"
    spec:
      restartPolicy: Never
      volumes:
        - name: dump
          emptyDir: {}
      initContainers:
        - name: download
          image: amazon/aws-cli:2.22.0
          command: ["bash", "-c"]
          args:
            - |
              set -euo pipefail
              $pick
              [ -n "`$key" ] || { echo "no dump found"; exit 1; }
              echo "restoring `$key"
              aws s3 cp "s3://`$BUCKET/`$NAMESPACE/`$key" /dump/flapjaw.sql.gz --endpoint-url "`$ENDPOINT"
          env:
            - {name: NAMESPACE, value: $ns}
            - name: ENDPOINT
              valueFrom: {secretKeyRef: {name: flapjaw-env-restore, key: BACKUP_S3_ENDPOINT}}
            - name: BUCKET
              valueFrom: {secretKeyRef: {name: flapjaw-env-restore, key: BACKUP_S3_BUCKET}}
            - name: AWS_DEFAULT_REGION
              valueFrom: {secretKeyRef: {name: flapjaw-env-restore, key: BACKUP_S3_REGION}}
            - name: AWS_ACCESS_KEY_ID
              valueFrom: {secretKeyRef: {name: flapjaw-env-restore, key: BACKUP_S3_ACCESS_KEY}}
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom: {secretKeyRef: {name: flapjaw-env-restore, key: BACKUP_S3_SECRET_KEY}}
          volumeMounts: [{name: dump, mountPath: /dump}]
          resources: {requests: {memory: 64Mi}, limits: {memory: 256Mi}}
      containers:
        - name: load
          image: postgres:16.6-alpine
          command: ["sh", "-c"]
          args:
            - gunzip -c /dump/flapjaw.sql.gz | psql -v ON_ERROR_STOP=1 "`$DATABASE_URL"
          env:
            - name: DATABASE_URL
              valueFrom: {secretKeyRef: {name: flapjaw-env-restore, key: DATABASE_URL}}
          volumeMounts: [{name: dump, mountPath: /dump}]
          resources: {requests: {memory: 64Mi}, limits: {memory: 256Mi}}
"@

# The Secret the deploy made has a hash in its name; the Job gets its own copy.
& kubectl -n $ns create secret generic flapjaw-env-restore "--from-env-file=$envFile" --dry-run=client -o yaml | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Fail "making the restore secret failed" }
& kubectl -n $ns rollout status statefulset/postgres --timeout=180s
if ($LASTEXITCODE -ne 0) { Fail "Postgres is not up: deploy first (tools/deploy.ps1 -Env $Env)" }
Write-Host "stopping the server"
& kubectl -n $ns scale deployment/flapjaw-server --replicas=0
& kubectl -n $ns delete job restore --ignore-not-found
$job | & kubectl apply -f -
& kubectl -n $ns wait --for=condition=complete job/restore --timeout=900s
$restored = $LASTEXITCODE -eq 0
& kubectl -n $ns logs job/restore --all-containers --tail=20
& kubectl -n $ns delete secret flapjaw-env-restore --ignore-not-found | Out-Null
Write-Host "starting the server"
& kubectl -n $ns scale deployment/flapjaw-server --replicas=1
& kubectl -n $ns rollout status deployment/flapjaw-server --timeout=300s
if (-not $restored) { Fail "THE RESTORE FAILED (logs above); the server runs on what the database had." }
Write-Host "RESTORED $Env" -ForegroundColor Green
exit 0
