# Master Backstage IdP

A hands-on learning project that walks the full **Internal Developer Portal (IDP)** workflow end-to-end:

> Source code → Docker image → Helm chart → ArgoCD → Kubernetes — with the service registered in a Backstage catalog and a GitHub Actions pipeline orchestrating every step.

The result is a tight feedback loop where editing `python-app/src/app.py` and pushing to `main` automatically builds a new container image, updates the Helm values, syncs ArgoCD, and rolls out a new pod — all without any manual `kubectl` or `docker` commands.

## Architecture at a Glance

```text
┌─────────────┐ push  ┌──────────────────┐ build  ┌──────────────────────┐
│  Developer  │ ────▶ │  GitHub (main)   │ ─────▶ │       Docker Hub     │
└─────────────┘       └──────────────────┘ image  │ christseng89/        │
                            │                     │  python-app:<sha>    │
                            │ ci/cd workflow:     │  argocd-bin:v3.4.2   │
                            │  bumps image.tag    │  yq-bin:v4.44.3      │
                            │  in values.yaml     └──────────┬───────────┘
                            ▼                                │ pull
                      ┌──────────────────┐ sync   ┌──────────▼───────────┐
                      │ charts/.../values│ ─────▶ │      ArgoCD          │
                      └──────────────────┘        │  (in-cluster sync)   │
                                                  └──────────┬───────────┘
                                                             │ apply
                                                             ▼
                                                  ┌──────────────────────┐
                                                  │     Kubernetes       │
                                                  │     (python-app)     │
                                                  └──────────────────────┘
```

> The Docker Hub mirror tags (`argocd-bin`, `yq-bin`) exist so the CD job inside the cluster can pull CLI binaries quickly via Cloudflare's CDN instead of the slower GitHub Releases path. They're populated once per version by the `mirror-cli-binaries` workflow (Part 5, Step 5).

## Repository Layout

| Path | Purpose |
|---|---|
| `python-app/src/` | Flask app source — every push here triggers CI/CD |
| `python-app/Dockerfile` | Container image definition (multi-arch via QEMU) |
| `python-app/charts/python-app/` | **The** Helm chart — ArgoCD watches this, CI/CD updates `values.yaml` here |
| `python-app/charts/nginx/` | Values override for the Nginx Ingress Controller install |
| `python-app/charts/argocd/` | Values override for the ArgoCD install |
| `python-app/k8s/` | Raw Kubernetes manifests (alternative to Helm, for direct `kubectl apply`) |
| `python-app/catalog-info.yaml` | Backstage catalog registration |
| `python-app/runnerdeployment.yaml` | ARC self-hosted runner manifest |
| `.github/workflows/cicd.yaml` | Authoritative CI/CD workflow (build + deploy on every push) |
| `.github/workflows/mirror-cli-binaries.yaml` | One-shot mirror workflow — copies `argocd` + `yq` from GitHub Releases to Docker Hub for fast pulls from Asia |
| `README.md` | This file — setup, architecture, parts 1–7 |
| `README-troubleshooting.md` | Categorised troubleshooting for every issue encountered during development |
| `backstage/` | Backstage app (Git submodule) |
| `charts/` | Backstage Helm chart fork (Git submodule, unrelated to python-app) |

## Prerequisites

Tested on Windows 11 (Surface Pro 11 / Snapdragon X, ARM64) with Docker Desktop. Other Linux / macOS hosts work with minor command translation (paths, `Add-Content` → `echo … >> /etc/hosts`).

| Tool | Version | Purpose |
|---|---|---|
| Docker Desktop | latest, with Kubernetes enabled | Container runtime + local k8s cluster |
| `kubectl` | matches your cluster | Cluster CLI |
| `helm` | 3.x | Chart installer |
| Python | 3.12.10 (via `pyenv`) | Local app dev |
| `uv` | latest | Python dependency manager |
| Git | 2.40+ | Submodule support |
| A Docker Hub account | — | Image registry |
| A GitHub account with admin on this repo | — | Actions secrets + ARC PAT |

> Throughout this guide, replace `christseng89` with your own Docker Hub and GitHub username wherever it appears.

---

## Part 1 — Clone & Local Development

### Clone the Repository

