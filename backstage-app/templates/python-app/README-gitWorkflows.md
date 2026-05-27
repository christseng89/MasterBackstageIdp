# CI/CD Pipeline

This document covers the four GitHub Actions workflows generated into every repo scaffolded from the `python-app` Backstage template.

| Workflow file | Purpose | Trigger |
|---|---|---|
| `.github/workflows/<app_name>-cicd.yaml` | Build image + deploy to **dev** | Auto on `src/**` push |
| `.github/workflows/<app_name>-staging-cd.yaml` | Deploy to **staging** | Auto on `values-staging.yaml` change |
| `.github/workflows/<app_name>-prod-cd.yaml` | Deploy to **prod** | Auto on `values-prod.yaml` change |
| `.github/workflows/mirror-cli-binaries.yaml` | Mirror `argocd`, `yq`, `kubectl` binaries to Docker Hub | Manual (`workflow_dispatch`) |

Staging and prod each get their own dedicated workflow file so they can evolve independently — different timeouts, different approval gates, different notification channels. The two files are identical apart from the env name (`staging` vs `prod`), the trigger path, the concurrency group key, and the hardcoded `ARGOCD_APP` / `DEST_NAMESPACE` values.

---

## Overview

```
src/** push to main
        │
        ▼
   ┌─────────┐
   │   ci    │  GitHub-hosted (ubuntu-latest)
   │         │  • builds multi-arch Docker image
   │         │  • pushes to Docker Hub as <app_name>:<commit_id>
   └────┬────┘
        │ commit_id
        ▼
   ┌─────────┐
   │  cd     │  Self-hosted ARC runner (linux)          cicd.yaml
   │  (dev)  │  • writes commit_id into values-dev.yaml
   │         │  • commits back to main
   │         │  • ArgoCD syncs <app_name>-dev app → namespace <app_name>-dev
   └─────────┘
        │
        │   User edits values-staging.yaml and commits
        ▼
   ┌─────────┐
   │  cd     │  Self-hosted ARC runner (linux)       staging-cd.yaml
   │(staging)│  • skips if image.tag is empty
   │         │  • ArgoCD syncs <app_name>-staging app → namespace <app_name>-staging
   └─────────┘

        │   User edits values-prod.yaml and commits
        ▼
   ┌─────────┐
   │  cd     │  Self-hosted ARC runner (linux)       prod-cd.yaml
   │ (prod)  │  • skips if image.tag is empty
   │         │  • ArgoCD syncs <app_name>-prod app → namespace <app_name>-prod
   └─────────┘
```

---

## `cicd.yaml` — Build + Deploy to Dev

### Triggers

| Event | Condition |
|---|---|
| `push` | Any change under `src/**` on `main` |
| `workflow_dispatch` | Manual re-run from Actions tab (no code change needed) |

### Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `ARGOCD_VERSION` | `vars.ARGOCD_VERSION` (repo variable) | ArgoCD CLI version pulled from Docker Hub mirror |
| `YQ_VERSION` | `vars.YQ_VERSION` (repo variable) | yq version pulled from Docker Hub mirror |
| `KUBECTL_VERSION` | `vars.KUBECTL_VERSION` (repo variable) | kubectl version pulled from Docker Hub mirror |
| `IMAGE_NAME` | hardcoded | `christseng89/<app_name>` Docker Hub image repository |
| `VALUES_PATH` | hardcoded | `charts/<app_name>/values-dev.yaml` — Helm values file updated by CD |
| `ARGOCD_APP` | hardcoded | `<app_name>-dev` — ArgoCD application name for dev |
| `ARGOCD_SERVER` | hardcoded | `argocd-server.argocd.svc.cluster.local` — in-cluster ArgoCD DNS |
| `ARGOCD_CHART_PATH` | hardcoded | `charts/<app_name>` — Helm chart path for ArgoCD app create |
| `DEV_NAMESPACE` | hardcoded | `<app_name>-dev` — Kubernetes namespace the dev deployment targets; ArgoCD auto-creates it via `CreateNamespace=true` |

To upgrade a tool version: update the repo variable in GitHub Settings → Variables (or pass the new version as input to `mirror-cli-binaries.yaml` which auto-updates it). The cache key includes the version string so the next run automatically invalidates and re-downloads.

