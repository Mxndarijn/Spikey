# One VM for many small apps (plan)

Status: **plan only, nothing built.** It builds on what this branch made for
Flapjaw alone (docs/SERVER_MIGRATION.md, docs/DEPLOY.md): the same Hetzner VM
with k3s, OpenTofu and Kustomize, grown into a small shared platform. Flapjaw
becomes its first tenant.

Visual version: <https://claude.ai/artifact/C1HEENqyButMkukokaHo34> (source:
`docs/mockups/shared_platform.html`). Keep both in step.

## The idea in one picture

```
Hetzner VM (k3s, one node)                       Hetzner Object Storage
├─ kube-system      Traefik (k3s), CoreDNS        ├─ postgres/   WAL + base backups (PITR)
├─ cert-manager     one Let's Encrypt issuer      └─ dumps/<app>/ nightly pg_dump per app
├─ platform-db      CloudNativePG: one Postgres cluster
│                   one database + one role per app
├─ flux-system      (later, see GitOps)
├─ app-flapjaw      server, godot-check   -> db "flapjaw"
├─ app-<next>       its pods              -> db "<next>"
└─ app-<...>
DNS: *.apps.<domain> -> the VM   (a new app needs no DNS change)
```

Shared: the VM, k3s, Traefik, cert-manager, the Postgres cluster and its
backups. Per app: a namespace, a database and role, a host name, its images,
its deploy files. Apps never see each other's data or pods.

## 1. Two kinds of repository

| Repository | Holds | Who changes it |
|---|---|---|
| `platform` (new) | `infra/` (OpenTofu: VM, firewall, volume), `cluster/` (cert-manager, ClusterIssuer, CloudNativePG operator and the Postgres cluster, default policies), `apps/<name>/` (each tenant's namespace, quota, database, deploy rights), `tools/new-app.ps1`, `tools/deploy-platform.ps1`, its own DEPLOY guide | You, rarely |
| each app (this one, ...) | its code, Dockerfiles and `deploy/` (Kustomize base and overlays for its own namespace only), its `tools/deploy.ps1` | That app's work |

Flapjaw's `infra/hetzner/` and the cluster-wide parts of its `deploy/`
(cert-manager, the issuer, its own Postgres StatefulSet and backup job) move
to `platform`. What stays in this repo is only what runs in `app-flapjaw`.

## 2. The VM

- One Hetzner x86 VM, **8 GB** to start (for example CX32 or CPX31, about
  EUR 8 to 15 a month; check the price list), 2 GB swap, a 40 GB volume for
  Postgres. Grows in place (`server_type`, a rescale keeps the disk).
- Memory budget at 8 GB, steady:

| Part | About |
|---|---|
| Linux, k3s, CoreDNS, Traefik | 900 MB |
| cert-manager, CloudNativePG operator | 200 MB |
| Postgres (shared_buffers 512 MB, max_connections 100) | 900 MB |
| Flapjaw (server 50, Godot check only while it runs) | 100 MB |
| Room for apps | about 5 GB |

  Every app gets a ResourceQuota (default 512 MB requests, 1 GB limits), so
  one app can't starve the others. More apps than fit: a bigger VM, or a
  second k3s node joining the same cluster.
- The firewall is the same as Flapjaw's: 80 and 443 open, 22 and 6443 only
  from your addresses.

## 3. The shared database: CloudNativePG

At this size the operator is worth it (the Flapjaw plan said so for 4 GB and
up): one Postgres cluster, declared in `platform/cluster/postgres.yaml`.

- **One database and one role per app**, declared too (CloudNativePG's
  managed roles and `Database` resources). The app's password lands in a
  Secret in the app's namespace; its `DATABASE_URL` points at
  `pg-rw.platform-db.svc:5432/<app>`.
- **Isolation inside Postgres**: each role owns only its database; `CONNECT`
  on every database is revoked from `PUBLIC`; no app role is superuser;
  per-role `connection limit` (20) and `statement_timeout` (30 s), so one
  app can't take all connections or lock the server up.
- **Backups, two kinds**: continuous WAL archiving plus a nightly base backup
  to Object Storage (restore the whole cluster to any minute, CloudNativePG's
  point-in-time recovery), and a nightly `pg_dump` per database (restore one
  app without touching the others). Both kept 14 days.
- Postgres upgrades and restarts are the operator's (rolling, one instance:
  a minute of downtime for all apps; tell their users or pick a quiet hour).
- An app that needs another engine (MySQL, Redis) runs it inside its own
  namespace with its own limits; only Postgres is shared.