```cmd
git clone --recurse-submodules https://github.com/christseng89/MasterBackstageIdp.git
cd MasterBackstageIdp
```

If you cloned without `--recurse-submodules`, initialize the submodules afterwards:

```cmd
git submodule update --init --recursive
```

### Run the Python App Locally

```cmd
cd python-app
pyenv local 3.12.10

uv sync
uv pip install -r requirements.txt

uv run main.py
```

Expected output:

```text
Hello from python-app!
```

Run the Flask server directly:

```cmd
uv run src\app.py
```

Then visit:

- <http://127.0.0.1:5000>
- <http://127.0.0.1:5000/api/v1/info>
- <http://127.0.0.1:5000/api/v1/healthz>

### Build & Run with Docker

```cmd
cd python-app
docker build -t python-app:latest .
docker run -d -p 5000:5000 --name python-app python-app:latest
```

Verify the running container:

```cmd
curl http://127.0.0.1:5000/api/v1/info
curl http://127.0.0.1:5000/api/v1/healthz
```

Inspect from inside the container:

```cmd
docker exec -it python-app sh
```

```sh
apk add curl
curl http://localhost:5000/api/v1/info
exit
```

Tear it down:

```cmd
docker logs python-app
docker stop python-app
docker rm python-app
```

Push the image to Docker Hub (requires `docker login` first):

```cmd
docker tag python-app:latest christseng89/python-app:latest
docker push christseng89/python-app:latest
```

---

## Part 2 — Kubernetes Cluster Setup

### Sanity-check the Cluster

```cmd
kubectl cluster-info
kubectl get nodes
kubectl get ns
```

You should see `docker-desktop` as the only node and the standard system namespaces.

### Configure Local DNS

The ingress rules expose hostnames `python-app.test.com` and `argocd.test.com`. Map them to your loopback so your browser can reach them through the local Nginx ingress.

PowerShell (as Administrator):

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 python-app.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 argocd.test.com"
```

Or edit the file by hand:

```cmd
notepad C:\Windows\System32\drivers\etc\hosts
```

Add:

```text
127.0.0.1       python-app.test.com
127.0.0.1       argocd.test.com
```

### Install Nginx Ingress Controller

```bash
cd python-app
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f charts/nginx/values-nginx.yaml
```

Verify the controller is reachable on port 9080:

```cmd
kubectl get svc -n ingress-nginx
curl http://localhost:9080
```

---

## Part 3 — Manual Deployment (Learning Path)

These are the manual paths for learning and ad-hoc testing. The production path is GitOps via ArgoCD (Part 4).

### Method A — Raw `kubectl` Manifests

```cmd
cd python-app
kubectl apply -f k8s/python-app.yaml
kubectl get all
```

Verify behind the local DNS entry:

```cmd
curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz
```

Tear it down:

```cmd
kubectl delete -f k8s/python-app.yaml
```

### Method B — Helm (Manual Install)

Tag and push a versioned image first:

```cmd
docker tag christseng89/python-app:latest christseng89/python-app:v2
docker push christseng89/python-app:v2
```

Install into the `default` namespace (dry-run first to inspect the rendered manifests):

```cmd
helm install python-app charts\python-app --dry-run --debug
helm install python-app charts\python-app --set image.tag=v2

helm ls
kubectl get all
```

Verify and uninstall:

```cmd
curl http://python-app.test.com:9080/api/v1/info
helm uninstall python-app
```

Or install into a dedicated `python-app` namespace (matches the ArgoCD setup in Part 4):

```bash
helm install python-app charts/python-app \
  --set image.tag=v2 -n python-app --create-namespace

helm ls -n python-app
kubectl get all -n python-app

curl http://python-app.test.com:9080/api/v1/info