### CI Job — Build and Push

Runs on `ubuntu-latest` (GitHub-hosted).

| Step | What it does |
|---|---|
| Checkout | Checks out the repo |
| Shorten commit id | Takes first 6 chars of `GITHUB_SHA` (e.g. `a1b2c3`); passed to CD job via `commit_id` output |
| Set up QEMU + Buildx | Enables cross-arch emulation for `linux/amd64` + `linux/arm64` builds |
| Login to Docker Hub | Authenticates with `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets |
| Build and push | Pushes `<app_name>:<commit_id>`; uses `<app_name>:buildcache` registry cache to save 60–120 s on warm builds |

### CD Job — Deploy to Dev

Runs on `[self-hosted, linux]` (ARC runner pod in-cluster).

| Step | What it does |
|---|---|
| Checkout | Checks out repo with `GITHUB_TOKEN` for push permission |
| Detect runner architecture | Sets `amd64` or `arm64` for tool downloads |
| Cache + install kubectl | Restores kubectl from `actions/cache`; on miss, pulls `christseng89/kubectl-bin:<version>` from Docker Hub and extracts via `docker cp` |
| Cache + install yq | Same mirror pattern; on miss, pulls `christseng89/yq-bin:<version>` |
| Update dev values file | Runs `yq -i '.image.tag = "<commit_id>"' values-dev.yaml` |
| Commit changes | Pushes updated `values-dev.yaml` to `main` with `--rebase --autostash` |
| Cache + install ArgoCD CLI | Same mirror pattern; cold run ~5–10 min, cached <1 s |
| ArgoCD login | Logs into ArgoCD server via in-cluster DNS with `--plaintext --grpc-web` |
| Register GitHub repo in ArgoCD | Runs `argocd repo add --username x-access-token --password GH_PAT --upsert` |
| Create ArgoCD app if absent | Checks `argocd app get`; if missing, runs `argocd app create` targeting namespace `DEV_NAMESPACE` (`<app_name>-dev`) with automated sync, auto-prune, and self-heal |
| ArgoCD app sync | Runs `argocd app sync` + `argocd app wait --health --timeout 180` |
| Diagnose on failure | Dumps app state, pod events (from `DEV_NAMESPACE`), and logs when any step above fails |

### Concurrency

```yaml
concurrency:
  group: cicd-${{ github.ref }}
  cancel-in-progress: false
```

One run per branch at a time. A second push waits rather than cancelling — ensures a CD job already writing `values-dev.yaml` and syncing ArgoCD is never killed mid-flight.

### Permissions

```yaml
permissions:
  contents: write
