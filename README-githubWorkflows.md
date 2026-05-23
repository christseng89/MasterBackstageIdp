# GitHub Actions Workflows

This repository has two workflows under `.github/workflows/`.

---

## 1. `cicd.yaml` — CI/CD Pipeline

### Purpose

Triggered automatically on every push to `python-app/src/**` on `main`. Builds a multi-arch Docker image, updates the Helm values file with the new image tag, and deploys to Kubernetes via ArgoCD.

### Trigger

| Event | Condition |
|---|---|
| `push` | Files under `python-app/src/**` on branch `main` |
| `workflow_dispatch` | Manual re-run (redeploy without a code change) |

### Concurrency

Runs are serialized per branch (`cicd-${{ github.ref }}`). `cancel-in-progress: false` ensures a CD job already syncing ArgoCD is never killed mid-flight by a second push.

### Permissions

`contents: write` — required for the CD job to commit the updated `values.yaml` back to `main`.

### Repository Variables (Settings → Variables)

| Variable | Example | Purpose |
|---|---|---|
| `ARGOCD_VERSION` | `v3.4.2` | ArgoCD CLI version pulled from Docker Hub mirror |
| `YQ_VERSION` | `v4.44.3` | yq version pulled from Docker Hub mirror |
| `KUBECTL_VERSION` | `v1.36.1` | kubectl version pulled from Docker Hub mirror |

### Secrets Required

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub login for pushing the app image |
| `DOCKERHUB_TOKEN` | Docker Hub token |
| `ARGOCD_PASSWORD` | ArgoCD admin password for CLI login |
| `GH_PAT` | GitHub PAT (`repo` scope) — used to register the repo in ArgoCD |

### Jobs

#### `ci` — runs on `ubuntu-latest`

| Step | What it does |
|---|---|
| Checkout | Clones the repository |
| Shorten commit id | Derives a 6-char image tag from `GITHUB_SHA` |
| Set up QEMU + Buildx | Enables cross-architecture emulation for multi-arch builds |
| Login to Docker Hub | Authenticates with Docker Hub |
| Build and push | Builds `linux/amd64` + `linux/arm64` image tagged `christseng89/python-app:<commit_id>`; uses a registry-backed layer cache to save 60–120s |

Output: `commit_id` (passed to the `cd` job).

#### `cd` — runs on `[self-hosted, linux]` (ARC runner inside the cluster)

The self-hosted runner is required because ArgoCD is reached via in-cluster DNS (`argocd-server.argocd.svc.cluster.local`), which is not reachable from GitHub-hosted runners.

| Step | What it does |
|---|---|
| Checkout | Clones the repo using `GITHUB_TOKEN` |
| Detect runner architecture | Resolves `amd64` or `arm64` for platform-specific pulls |
| Cache + Install kubectl | Pulls `christseng89/kubectl-bin:<KUBECTL_VERSION>` from Docker Hub mirror; cached by version+arch |
| Cache + Modify values file | Pulls `christseng89/yq-bin:<YQ_VERSION>` from Docker Hub mirror; updates `image.tag` in `values.yaml` |
| Commit changes | Commits and pushes the updated `values.yaml` using `EndBug/add-and-commit@v9` with `--rebase --autostash` to handle concurrent pushes |
| Cache + Install ArgoCD CLI | Pulls `christseng89/argocd-bin:<ARGOCD_VERSION>` from Docker Hub mirror; cached by version+arch |
| ArgoCD login | Authenticates with ArgoCD server using `--plaintext --grpc-web` (server runs with `server.insecure: true`) |
| Register GitHub repo in ArgoCD | Calls `argocd repo add --upsert` with `GH_PAT` — ensures credentials survive cluster rebuilds |
| Create ArgoCD app if absent | Creates the `python-app` ArgoCD Application with automated sync, auto-prune, self-heal, and `CreateNamespace=true` if it does not already exist; uses `--validate=false` to avoid Helm render timeouts on first access |
| ArgoCD app sync | Runs `argocd app sync` then `argocd app wait --health --timeout 180` — blocks until pods are healthy |
| Diagnose on failure | Runs only on failure; dumps `argocd app get`, `argocd app history`, `kubectl get pods`, `kubectl describe deploy`, and `kubectl logs` in one step |

### Binary Caching Strategy

The ARC runner cannot reach `dl.k8s.io` or GitHub Releases directly (network constraints). All three CLI tools are pulled from public Docker Hub mirrors (`christseng89/*-bin`) using `docker pull` + `docker create` + `docker cp`. Each binary is cached in `/tmp/` with a key of `<tool>-<arch>-<version>` so warm runs skip the pull entirely.

### ArgoCD App Specification (auto-created)

| Field | Value |
|---|---|
| Application Name | `python-app` |
| Project | `default` |
| Sync Policy | Automatic (auto-prune + self-heal) |
| Auto-Create Namespace | Enabled |
| Repository URL | `https://github.com/christseng89/MasterBackstageIdp.git` |
| Revision | `main` |
| Path | `python-app/charts/python-app` |
| Cluster URL | `https://kubernetes.default.svc` |
| Namespace | `python-app` |
| Values File | `values.yaml` |

