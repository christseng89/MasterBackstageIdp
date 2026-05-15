# Master Backstage IdP

A hands-on learning project that walks the full **Internal Developer Portal (IDP)** workflow end-to-end:

> Source code → Docker image → Helm chart → ArgoCD → Kubernetes — with the service registered in a Backstage catalog and a GitHub Actions pipeline orchestrating every step.

The result is a tight feedback loop where editing `python-app/src/app.py` and pushing to `main` automatically builds a new container image, updates the Helm values, syncs ArgoCD, and rolls out a new pod — all without any manual `kubectl` or `docker` commands.

## Architecture at a Glance

```text
┌─────────────┐  push   ┌──────────────────┐  build   ┌─────────────┐
│  Developer  │ ──────▶ │  GitHub (main)   │ ───────▶ │  Docker Hub │
└─────────────┘         └──────────────────┘   image  └─────────────┘
                              │                              │
                              │ workflow:                     │ pull
                              │  bumps image.tag              │
                              ▼                              ▼
                        ┌──────────────────┐  sync   ┌─────────────┐
                        │ charts/.../values│ ──────▶ │   ArgoCD    │
                        └──────────────────┘         └──────┬──────┘
                                                            │ apply
                                                            ▼
                                                    ┌─────────────┐
                                                    │ Kubernetes  │
                                                    │ (python-app)│
                                                    └─────────────┘
```

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
| `.github/workflows/cicd.yaml` | Authoritative GitHub Actions workflow |
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

The workflow at `.github/workflows/cicd.yaml` runs in two jobs on **self-hosted Linux runners** provisioned by [Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) inside this same Kubernetes cluster.

### How It Works

```text
push to main (changes under python-app/src/**)
        │
        ▼
┌──────────────────────────────┐
│  ci  (runs-on: ARC linux)    │
│   1. Checkout                │
│   2. Set up QEMU + Buildx    │
│   3. Login to Docker Hub     │
│   4. Build & push multi-arch │
│      christseng89/python-app │
│      :<commit-6>             │
└──────────────────────────────┘
        │
        ▼
┌──────────────────────────────┐
│  cd  (runs-on: ARC linux)    │
│   1. Checkout                │
│   2. Detect runner arch      │
│   3. yq -i values.yaml       │
│      (bump image.tag)        │
│   4. git commit & push       │
│   5. argocd login (in-cluster│
│      service DNS)            │
│   6. argocd app sync         │
│   7. argocd app wait healthy │
└──────────────────────────────┘
```

> The `cd` job talks to ArgoCD via the in-cluster service DNS `argocd-server.argocd.svc.cluster.local`, **not** through `argocd.test.com:9080`. The ingress hostname only resolves on your laptop via the Windows hosts file, which ARC runner pods cannot see.

> 💡 **`argocd-cli` is not required on your local machine** to run this pipeline — the CD job downloads its own pinned `argocd` binary on every run. Install it locally only if you want to query ArgoCD by hand from a terminal.

### Step 1 — Repository Settings

In GitHub → repository **Settings**:

- **Actions → General → Allow all actions and reusable workflows** ✅
- **Actions → General → Workflow permissions → Read and write permissions** ✅
  (required so the CD job's `EndBug/add-and-commit` action can push the updated `values.yaml` back to `main`)

### Step 2 — Create a Docker Hub Access Token

At <https://hub.docker.com/settings/security>:

- Description: `MasterBackstageIdp`
- Expiration: None
- Access permissions: **Read & Write**

Copy the token — you'll add it as a GitHub secret in Step 3.

### Step 3 — Add GitHub Secrets

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | `christseng89` |
| `DOCKERHUB_TOKEN` | _your Docker Hub access token_ |
| `ARGOCD_PASSWORD` | output of `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |

> The workflow reads these exact names. Misnaming any of them will fail `docker/login-action` or `argocd login`.

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

In GitHub → **Settings → Actions → Runners** the new runner should appear with status **Idle**, ready to accept jobs.

- self-hosted-runner-vbb92-mrcmr (self-hosted, linux) - Idle
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

6. git config --global pull.rebase true
   git pull
    
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

Problems that bit during development of this project, with their fixes.

### `argocd app sync` succeeds but the pod still serves the old code

**Cause:** ArgoCD's `Path` doesn't match where CI/CD writes `values.yaml`.

**Fix:** In the ArgoCD application, ensure `Path = python-app/charts/python-app` exactly. The CD job rewrites `python-app/charts/python-app/values.yaml` — any other path means ArgoCD sees no diff.

### Pod shows `CrashLoopBackOff` with `exec /usr/local/bin/python: exec format error`

**Cause:** The container image's CPU architecture doesn't match the node. The GitHub-hosted CI runner is `linux/amd64`, but Surface Pro 11 / Apple Silicon nodes are `linux/arm64`.

**Fix:** The workflow already builds multi-arch via `docker/setup-qemu-action@v3` and `platforms: linux/amd64,linux/arm64`. Confirm with:

```cmd
docker buildx imagetools inspect christseng89/python-app:<tag>
```

You should see two `Manifests:` entries, one per platform.

### CD job fails with `argocd: command not found`

**Cause:** ARC runner pods are minimal and don't ship the ArgoCD CLI.

**Fix:** The workflow's `Install ArgoCD CLI` step now downloads the pinned binary into `/tmp/argocd`. Make sure that step exists before `Argocd app sync`.

### `argocd login` fails with `WARNING: server is not configured with TLS. Proceed (y/n)?` and exits 20

**Cause:** `argocd-server` is configured with `server.insecure: "true"`, so it serves plain HTTP. The CLI defaults to HTTPS and falls back to an interactive prompt that EOFs in a non-interactive shell.

**Fix:** Add `--plaintext` (and drop `--insecure` / `--skip-test-tls` — those are HTTPS-only):

```bash
argocd login argocd-server.argocd.svc.cluster.local \
  --plaintext --grpc-web \
  --username admin --password "$ARGOCD_PASSWORD"
```

### `git status` reports `error: index uses ?<�d extension, which we do not understand` / `index file corrupt`

**Cause:** Git index sometimes corrupts on Windows after interrupted operations.

**Fix:** Rebuild it from `HEAD` (working-tree files are untouched):

```cmd
del .git\index
git reset
```

### CD job's `yq` step fails on ARM64 runner

**Cause:** Hardcoded `yq_linux_amd64` binary download.

**Fix:** The workflow already detects the runner architecture and downloads the matching binary. Confirm the `Detect runner architecture` step runs before `Modify values file`.