```

Required for the CD job to commit the updated `values-dev.yaml` back to `main`.

### Init Commit Guard

Both the `ci` and `cd` jobs have:

```yaml
if: "!contains(github.event.head_commit.message || '', 'init commit')"
```

This skips the workflow when the Backstage scaffolder creates the repo with its initial "init commit" — preventing a build attempt before secrets and repo variables are configured.

---

## `staging-cd.yaml` and `prod-cd.yaml` — Deploy to Staging or Prod

Staging and prod each have a dedicated workflow file. The two files are functionally identical apart from the environment they target — splitting them keeps the trigger path filter exact, makes it easy to add prod-only protections (e.g. a GitHub `environment: production` with required reviewers) without affecting staging, and yields a cleaner run history per environment.

### Triggers

| File | `push` path | `workflow_dispatch` |
|---|---|---|
| `<app_name>-staging-cd.yaml` | `charts/<app_name>/values-staging.yaml` on `main` | Yes — no inputs |
| `<app_name>-prod-cd.yaml` | `charts/<app_name>/values-prod.yaml` on `main` | Yes — no inputs |

The typical flow is:
1. Edit `values-staging.yaml` (or `values-prod.yaml`) — set `image.tag` to the desired tag
2. Commit and push to `main`
3. The matching workflow triggers automatically and syncs the corresponding ArgoCD app

### Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `ARGOCD_VERSION` | `vars.ARGOCD_VERSION` (repo variable) | ArgoCD CLI version |
| `KUBECTL_VERSION` | `vars.KUBECTL_VERSION` (repo variable) | kubectl version |
| `ARGOCD_SERVER` | hardcoded | `argocd-server.argocd.svc.cluster.local` — in-cluster ArgoCD DNS |
| `ARGOCD_CHART_PATH` | hardcoded | `charts/<app_name>` — Helm chart path for ArgoCD app create |
| `DEPLOY_ENV` | hardcoded per file | `staging` or `prod` |
| `ARGOCD_APP` | hardcoded per file | `<app_name>-staging` or `<app_name>-prod` |
| `DEST_NAMESPACE` | hardcoded per file | `<app_name>-staging` or `<app_name>-prod` |
| `VALUES_FILE` | hardcoded per file | `charts/<app_name>/values-staging.yaml` or `values-prod.yaml` |

Because the environment is fixed per file, there is no longer a "Detect environment" step — that logic existed only to disambiguate the single combined workflow we used previously.

### CD Job

Runs on `[self-hosted, linux]` (ARC runner pod in-cluster).

| Step | What it does |
|---|---|
| Checkout | Checks out the repo |
| Validate image tag | Reads `.image.tag` from `VALUES_FILE`. If empty, prints a notice and skips all deployment steps |
| Detect runner architecture | Sets `amd64` or `arm64` |
| Cache + install kubectl | Same Docker Hub mirror pattern as `cicd.yaml` |
| Cache + install ArgoCD CLI | Same Docker Hub mirror pattern as `cicd.yaml` |
| ArgoCD login | Logs into ArgoCD server via in-cluster DNS |
| Register GitHub repo in ArgoCD | Runs `argocd repo add --upsert` with `GH_PAT` |
| Create ArgoCD app if absent | Checks `argocd app get`; if missing, creates `ARGOCD_APP` targeting namespace `DEST_NAMESPACE` with automated sync, auto-prune, and self-heal |
| ArgoCD app sync | Runs `argocd app sync` + `argocd app wait --health --timeout 180` |
| Diagnose on failure | Dumps app state, pods (from `DEST_NAMESPACE`), and logs — skipped if image tag was empty |

### Concurrency

```yaml
# staging-cd.yaml
concurrency:
  group: staging-cd-${{ github.ref }}
  cancel-in-progress: false

# prod-cd.yaml
concurrency:
  group: prod-cd-${{ github.ref }}
  cancel-in-progress: false
```

Staging and prod use different group keys, so a staging deploy and a prod deploy can run in parallel. Two pushes to the *same* environment serialize.

### Permissions

```yaml
permissions:
  contents: read
```

Read-only — the values file is already updated by the user's commit. No write-back needed.

### Init Commit Guard

Each `cd` job has:

```yaml
if: "!contains(github.event.head_commit.message || '', 'init commit')"
```

This prevents a run triggered by a values file accidentally checked in during scaffolding before secrets are configured.

### Optional — Add a Prod Approval Gate

Because prod has its own workflow file, you can attach a GitHub deployment environment to it without touching staging:

1. In the repo, **Settings → Environments → New environment**, name it `production`, add required reviewers.
2. Edit `<app_name>-prod-cd.yaml` and add `environment: production` to the `cd` job:

   ```yaml
   jobs:
     cd:
       environment: production
       runs-on: [self-hosted, linux]
       ...
   ```

GitHub will then pause the workflow at the start of the job until a reviewer approves.

---

## `mirror-cli-binaries.yaml` — Mirror CLI Binaries to Docker Hub

### Purpose

The self-hosted ARC runner pod runs inside the cluster where GitHub Releases downloads are slow or flaky from Asia. This workflow pre-mirrors the `argocd`, `yq`, and `kubectl` binaries to Docker Hub (Cloudflare CDN with Asia POPs) so both CD jobs can pull them quickly.

The three mirror images produced are:

| Docker Hub image | Binary |
|---|---|
| `christseng89/argocd-bin:<version>` | `/argocd` |
| `christseng89/yq-bin:<version>` | `/yq` |
| `christseng89/kubectl-bin:<version>` | `/kubectl` |

All are `FROM scratch` multi-arch images (`linux/amd64` + `linux/arm64`). No `docker login` is needed to pull them — they are public.

### When to Run

Run this workflow **before** bumping a version in the repo variables. The CD job's cache key includes the version string, so a version bump invalidates the cache and triggers a fresh pull — the mirror must already exist on Docker Hub or the pull will fail.

```
1. Run mirror-cli-binaries.yaml (Actions → Run workflow)
      argocd_version: v3.5.0   ← new version (leave blank to mirror from repo variable)
      yq_version:              ← leave blank to skip
      kubectl_version:         ← leave blank to skip