### Full Pipeline Flow

```
push to python-app/src/**
        │
        ▼
   ┌─── ci (ubuntu-latest) ───────────────────────────┐
   │  Build multi-arch Docker image                    │
   │  Push christseng89/python-app:<commit_id>         │
   └──────────────────────────────────────────────────┘
        │ commit_id
        ▼
   ┌─── cd (self-hosted ARC runner) ──────────────────┐
   │  Update python-app/charts/python-app/values.yaml │
   │  Commit & push values.yaml → main                 │
   │  Register GitHub repo credentials in ArgoCD       │
   │  Create ArgoCD app (if first run)                 │
   │  argocd app sync → app wait --health              │
   └──────────────────────────────────────────────────┘
        │
        ▼
   ArgoCD reconciles → Kubernetes rolls out new pods
```

---

## 2. `mirror-cli-binaries.yaml` — CLI Binary Mirror

### Purpose

Downloads ArgoCD, yq, and kubectl binaries from their upstream GitHub Releases and re-publishes them as multi-arch Docker images on Docker Hub. The CD pipeline pulls from these mirrors instead of upstream because the self-hosted ARC runner (in-cluster) cannot reliably reach GitHub Releases or `dl.k8s.io` from inside Docker Desktop.

### Trigger

`workflow_dispatch` only — run manually from the **Actions** tab whenever a tool version is bumped.

### Permissions

`contents: read` — no write access needed.

### Repository Variables (single source of truth)

Versions are stored as repository variables (Settings → Variables). The workflow inputs override them for a single run; leaving inputs blank uses the repo variable automatically.

| Variable | Example |
|---|---|
| `ARGOCD_VERSION` | `v3.4.2` |
| `YQ_VERSION` | `v4.44.3` |
| `KUBECTL_VERSION` | `v1.36.1` |

### Inputs

| Input | Default | Behaviour |
|---|---|---|
| `argocd_version` | _(blank)_ | Override for this run; blank = use `ARGOCD_VERSION` repo variable |
| `yq_version` | _(blank)_ | Override for this run; blank = use `YQ_VERSION` repo variable |
| `kubectl_version` | _(blank)_ | Override for this run; blank = use `KUBECTL_VERSION` repo variable |

Leaving all inputs blank mirrors all three tools using the current repo variable values.

### Secrets Required

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub login |
| `DOCKERHUB_TOKEN` | Docker Hub token (read+write) |

### Steps

| Step | What it does |
|---|---|
| Login to Docker Hub | Authenticates for pushing mirror images |
| Set up QEMU + Buildx | Enables multi-arch manifest builds from an amd64 runner |
| Mirror ArgoCD CLI | Downloads `argocd-linux-amd64` + `argocd-linux-arm64` from GitHub Releases; packages into a `FROM scratch` image; pushes `christseng89/argocd-bin:<version>` |
| Mirror yq | Same pattern for yq from `github.com/mikefarah/yq` |
| Mirror kubectl | Same pattern for kubectl from `dl.k8s.io` |
| Update repo variables | If any input was non-blank, writes the new version back to the GitHub repo variable so `cicd.yaml` stays in sync automatically |
| Summary | Writes a markdown table to the GitHub Actions job summary showing each mirrored image and its pull command |

### Mirror Image Format

Each binary is packaged as a minimal `FROM scratch` image with a `CMD` set so `docker create` works without supplying an argument. The CD pipeline extracts the binary with `docker cp` — the container is never run.

```dockerfile
FROM scratch
ARG TARGETARCH
COPY <tool>-${TARGETARCH} /<tool>
CMD ["/<tool>"]
```

### Version Bump Workflow

```
1. Decide new version (e.g. ARGOCD_VERSION=v3.5.0)
2. Trigger mirror-cli-binaries with argocd_version=v3.5.0
   → Binary mirrored to christseng89/argocd-bin:v3.5.0
   → ARGOCD_VERSION repo variable updated to v3.5.0
3. Next cicd.yaml run picks up v3.5.0 from vars.ARGOCD_VERSION automatically
```

Or trigger via CLI to pre-fill all inputs from the repo variables:

```bash
gh workflow run mirror-cli-binaries.yaml \
  --field argocd_version=$(gh variable get ARGOCD_VERSION --repo christseng89/MasterBackstageIdp) \
  --field yq_version=$(gh variable get YQ_VERSION --repo christseng89/MasterBackstageIdp) \
  --field kubectl_version=$(gh variable get KUBECTL_VERSION --repo christseng89/MasterBackstageIdp) \
  --repo christseng89/MasterBackstageIdp
```

---

## Relationship Between the Two Workflows

```
mirror-cli-binaries          cicd
─────────────────────        ──────────────────────────────────
Run once per version bump → produces Docker Hub mirror images
                             consumed by CD job on every push
                             via docker pull + docker cp
```

`mirror-cli-binaries` is a prerequisite that must be run before `cicd` can use a new tool version. The repo variables (`ARGOCD_VERSION`, `YQ_VERSION`, `KUBECTL_VERSION`) are the shared contract between the two workflows.