**Flapjaw on the shared database** needs two changes: its migrations create
the roles `anon`, `authenticated`, `service_role` and the schemas `auth` and
`net` (Supabase's stand-ins). Roles are global in a Postgres cluster, so the
platform creates those three once (nologin, owned by nobody's app), and the
Flapjaw role gets `CREATE` on its own database only. The server then runs as
that non-superuser role instead of the database owner it is today. Its tests
(`tools/backend_test.ps1`) get a mode that runs as such a role, so this is
proven before the move.

## 4. Apps in the cluster

Each app gets, from `tools/new-app.ps1 <name> <host>` in `platform`:

- namespace `app-<name>`, with ResourceQuota and LimitRange (default limits
  for any container that forgot them);
- NetworkPolicies: nothing comes in but Traefik (and cert-manager's solver);
  out only to its database on `platform-db`, DNS and the internet;
- a database, role and `DATABASE_URL` Secret (section 3);
- a deploy identity: a ServiceAccount with rights only in its namespace and
  a kubeconfig for it. The app's `deploy.ps1` uses that, so an app's deploy
  can never touch another app or the platform. Your own admin kubeconfig
  stays for the platform.
- a host: `<name>.apps.<domain>` works at once through the wildcard DNS
  record; a custom domain is one more record plus the host in the app's
  Ingress. Certificates come from the shared issuer.

Each app's own `deploy/` stays as Flapjaw's is now (images pinned to the git
sha, `kubectl apply -k`, rollout, smoke test, rollback), minus the cluster
pieces. Images: GitHub Container Registry per app (or any registry; a pull
secret per namespace).

## 5. GitOps

With one app the deploy script was enough. With several, **Flux** becomes
worth its ~150 MB: the cluster follows `platform` and each app's deploy
branch by itself, and the deploy scripts only build and push images and bump
the tag in git. Plan: start with the scripts (as now), move to Flux once the
third app arrives. Argo CD does the same with a web UI, for about 500 MB.

## 6. Monitoring (light)

metrics-server back on (about 50 MB, so `kubectl top` works), and an uptime
check from outside on every app's health URL (a free external pinger, or a
tiny CronJob that alerts you). A full Prometheus and Grafana costs more than
the apps themselves on this VM; leave it until something needs it.

## 7. Risks of sharing

| Risk | What limits it |
|---|---|
| The VM or its disk dies: every app is down | The data volume and Object Storage backups; rebuild with `tofu apply` plus `deploy-platform.ps1` plus each app's deploy (practise once) |
| One app eats memory or CPU | ResourceQuota and LimitRange per namespace |
| One app floods Postgres | Per-role connection limit and statement timeout |
| A Postgres upgrade or restart | All apps pause a minute; planned, at a quiet hour |
| An app's deploy breaks another | Its kubeconfig only reaches its own namespace |
| A leaked app password | That role reaches only its own database |
| An app needs its own uptime | Move it to its own node or VM later; nothing in its deploy changes but the kubeconfig |

## 8. Steps

1. Create the `platform` repository; move `infra/hetzner/` there, grow it to
   8 GB and a 40 GB volume, add the wildcard DNS note.
2. `platform/cluster/`: cert-manager and the issuer (from Flapjaw's
   `deploy/cluster/`), CloudNativePG at a pinned version, the Postgres
   cluster with its backups, the three Supabase roles, default policies.
3. `tools/new-app.ps1` and `tools/deploy-platform.ps1`, with `-Check` like
   Flapjaw's (render, kubeconform, every container limited), and the guide.
4. Flapjaw onto it, on this branch: drop its Postgres, backup job and
   cluster pieces from `deploy/`, take `DATABASE_URL` from the platform's
   Secret, run as a non-superuser role (tests first), namespace `app-flapjaw`.
5. You create the VM and the platform (the guide), then deploy Flapjaw to
   staging there, then prod: the cutover in docs/DEPLOY.md stays the same.
6. Each next app: `new-app.ps1`, its own `deploy/`, deploy.
7. At the third app: Flux.

Steps 1 to 4 are code and tests on this PC; 5 is yours, as before: no
session creates accounts, VMs or DNS records.

## Open questions

1. **Which other apps**, roughly: what they run (language, Postgres or
   something else), how much memory, and do they need staging too? That
   decides 8 GB or more.
2. **A separate `platform` repository**, or a `platform/` folder in one of
   the app repos? (Recommended: separate.)
3. **The domain** for the wildcard (`*.apps.<domain>`), and is it fine that
   every app shows up under it by default?
4. **CloudNativePG** with point-in-time restore (recommended at 8 GB), or one
   plain Postgres StatefulSet with nightly dumps per database (simpler, less
   memory, restores only to last night)?
5. **Flapjaw first on the shared VM**, or keep the 2 GB Flapjaw-only plan for
   its launch and move it over later? (The deploy files differ only in the
   cluster pieces, so either works.)