2. The workflow automatically updates ARGOCD_VERSION repo variable to v3.5.0
3. Next CD run pulls the new binary from Docker Hub (cache key changed)
```

### Trigger

`workflow_dispatch` only — never runs automatically.

### Inputs

| Input | Default | Description |
|---|---|---|
| `argocd_version` | _(blank — uses `ARGOCD_VERSION` repo variable)_ | ArgoCD CLI version to mirror. Leave blank to use repo variable. |
| `yq_version` | _(blank — uses `YQ_VERSION` repo variable)_ | yq version to mirror. Leave blank to use repo variable. |
| `kubectl_version` | _(blank — uses `KUBECTL_VERSION` repo variable)_ | kubectl version to mirror. Leave blank to use repo variable. |

Leave all blank to re-mirror all three tools at their currently configured versions. Pass a version to override and automatically update the corresponding repo variable.

### Steps

| Step | What it does |
|---|---|
| Login to Docker Hub | Authenticates with `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` |
| Set up QEMU + Buildx | Enables cross-arch builds from the amd64 GitHub-hosted runner |
| Mirror ArgoCD CLI | Downloads `argocd-linux-amd64` and `argocd-linux-arm64` from GitHub Releases; builds a `FROM scratch` multi-arch image; pushes to `christseng89/argocd-bin:<version>` |
| Mirror yq | Same pattern for `christseng89/yq-bin:<version>` |
| Mirror kubectl | Downloads from `dl.k8s.io`; builds and pushes `christseng89/kubectl-bin:<version>` |
| Update repo variables | If an input version was provided, updates the corresponding repo variable (`ARGOCD_VERSION`, `YQ_VERSION`, or `KUBECTL_VERSION`) so the CI/CD workflows stay in sync |
| Summary | Writes a job summary table with the mirrored tags and pull commands |

### Permissions

```yaml
permissions:
  contents: read
```

Only Docker Hub push and `gh variable set` (via `GITHUB_TOKEN`) are needed — no repo code write access required.

---

## Multi-Environment Image Promotion

Each environment is independently tracked by its values file:

| File | Updated by | Triggers | Kubernetes Namespace | Ingress URL |
|---|---|---|---|---|
| `values-dev.yaml` | `cicd.yaml` automatically (COMMIT_ID) | n/a (same workflow) | `<app_name>-dev` | `<app_name>-dev.test.com` |
| `values-staging.yaml` | User commits `image.tag` directly | `staging-cd.yaml` | `<app_name>-staging` | `<app_name>-staging.test.com` |
| `values-prod.yaml` | User commits `image.tag` directly | `prod-cd.yaml` | `<app_name>-prod` | `<app_name>-prod.test.com` |

Example — promote staging to `a1b2c3`, prod to `001122`:

```yaml
# values-staging.yaml
image:
  tag: a1b2c3    ← commit this change → staging-cd.yaml triggers → staging updated

# values-prod.yaml
image:
  tag: "001122"  ← commit this change → prod-cd.yaml triggers → prod updated