helm uninstall python-app -n python-app
```

---

## Part 4 — GitOps with ArgoCD

ArgoCD will watch the Helm chart in this repo and reconcile the cluster to match. Once configured, you should never need to run `helm install` manually again.

### Install ArgoCD

Reference: <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>

```bash
cd python-app
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f charts/argocd/values-argo.yaml
```

Verify the ingress is up:

```cmd
kubectl get ingress -n argocd
curl http://argocd.test.com:9080
```

### Retrieve the Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

> Save this value — you'll need it for both the browser login and the `ARGOCD_PASSWORD` GitHub secret in Part 5.

Log in via the browser at <http://argocd.test.com:9080> with username `admin` and the password you just retrieved.

### Connect the Repository

You'll need a GitHub Personal Access Token (PAT) so ArgoCD can read this repo.

1. Visit <https://github.com/settings/tokens> → **Generate new token (classic)**.
2. Name: `MasterBackstageIdp`, scopes: `repo` (full control).
3. Generate, then **copy immediately** — GitHub only shows it once.

In ArgoCD → **Settings → Repositories → Connect Repo**:

| Field | Value |
|---|---|
| Connection Method | VIA HTTPS |
| Name | `MasterBackstageIdp` |
| Project | `default` |
| Repository URL | `https://github.com/christseng89/MasterBackstageIdp.git` |
| Username | `christseng89` |
| Password | _your GitHub PAT_ |

### Create the `python-app` Application

In ArgoCD → **Applications → New App**:

| Field | Value |
|---|---|
| Application Name | `python-app` |
| Project | `default` |
| **Sync Policy** | **Automatic** (with **Auto-Create Namespace** ✅) |
| Repository URL | `https://github.com/christseng89/MasterBackstageIdp.git` |
| Revision | `main` |
| **Path** | **`python-app/charts/python-app`** |
| Cluster URL | `https://kubernetes.default.svc` |
| Namespace | `python-app` |
| Values Files | `values.yaml` |

> ⚠️ **Critical:** the `Path` must exactly match `python-app/charts/python-app`. The CD job in `.github/workflows/cicd.yaml` writes the new image tag into `python-app/charts/python-app/values.yaml`. Any other path means `argocd app sync` sees no diff and the pod is never updated.

Click **Create**, wait for the first sync, and verify:

```cmd
curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz
```

---

## Part 5 — CI/CD Automation (GitHub Actions)

Two workflow files cooperate, with each job placed on the runner type that matches its needs:

| File / Job | Where it runs | When | Why this runner |
|---|---|---|---|
| `cicd.yaml` → `ci` job | **GitHub-hosted `ubuntu-latest`** | Every push to `python-app/src/**` (or manual `workflow_dispatch`) | IO-heavy: needs fast access to GitHub Releases (for buildx/QEMU) and Docker Hub. Doesn't need cluster access. |
| `cicd.yaml` → `cd` job | **Self-hosted Linux runners (ARC) inside your cluster** | After `ci` succeeds | Must reach `argocd-server.argocd.svc.cluster.local` via in-cluster DNS — only ARC pods can. |
| `mirror-cli-binaries.yaml` | **GitHub-hosted `ubuntu-latest`** | Manual `workflow_dispatch`, once per `argocd` / `yq` version bump | Pure IO: download GitHub Releases → push Docker Hub. Both are public services; cluster access not needed. |

> 💡 **Don't move the `ci` job to ARC** — every tool installer (`docker/setup-buildx-action`, `docker/setup-qemu-action`, `actions/cache`) downloads from GitHub Releases / GitHub cache service. From an ARC pod in Asia these can run at 0.1 MB/s and trip the job timeout. Keep `ci` on `ubuntu-latest` and only `cd` on ARC.

### How It Works

```text
push to main (changes under python-app/src/**)  |  workflow_dispatch
                                │
                                ▼
┌──────────────────────────────────────────────────────────────┐
│  ci   (runs-on: ubuntu-latest, GitHub-hosted)                │
│   1. Checkout                                                │
│   2. Shorten commit id → COMMIT_ID (first 6 chars of SHA)    │
│   3. Set up QEMU + Buildx (multi-arch emulation)             │
│   4. Login to Docker Hub                                     │
│   5. Build & push christseng89/python-app:<COMMIT_ID>        │
│      (linux/amd64 + linux/arm64, registry-side build cache   │
│      via :buildcache tag)                                    │
└──────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────┐
│  cd   (runs-on: [self-hosted, linux] — ARC in cluster)       │
│   1. Checkout                                                │
│   2. Detect runner arch → amd64 / arm64                      │
│   3. Cache yq binary (actions/cache, keyed by version+arch)  │
│   4. Modify values.yaml:                                     │
│        • cache miss → docker pull mirror (retry 3×) + extract│
│        • cache hit  → use /tmp/yq directly                   │
│      Then `yq -i .image.tag = <COMMIT_ID>` on values.yaml    │
│   5. Commit + push (--rebase --autostash) via add-and-commit │
│   6. Cache argocd CLI (actions/cache, keyed by version+arch) │
│   7. Install argocd CLI (same docker-pull-or-cache pattern)  │
│   8. argocd login (in-cluster service DNS, --plaintext       │
│        --grpc-web, password as flag — argocd has no stdin)   │
│   9. argocd app sync python-app                              │
│  10. argocd app wait --health --timeout 180                  │
│  11. (on failure) Diagnose: argocd app get + history,        │
│      kubectl pods/describe/logs                              │
└──────────────────────────────────────────────────────────────┘
```

