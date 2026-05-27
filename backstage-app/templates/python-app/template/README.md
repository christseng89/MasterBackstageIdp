# ${{values.app_name}}

This repo was scaffolded from the `python-app` Backstage template.
One setup script handles all post-scaffolding bootstrap — run it once after cloning.
ArgoCD apps are created automatically on the first successful pipeline run.

---

## What Was Created

```
christseng89/${{values.app_name}}/
├── .github/workflows/
│   ├── ${{values.app_name}}-cicd.yaml       ← CI + deploy to dev (auto on src/ push)
│   ├── ${{values.app_name}}-staging-cd.yaml ← promote to staging (auto on values-staging.yaml change)
│   ├── ${{values.app_name}}-prod-cd.yaml    ← promote to prod (auto on values-prod.yaml change)
│   └── mirror-cli-binaries.yaml             ← mirror tool binaries to Docker Hub (manual)
├── charts/${{values.app_name}}/
│   ├── values.yaml                           ← base Helm defaults
│   ├── values-dev.yaml                       ← image.tag written by cicd.yaml automatically
│   ├── values-staging.yaml                   ← set image.tag here to promote to staging
│   ├── values-prod.yaml                      ← set image.tag here to promote to prod
│   └── templates/                            ← Deployment, Service, Ingress
├── src/                                      ← application source code
├── Dockerfile
├── catalog-info.yaml                         ← Backstage component registration
├── runnerdeployment.yaml                     ← ARC self-hosted runner spec
├── setup.sh                                  ← bootstrap: secrets/variables set per-repository
├── setup-org.sh                              ← bootstrap: secrets/variables set at org level (shared)
└── mkdocs.yaml + docs/                       ← TechDocs source
```

---

## Admin Setup (run once after scaffolding)

### 1. Clone and enter the repo

```bash
git clone https://github.com/christseng89/${{values.app_name}}.git
cd ${{values.app_name}}
```

### 2. Create `.env`

Both setup scripts source this file before doing anything. Create it in the repo root:

```bash
cat > .env <<'EOF'
# --- Required ---
DOCKERHUB_USERNAME=your-dockerhub-username
DOCKERHUB_TOKEN=your-dockerhub-access-token
ARGOCD_PASSWORD=your-argocd-admin-password
GITHUB_PAT=your-github-personal-access-token   # needs repo scope

# --- Optional: override tool versions (defaults shown) ---
# ARGOCD_VERSION=v3.4.2
# YQ_VERSION=v4.44.3
# KUBECTL_VERSION=v1.36.1
EOF
```

> `.env` is git-ignored — never commit it.

### 3. Choose and run a setup script

Two scripts are provided. Pick the one that matches your GitHub setup:

| | `setup.sh` | `setup-org.sh` |
|---|---|---|
| **Secrets/variables scope** | This repository only | `intelligent-ltd` org (all repos inherit) |
| **When to use** | Standalone repo or personal account | Multiple scaffolded repos sharing the same credentials |
| **gh token scope needed** | `repo` | `repo` + `admin:org` |
| **Idempotent on re-run** | Overwrites existing values | Skips any secret/variable already present in the org |

**Option A — per-repository (setup.sh)**

```bash
gh auth login          # one-time, if not already authenticated
bash setup.sh          # runs all steps and triggers the first CI/CD pipeline
```

**Option B — org-level (setup-org.sh)**

Your `gh` token must have the `admin:org` scope. If needed, refresh it first:

```bash
gh auth refresh -s admin:org
bash setup-org.sh      # sets secrets/variables in intelligent-ltd org, then triggers pipeline
```

Common flags (work with either script):

```bash
bash setup.sh --skip-mirror               # skip mirroring if Docker Hub images already exist
bash setup.sh --skip-cicd                 # skip triggering the first pipeline run
bash setup.sh --skip-mirror --skip-cicd
```

### 4. Add Windows hosts entry (manual — requires Administrator)

The setup scripts detect whether Git Bash is running as Administrator. If not, they print the
command but cannot write the hosts file automatically. Open **PowerShell as Administrator** and run:

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-dev.test.com"
```

> Skip if the entry already exists.

### 5. Verify

Once the first pipeline run succeeds:

- ArgoCD dashboard: `http://argocd.test.com:9080/`
- App (dev): `http://${{values.app_name}}-dev.test.com:9080/`

---

## Normal Workflow After Setup

### Deploy to Dev — push source changes

```bash
git add src/
git commit -m "your change"
git push origin main
```

```
cicd.yaml triggers automatically
  → builds christseng89/${{values.app_name}}:<sha>   (docker build + push to Docker Hub)
  → writes <sha> into values-dev.yaml               (helm values update)
  → ArgoCD creates/syncs ${{values.app_name}}-dev   (helm upgrade --install)
  → accessible at ${{values.app_name}}-dev.test.com:9080
```

### Promote to Staging

Find the image tag currently deployed in dev:

```bash
grep tag charts/${{values.app_name}}/values-dev.yaml
```

Edit `charts/${{values.app_name}}/values-staging.yaml`:

```yaml
image:
  tag: a1b2c3    # replace with the tag tested in dev
```

```bash
git add charts/${{values.app_name}}/values-staging.yaml
git commit -m "promote staging to a1b2c3"
git push origin main
```

```
staging-cd.yaml triggers automatically
  → ArgoCD creates/syncs ${{values.app_name}}-staging
  → accessible at ${{values.app_name}}-staging.test.com:9080
```