```

Git history on these files is the full audit trail of who promoted what and when.

---

## Required Secrets

| Secret | Used by | Description |
|---|---|---|
| `DOCKERHUB_USERNAME` | `cicd.yaml` CI job, `mirror-cli-binaries.yaml` | Docker Hub login |
| `DOCKERHUB_TOKEN` | `cicd.yaml` CI job, `mirror-cli-binaries.yaml` | Docker Hub access token |
| `ARGOCD_PASSWORD` | `cicd.yaml`, `staging-cd.yaml`, `prod-cd.yaml` | ArgoCD `admin` password |
| `GH_PAT` | `cicd.yaml`, `staging-cd.yaml`, `prod-cd.yaml` | GitHub PAT (`repo` scope) — used to register the repo in ArgoCD |

`GITHUB_TOKEN` is provided automatically by GitHub Actions (used for committing values files and updating repo variables).

## Required Repository Variables

| Variable | Default value | Description |
|---|---|---|
| `ARGOCD_VERSION` | `v3.4.2` | ArgoCD CLI version — read by `cicd.yaml`, `staging-cd.yaml`, `prod-cd.yaml`, and `mirror-cli-binaries.yaml` |
| `YQ_VERSION` | `v4.44.3` | yq version — read by `cicd.yaml` and `mirror-cli-binaries.yaml` |
| `KUBECTL_VERSION` | `v1.36.1` | kubectl version — read by `cicd.yaml`, `staging-cd.yaml`, `prod-cd.yaml`, and `mirror-cli-binaries.yaml` |

Set these once after scaffolding:

```bash
gh variable set ARGOCD_VERSION  --body "v3.4.2"  --repo christseng89/<app_name>
gh variable set YQ_VERSION      --body "v4.44.3" --repo christseng89/<app_name>
gh variable set KUBECTL_VERSION --body "v1.36.1" --repo christseng89/<app_name>
```

---

## Shared Runner Architecture

All apps scaffolded from this template share a single `github-runners` namespace for their GitHub Actions self-hosted runners. Each app keeps its own ServiceAccount and RunnerDeployment inside that namespace, and its own RoleBinding inside each env namespace.

### Cluster layout

```
Namespace: github-runners                                  ← shared, created once
  ├─ ServiceAccount:    <app>-self-hosted-runner           ← per-app
  ├─ ServiceAccount:    <other-app>-self-hosted-runner
  ├─ RunnerDeployment:  <app>-self-hosted-runner           ← per-app
  └─ RunnerDeployment:  <other-app>-self-hosted-runner

ClusterRole: arc-runner-reader                             ← shared, created once
  • pods, pods/log, events  (get/list/watch)
  • deployments, replicasets (get/list/watch)

Namespace: <app>-dev / <app>-staging / <app>-prod          ← per-app, per-env
  └─ RoleBinding: arc-runner-reader
       subject: <app>-self-hosted-runner @ github-runners
       roleRef:  ClusterRole arc-runner-reader
       (created by Helm chart, applied by ArgoCD on sync)
