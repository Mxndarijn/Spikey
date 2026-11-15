# Running the game server (from an empty Hetzner account to the cutover)

The game server (`backend/`, docs/SERVER_MIGRATION.md) runs on its own
Hetzner VM with k3s. Everything about it is code in this repository:

| Part | Where | What |
|---|---|---|
| The VM | `infra/hetzner/` | OpenTofu: server, firewall, data volume; cloud-init installs k3s and swap |
| What runs on it | `deploy/` | Kustomize: `base/` plus `overlays/staging` and `overlays/prod`; `cluster/` for cert-manager |
| Deploys | `tools/deploy.ps1` | build, push, apply, wait, smoke test; `-Rollback` |
| Restores | `tools/restore.ps1` | the newest (or a named) nightly dump back into Postgres |
| Settings and secrets | `deploy/overlays/<env>/.env.<env>` | git-ignored; copy `deploy/.env.example` |

You do every step here yourself; no Claude session deploys, creates accounts
or touches the live Supabase project. Commands are PowerShell on your PC,
from the repository root.

Rough cost: the VM about EUR 4 to 8 a month (2 GB; 4 GB a little more), Object
Storage for backups about EUR 5, a domain if you don't have one. Check
Hetzner's price list.

## What you need on your PC

- Docker Desktop (builds the images), `kubectl`, OpenTofu (`winget install
  OpenTofu.Tofu`; Terraform works too) and an SSH key
  (`ssh-keygen -t ed25519` if `~/.ssh/id_ed25519.pub` doesn't exist).
- A domain where you can add DNS records.
- A GitHub account for the image registry (GitHub Container Registry, the
  default; any registry works, see `REGISTRY` in `.env.example`).

## 1. Hetzner: project, token, bucket

1. In the Hetzner Cloud console make a project (for example `flapjaw`).
2. Security > API tokens > Generate API token, **Read & Write**. Keep it for
   step 2.
3. Object Storage > Create bucket (for example `flapjaw-backups`, location
   `nbg1`, private). Then Security > S3 credentials > Generate: an access key
   and a secret key. These are for the nightly backups (and, if you want, the
   OpenTofu state: `infra/hetzner/backend.tf.example`).

## 2. The VM: `tofu apply`

```powershell
cd infra/hetzner
copy terraform.tfvars.example terraform.tfvars   # then fill it in
tofu init
tofu apply
```

`terraform.tfvars` needs the token, your own IP address (`admin_cidrs`, the
only address allowed to use SSH and the Kubernetes API; find it at any "what is
my IP" page and add `/32`) and `api_host` (for example `api.example.com`).
The default `server_type` is `cpx11` (2 GB); `cx22` is the comfortable 4 GB
one (docs/SERVER_MIGRATION.md, VM size).

`tofu apply` shows what it will make (a server, a firewall, a 20 GB volume, an
SSH key) and asks you to type `yes`. Note the `ipv4` it prints at the end.

## 3. DNS

At your domain's DNS add an **A** record for `api_host` (and one for staging,
for example `staging-api.example.com`) pointing at the `ipv4` from step 2,
and an **AAAA** record at `ipv6` if you like. Let's Encrypt needs these before
the first deploy can get a certificate.

## 4. The cluster

cloud-init takes a few minutes on the first boot (updates, the volume, swap,
k3s). Then copy the cluster's kubeconfig to your PC:

```powershell
scp root@<ipv4>:/etc/rancher/k3s/k3s.yaml ./flapjaw.kubeconfig
```

Open `flapjaw.kubeconfig` and change `server: https://127.0.0.1:6443` to
`server: https://<ipv4>:6443`. It is the key to the cluster: `*.kubeconfig`
files are git-ignored, never commit one. Then:

```powershell
$env:KUBECONFIG = "$PWD\flapjaw.kubeconfig"
kubectl get nodes            # one node, Ready
```

## 5. The registry

GitHub > Settings > Developer settings > Personal access tokens > Tokens
(classic) > `write:packages`. Then `docker login ghcr.io -u <github user>`
with the token as password. After the first deploy, make the two packages
(`flapjaw-server`, `flapjaw-godot-check`) public on GitHub (Packages >
Package settings), or keep them private and fill in `REGISTRY_USER` and
`REGISTRY_TOKEN` (a token with `read:packages`) so the cluster can pull.

## 6. Settings and secrets

```powershell
copy deploy\.env.example deploy\overlays\staging\.env.staging
```

Fill it in: `REGISTRY` (`ghcr.io/<github user>`), `API_HOST` (the staging
host), `ACME_EMAIL`, `KUBECONFIG_FILE`, a database password (in both
`POSTGRES_PASSWORD` and `DATABASE_URL`; make one with
`[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))`),
the bucket from step 1 and, for board alerts, `FIREBASE_SERVICE_ACCOUNT` (the
Firebase service account JSON in base64, the same one the Supabase
`send-alerts` function has: docs/PUSH_SETUP.md). The Daily Run secret is made
by the database itself on the first start and is in every backup.

## 7. Deploy staging

```powershell
powershell -ExecutionPolicy Bypass -File tools/deploy.ps1 -Check      # offline, touches nothing
powershell -ExecutionPolicy Bypass -File tools/deploy.ps1 -Env staging
```

It refuses uncommitted changes, builds and pushes both images tagged with the
git commit, installs cert-manager and the Let's Encrypt issuer, applies the
staging overlay, waits for the server and pings
`https://<staging host>/v1/ping` until it answers that commit. The first time
the certificate takes a minute or two.

## 8. Point a debug build at it

Write `services/backend_config.json` (git-ignored):

```json
{"kind": "flapjaw", "url": "https://staging-api.example.com", "server_id": "staging-1"}
```

Run the game from the editor or a debug build: it starts fresh once (the
"Fresh start" card), signs in as a new player and plays against staging. Try a
few runs (they show on the boards after the replay check, within seconds),
the Daily Run, the wallet, and Settings > Move to a new phone between two
devices. Delete the file to go back to Supabase.

On the 2 GB VM stop staging when you're done:
`tools/deploy.ps1 -Env staging -Stop`.

Rehearse a rebuild once on staging now (see "If the VM dies" below), so you
know it works before it matters.

## 9. Production

```powershell
copy deploy\.env.example deploy\overlays\prod\.env.prod   # fill in: the prod host, a new password
powershell -ExecutionPolicy Bypass -File tools/deploy.ps1 -Env prod
kubectl -n flapjaw create job --from=cronjob/backup backup-first   # a first backup now
kubectl -n flapjaw logs job/backup-first --all-containers           # "uploaded flapjaw-...sql.gz"
```

## 10. The cutover

1. In GitHub > Settings > Secrets and variables > Actions add
   `FLAPJAW_API_URL` (`https://api.example.com`) and `FLAPJAW_SERVER_ID` (for
   example `flapjaw-1`). The phone builds (`.github/workflows/build.yml`) then
   write `services/backend_config.json`, which wins over the Supabase config.
2. Build and send out the new APK and TestFlight build. On their first launch
   phones start fresh once: new players, empty boards, no diamonds; settings
   and the name stay (BackendReset).
3. Tell everyone to update: builds from before this one keep talking to
   Supabase (they have no update prompt). Builds from now on get "Update
   Flapjaw" when the server's `MIN_API_VERSION` goes past them.

To undo the cutover, remove the two secrets and build again: the phones go back
to Supabase, which kept running untouched.

## 11. Switching Supabase off (a few weeks later)

When no old builds call it any more (Supabase's dashboard shows the requests),
pause or delete the Supabase project in its dashboard and remove the
`SUPABASE_*` GitHub secrets. A later change then removes the Supabase client,
`supabase/functions/`, and the workflows `verify-runs.yml`,
`supabase-db.yml`, `supabase-functions.yml` and `supabase-keepalive.yml`. The
migrations stay: the server applies them (move them next to
`backend/migrations/` in that change).

## Every later deploy

Commit, then `tools/deploy.ps1 -Env staging`, try it, then
`tools/deploy.ps1 -Env prod`. A bad release:
`tools/deploy.ps1 -Env prod -Rollback` (the commit before the last one,
`deploy/.out/prod/history.txt`), or `-Sha <commit>` for any earlier one.
Database migrations only ever add, and each one works with the server before
it, so a rollback never needs to undo one.

## If the VM dies

The database is on the Hetzner volume, not the VM's own disk.

- **The VM is broken but the volume is fine**: `tofu apply -replace=hcloud_server.game`
  (a new VM, the same volume), step 4 again (the kubeconfig), then
  `tools/deploy.ps1 -Env prod -Sha <last commit>`. The data is still there.
- **The volume is gone too**: `tofu apply`, step 4, `tools/deploy.ps1 -Env prod
  -Sha <last commit>`, then `tools/restore.ps1 -Env prod` (the newest nightly
  dump; `-Dump <name>` for another). At most a day of runs is lost.

The DNS record needs a change only when the VM's address changed
(`tofu output ipv4`).

## Looking after it

- Logs: `kubectl -n flapjaw logs deployment/flapjaw-server`.
- The Godot check: `kubectl -n flapjaw get jobs` (a run every 10 minutes,
  gone at once when nothing waits).
- Memory: `kubectl top` needs metrics-server, which is off to save memory; use
  `ssh root@<ipv4> free -m`.
- Ubuntu installs security updates by itself. k3s upgrades: change
  `k3s_version` for new VMs, or follow k3s's upgrade guide on the running one.
- Who moved to another phone: `select * from backend.transfer_log order by at desc;`
  (`kubectl -n flapjaw exec -it postgres-0 -- psql -U flapjaw`).