### Promote to Prod

Edit `charts/${{values.app_name}}/values-prod.yaml`:

```yaml
image:
  tag: a1b2c3    # replace with the tag validated in staging
```

```bash
git add charts/${{values.app_name}}/values-prod.yaml
git commit -m "promote prod to a1b2c3"
git push origin main
```

```
prod-cd.yaml triggers automatically
  → ArgoCD creates/syncs ${{values.app_name}}-prod
  → accessible at ${{values.app_name}}-prod.test.com:9080
```

> The image tag is the first 6 characters of the Git commit SHA (e.g. `a1b2c3`).
> Git history on `values-staging.yaml` and `values-prod.yaml` is the full audit
> trail of who promoted what version and when.

---

## Appendix: What the Setup Scripts Do

Both scripts run the same six steps in order. Steps 2 and 3 differ between the two.
The flags `--skip-mirror` and `--skip-cicd` skip steps 4 and 6 respectively.

### Step 1 — Register the Self-Hosted Runner

Applies the ARC runner and its RBAC to the local Docker Desktop Kubernetes cluster:

```bash
kubectl config use-context docker-desktop
kubectl apply -f k8s/runner-rbac.yaml
kubectl apply -f runnerdeployment.yaml
```

`runner-rbac.yaml` creates the shared `github-runners` namespace, a per-app
ServiceAccount, and the `arc-runner-reader` ClusterRole. All three are idempotent —
safe to re-run when bootstrapping additional apps from this template.

---

### Step 2 — Set GitHub Actions Secrets

**`setup.sh` — per-repository**

Sets four secrets directly on this repo:

```bash
gh secret set DOCKERHUB_USERNAME --body "$DOCKERHUB_USERNAME" --repo christseng89/${{values.app_name}}
gh secret set DOCKERHUB_TOKEN    --body "$DOCKERHUB_TOKEN"    --repo christseng89/${{values.app_name}}
gh secret set ARGOCD_PASSWORD    --body "$ARGOCD_PASSWORD"    --repo christseng89/${{values.app_name}}
gh secret set GH_PAT             --body "$GITHUB_PAT"         --repo christseng89/${{values.app_name}}
```

**`setup-org.sh` — org-level**

Checks each secret in the `intelligent-ltd` org first; only sets it if absent:

```bash
# for each of: DOCKERHUB_USERNAME, DOCKERHUB_TOKEN, ARGOCD_PASSWORD, GH_PAT
if <secret already exists in org>; then
  echo "$name already exists in org — skipping."
else
  gh secret set "$name" --body "..." --org intelligent-ltd --visibility all
fi
```

All repos in the org inherit org-level secrets automatically — no per-repo configuration needed
for subsequent scaffolded apps.

`GH_PAT` (from `GITHUB_PAT`) is used by the CD jobs to register this repo in ArgoCD
via `argocd repo add`. Create one at GitHub → Settings → Developer settings →
Personal access tokens with **`repo`** scope.

---

### Step 3 — Set GitHub Actions Variables

**`setup.sh` — per-repository**

Sets three tool-version variables on this repo:

```bash
gh variable set ARGOCD_VERSION  --body "$ARGOCD_VERSION"  --repo christseng89/${{values.app_name}}
gh variable set YQ_VERSION      --body "$YQ_VERSION"       --repo christseng89/${{values.app_name}}
gh variable set KUBECTL_VERSION --body "$KUBECTL_VERSION"  --repo christseng89/${{values.app_name}}
```

**`setup-org.sh` — org-level**

Checks each variable in the `intelligent-ltd` org first; only sets it if absent:

```bash
# for each of: ARGOCD_VERSION, YQ_VERSION, KUBECTL_VERSION
if <variable already exists in org>; then
  echo "$name already exists in org — skipping."
else
  gh variable set "$name" --body "..." --org intelligent-ltd --visibility all
fi
```

Defaults (`v3.4.2` / `v4.44.3` / `v1.36.1`) are used unless overridden in `.env`.
Variables (not secrets) let `mirror-cli-binaries.yaml` update them automatically
when a version override is passed as a workflow input.

---

### Step 4 — Mirror CLI Binaries to Docker Hub

Triggers `mirror-cli-binaries.yaml` via `gh workflow run` and watches it complete.
This mirrors `argocd`, `yq`, and `kubectl` to Docker Hub as `FROM scratch` multi-arch
images before the first CD run needs them.

Skip with `--skip-mirror` if the mirrors already exist at the configured versions.

---

### Step 5 — Add Windows Hosts Entry

Checks whether Git Bash is running as Administrator. If yes, writes the entry directly:

```
127.0.0.1 ${{values.app_name}}-dev.test.com
```

If not running as Administrator, prints the PowerShell command to run manually (see
Admin Setup step 4 above) and exits with an error so the issue is not silently skipped.

---

### Step 6 — Trigger the First CI/CD Run

Triggers `${{values.app_name}}-cicd.yaml` via `gh workflow run` and watches it complete.
The workflow: builds the Docker image (CI job on `ubuntu-latest`), pushes it to
Docker Hub, writes the image tag into `values-dev.yaml`, then registers the GitHub
repo in ArgoCD, creates the ArgoCD app if absent, and syncs it (CD job on the
self-hosted ARC runner).

Skip with `--skip-cicd` to trigger the pipeline manually later from the Actions tab.