```

### Who creates what

| Resource | Created by | When |
|---|---|---|
| `Namespace github-runners` | `k8s/runner-rbac.yaml` via `setup.sh` step 1 | Once per cluster (idempotent on re-apply) |
| `ClusterRole arc-runner-reader` | `k8s/runner-rbac.yaml` via `setup.sh` step 1 | Once per cluster (idempotent on re-apply) |
| `ServiceAccount <app>-self-hosted-runner` | `k8s/runner-rbac.yaml` via `setup.sh` step 1 | Once per app |
| `RunnerDeployment <app>-self-hosted-runner` | `runnerdeployment.yaml` via `setup.sh` step 1 | Once per app |
| `RoleBinding arc-runner-reader` in `<app>-{env}` | `charts/<app>/templates/runner-rolebinding.yaml` via ArgoCD | On first sync of each env's ArgoCD app |

### Why split this way

- **`github-runners` is platform infra, not an app.** Putting it outside any ArgoCD-managed namespace avoids the trap where ArgoCD `auto-prune` deletes the runner pod (because it isn't in the Helm chart) and the ARC controller immediately recreates it — an infinite sync loop.
- **Per-app SA isolates runners.** `python-app1`'s runner cannot read pods in `python-app2-prod` because the RoleBindings only grant access from each app's own SA.
- **RoleBindings ship in the Helm chart.** The CD job doesn't need cluster-level RBAC permissions to create them — ArgoCD applies them as part of each env's sync. Removing the ArgoCD app removes the RoleBinding cleanly.

### Scaling to a second app

Running `setup.sh` for a new app from this template:

1. `kubectl apply -f k8s/runner-rbac.yaml` — re-applies `Namespace github-runners` and `ClusterRole arc-runner-reader` as no-ops; creates the new `ServiceAccount <new-app>-self-hosted-runner`.
2. `kubectl apply -f runnerdeployment.yaml` — creates a new `RunnerDeployment <new-app>-self-hosted-runner` in `github-runners`.
3. First `cicd.yaml` run — ArgoCD creates `<new-app>-dev` namespace and the per-env RoleBinding inside it.

No coordination with other apps is needed; the only cluster-level shared resource is the ClusterRole, which is read-only.

### Component name length cap

Because the runner pod name is `<app>-self-hosted-runner-<rs-hash>-<pod-hash>` (~17 chars of suffix) and Kubernetes enforces a 63-char DNS label limit on pod names, the Backstage template caps `component_id` at **30 chars**. This leaves ~16 chars of safety margin.

---

## Docker Hub Mirror Images

The `docker create` / `docker cp` pattern extracts each binary from a `FROM scratch` image without running a container. No `docker login` is needed to pull the public mirror images.

See [`mirror-cli-binaries.yaml`](#mirror-cli-binariesyaml--mirror-cli-binaries-to-docker-hub) for how the mirrors are built and when to run the workflow.

---

## Troubleshooting

**`cicd.yaml` never starts**
- Confirm the change touched a file under `src/`. Changes to `charts/`, `.github/`, or the repo root do not match the path filter.

**`staging-cd.yaml` or `prod-cd.yaml` never starts after editing a values file**
- Confirm you edited the matching file — `staging-cd.yaml` only watches `values-staging.yaml`, `prod-cd.yaml` only watches `values-prod.yaml`. `values-dev.yaml` is intentionally excluded (updated by `cicd.yaml`, not the user).
- Confirm the commit landed on `main`, not a feature branch.
- Confirm the commit actually touched the values file (e.g. a no-op formatting change that ends up identical to the previous version still won't trigger).

**CI fails on "Login to Docker Hub"**
- Verify secrets are set: `gh secret list --repo christseng89/<app_name>`

**CD fails on yq/kubectl/argocd pull hanging or timing out**
- The runner pod may lack internet egress. Check network policies in the `github-runners` namespace.
- Run `mirror-cli-binaries.yaml` first if the Docker Hub mirror for that version doesn't exist yet.

**`Diagnose on failure` output is empty or shows `Forbidden`**
- The runner SA RoleBinding is missing in the target namespace. This RoleBinding ships in the Helm chart (`charts/<app>/templates/runner-rolebinding.yaml`) and is created on first ArgoCD sync. If the first sync never succeeded (e.g. dev failed to deploy), the RoleBinding doesn't exist yet and `Diagnose` runs without permissions.
- Verify: `kubectl get rolebinding -n <app>-dev arc-runner-reader`. If missing, fix the underlying sync failure and the RoleBinding will be created automatically next run.

**`staging-cd.yaml` or `prod-cd.yaml` skips deployment with "image.tag is empty"**
- Set `image.tag` in the matching values file (`values-staging.yaml` or `values-prod.yaml`) to a real tag and commit again.

**ArgoCD sync fails with `UNAUTHENTICATED`**
- The `ARGOCD_PASSWORD` secret is stale. Rotate: `gh secret set ARGOCD_PASSWORD --body <new> --repo christseng89/<app_name>`

**ArgoCD repo registration fails with permission error**
- The `GH_PAT` secret is missing or expired. Create a new PAT with `repo` scope and update: `gh secret set GH_PAT --body <token> --repo christseng89/<app_name>`

**ArgoCD wait times out (`context deadline exceeded`)**
- The `--timeout 180` expired. Check "Diagnose on failure" output for pod events and logs.
- Common causes: bad image tag, Docker Hub rate limit, failing readiness probe at `/api/v1/healthz`.

**"Commit changes" fails with a merge conflict**
- Another commit landed on `main` between checkout and push. The `--rebase --autostash` strategy handles most cases automatically. If it still fails, re-run manually from the Actions tab.

**CD fails pulling argocd or yq with "manifest unknown"**
- The mirror image for that version does not exist on Docker Hub yet. Run `mirror-cli-binaries.yaml` first with the required version, then re-run the CD job.

**`mirror-cli-binaries.yaml` fails on "Login to Docker Hub"**
- Verify `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets are set on the repo.

**`mirror-cli-binaries.yaml` curl step times out**
- GitHub Releases may be temporarily slow. Re-run the workflow — the `--retry 3` flag handles transient failures automatically.

**Workflow reads wrong tool version**
- Confirm the repo variable is set: `gh variable list --repo christseng89/<app_name>`
- If you updated the variable manually in Settings, the cache key for the old version is now stale — the next run will re-download automatically.