The CD job talks to ArgoCD via the in-cluster service DNS `argocd-server.argocd.svc.cluster.local` — not through `argocd.test.com:9080`. The ingress hostname only resolves on your laptop via the Windows hosts file, which ARC runner pods cannot see.

> 💡 **`argocd-cli` is not required on your local machine** to run this pipeline — the CD job pulls a pinned `argocd` binary from the Docker Hub mirror on the first run (and reuses it via `actions/cache` on every subsequent run, so the binary is only fetched again when you bump `ARGOCD_VERSION`). Install the CLI locally only if you want to query ArgoCD by hand from your terminal.

> 💡 **Why two cache layers (`actions/cache` + Docker Hub mirror)?** The mirror replaces the slow GitHub Releases path with a fast Cloudflare-CDN-backed Docker Hub pull (~15s); the cache replaces even *that* pull with a local-file read (<1s) for repeat runs at the same `ARGOCD_VERSION` / `YQ_VERSION`. The mirror is what makes the **first** CD run survivable from slow networks; the cache is what makes **every subsequent** run instant.

### Step 1 — Repository Settings

In GitHub → repository **Settings**:

- **Actions → General → Allow all actions and reusable workflows** ✅
- **Actions → General → Workflow permissions → Read and write permissions** ✅
  (required so the CD job's `EndBug/add-and-commit` action can push the updated `values.yaml` back to `main`)

The workflow file itself also declares this explicitly via `permissions: contents: write`, but the repo-level setting must allow it.

### Step 2 — Create a Docker Hub Access Token

At <https://hub.docker.com/settings/security>:

- Description: `MasterBackstageIdp`
- Expiration: None
- Access permissions: **Read & Write** (write is needed because the mirror workflow pushes new image repos like `christseng89/argocd-bin`)

Copy the token — you'll add it as a GitHub secret in Step 3.

### Step 3 — Add GitHub Secrets

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value | Used by |
|---|---|---|
| `DOCKERHUB_USERNAME` | `christseng89` | `cicd.yaml` (CI only) + `mirror-cli-binaries.yaml` |
| `DOCKERHUB_TOKEN` | _your Docker Hub access token_ | `cicd.yaml` (CI only) + `mirror-cli-binaries.yaml` |
| `ARGOCD_PASSWORD` | output of `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` | `cicd.yaml` (CD only) |

> The workflows read these exact names. Misnaming any of them will fail `docker/login-action` or `argocd login`.

> 💡 **Why doesn't the CD job need `DOCKERHUB_*`?** It only `docker pull`s the public mirror images (`christseng89/argocd-bin`, `christseng89/yq-bin`) — anonymous pulls work for public repos. Removing `docker login` from CD also avoids flaky `auth.docker.io` timeouts from in-cluster ARC pods. If you ever flip the mirror repos to private on Docker Hub, you'll need to add `docker/login-action@v3` back into the CD job and re-add the secrets to its "Used by" list.

### Step 4 — Install Actions Runner Controller (ARC)

Reference: <https://github.com/actions/actions-runner-controller>

Install cert-manager (a hard dependency of ARC):

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml
kubectl get po -n cert-manager
```

Install the controller, providing a GitHub PAT with `repo` scope (you can reuse the one from Part 4):

```bash
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

helm upgrade --install \
  --namespace actions-runner-system --create-namespace \
  --set=authSecret.create=true \
  --set=authSecret.github_token="<YOUR_GITHUB_PAT>" \
  --wait \
  actions-runner-controller actions-runner-controller/actions-runner-controller
```

Create the runner pool from the bundled manifest:

```bash
kubectl apply -f python-app/runnerdeployment.yaml
kubectl get runners
kubectl get po
```

Expected output for the pods (the suffix will differ):

```text
NAME                             READY   STATUS    RESTARTS   AGE
self-hosted-runner-vbb92-mrcmr   2/2     Running   0          36m
```

In GitHub → **Settings → Actions → Runners** the new runner should appear:

```text
- self-hosted-runner-vbb92-mrcmr (self-hosted, linux) - Idle
```

### Step 5 — Bootstrap the CLI Binary Mirror (one-time)

`argocd` and `yq` binaries on GitHub Releases can be very slow to download from Asia (50–100 KB/s for ARM64 in some cases). Without this step, the first CD run would spend an hour downloading 197 MB of `argocd` and probably hit the job timeout.

The `mirror-cli-binaries` workflow runs on a GitHub-hosted `ubuntu-latest` runner (fast egress to both GitHub Releases and Docker Hub) and republishes those binaries as small `FROM scratch` Docker images. Your CD job then pulls from Docker Hub — Cloudflare CDN, fast in Asia.

**Run it once now:**

1. GitHub → **Actions → mirror-cli-binaries → Run workflow**
2. Inputs:
   - `argocd_version`: `v3.4.2` (matches `ARGOCD_VERSION` in `cicd.yaml`)
   - `yq_version`: `v4.44.3` (matches `YQ_VERSION` in `cicd.yaml`)
3. Click **Run workflow**

Takes ~3–5 minutes. When it's green, verify on Docker Hub:

- <https://hub.docker.com/r/christseng89/argocd-bin/tags>
- <https://hub.docker.com/r/christseng89/yq-bin/tags>

You should see your version tag with a multi-arch manifest (amd64 + arm64).

> ⚠️ **Whenever you bump `ARGOCD_VERSION` or `YQ_VERSION` in `cicd.yaml`, run this mirror workflow first**. If you bump the version in `cicd.yaml` without re-mirroring, the CD job will fail with `manifest for christseng89/argocd-bin:vX.Y.Z not found`.

---

## Part 6 — Verify the Pipeline End-to-End

With everything from Parts 1–5 in place, a single code edit should flow all the way to a redeployed pod.

1. Edit `python-app/src/app.py` (e.g., change the `message` string) and push to `main`.
2. Watch the workflow run at **GitHub → Actions → cicd**. You should see:
   - **ci** build and push `christseng89/python-app:<commit-6>` as a multi-arch (`linux/amd64` + `linux/arm64`) image.
   - **cd** bump `python-app/charts/python-app/values.yaml`, commit the change, then `argocd app sync python-app` and `argocd app wait --health`.
3. Pull the bot's commit and confirm the new image tag:

   ```bash
   git pull
   grep "tag:" python-app/charts/python-app/values.yaml
   ```

4. Confirm the cluster rolled out the new image:

   ```bash
   kubectl get deploy python-app -n python-app \
     -o jsonpath="{.spec.template.spec.containers[0].image}"
   kubectl get pods -n python-app
   ```

5. Hit the endpoint and confirm the response reflects your edit:

   ```cmd
   curl http://python-app.test.com:9080/api/v1/info
   ```

6. The CD job's `EndBug/add-and-commit` step pushes the `values.yaml` bump back to `main`. Pull it locally so your next push isn't rejected as non-fast-forward:

   ```bash
   git config --global pull.rebase true   # one-time, makes future pulls clean
   git pull
   ```

   Or enable VS Code's **Git: Autofetch** setting and let the editor pull bot commits in the background.

---

## Appendix — Where Each Component Actually Runs

Useful when troubleshooting "can X reach Y over the network?" questions.

```text
┌──────────────────────────────────────────────────────────┐
│ Layer 0: Windows Host (Surface Pro 11, ARM64)            │
│          D:\development\MasterBackstageIdp\              │
│          │                                                │
│          │  Docker Desktop file sharing                  │
│          ▼                                                │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Layer 1: Docker Desktop VM (Linux on Hyper-V)        │ │
│ │          /run/desktop/mnt/host/d/development/...     │ │
│ │          (sees Windows D:\ via 9P / virtiofs mount)  │ │
│ │          │                                           │ │
│ │ ┌──────────────────────────────────────────────────┐ │ │
│ │ │ Layer 2: Kubernetes cluster (docker-desktop)     │ │ │
│ │ │          single-node, kubelet + CRI + CNI on     │ │ │
│ │ │          Layer 1                                 │ │ │
│ │ │ ┌──────────────────────────────────────────────┐ │ │ │
│ │ │ │ Layer 3: ARC Runner Pod (Linux container)    │ │ │ │
│ │ │ │          /runner/_work/MasterBackstageIdp/   │ │ │ │
│ │ │ │          overlayfs, isolated from Layer 1;   │ │ │ │
│ │ │ │          discarded when the job ends.        │ │ │ │
│ │ │ │                                              │ │ │ │
│ │ │ │          ← `cicd.yaml` steps run here        │ │ │ │
│ │ │ └──────────────────────────────────────────────┘ │ │ │
│ │ └──────────────────────────────────────────────────┘ │ │
│ └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘

         ┌──────────────────────────────────────┐
         │  GitHub-hosted runner (ubuntu-latest)│
         │  ← `mirror-cli-binaries.yaml` runs   │
         │     here. Fast egress to GitHub      │
         │     Releases AND Docker Hub. No      │
         │     visibility into your cluster.    │
         └──────────────────────────────────────┘
```

Implications:

- The `cd` job in `cicd.yaml` can reach `argocd-server.argocd.svc.cluster.local` because it shares Layer 2's CoreDNS — but it cannot see your Windows `D:\` files. That's why no GitHub Actions step can `git pull` to your laptop; the laptop must initiate the pull.
- The `mirror-cli-binaries` workflow runs in GitHub's cloud, so it has no path to your in-cluster ArgoCD — but it has fast access to public services like GitHub Releases and Docker Hub. That's why we use it specifically for the binary-mirror role and nothing else.

---

## Part 7 — Cleanup

To completely tear down the local environment:

```cmd
:: Delete the ArgoCD-managed application (and its python-app namespace)
helm uninstall argocd -n argocd
kubectl delete ns argocd python-app

:: Remove the ingress controller
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete ns ingress-nginx

:: Remove ARC and cert-manager
kubectl delete -f python-app/runnerdeployment.yaml
helm uninstall actions-runner-controller -n actions-runner-system
kubectl delete ns actions-runner-system
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml

:: Drop the local hosts entries (PowerShell as Administrator)
```

```powershell
$hosts = "C:\Windows\System32\drivers\etc\hosts"
(Get-Content $hosts) |
  Where-Object { $_ -notmatch "python-app\.test\.com|argocd\.test\.com" } |
  Set-Content $hosts
```

---

## Troubleshooting

Hit a snag? See **[README-troubleshooting.md](./README-troubleshooting.md)** — a categorised list of every real problem that bit during development, with cause and fix.

Quick jump to the right category:

- [A. Deployment doesn't reflect your code change](./README-troubleshooting.md#a-deployment-doesnt-reflect-your-code-change) — ArgoCD path, mirror tag, `argocd: command not found`
- [B. Pod starts but crashes immediately](./README-troubleshooting.md#b-pod-starts-but-crashes-immediately) — `exec format error`, arch mismatch
- [C. Network slowness or timeouts from in-cluster ARC pod](./README-troubleshooting.md#c-network-slowness-or-timeouts-from-the-in-cluster-arc-pod) — slow argocd download, `auth.docker.io` timeout, slow buildx
- [D. CLI flag and image-build quirks](./README-troubleshooting.md#d-cli-flag-and-image-build-quirks) — `argocd login --plaintext`, `docker create` no command
- [E. Runner environment gaps](./README-troubleshooting.md#e-runner-environment-gaps) — `kubectl: command not found`
- [F. Local laptop friction](./README-troubleshooting.md#f-local-laptop-friction) — git index corrupt, `non-fast-forward` push
