# Master Backstage IdP

A learning project that walks an internal developer-portal (IDP) workflow end‑to‑end: a Python microservice → Docker image → Helm chart → ArgoCD → Kubernetes, with the service registered in a Backstage catalog and a GitHub Actions pipeline doing the source‑to‑cluster handoff.

## Repository Layout

| Path | Purpose |
|---|---|
| `python-app/src/` | Flask app source — every push here triggers CI/CD |
| `python-app/Dockerfile` | Container image definition |
| `python-app/charts/python-app/` | **The** Helm chart — ArgoCD watches this, CI/CD updates `values.yaml` here |
| `python-app/charts/nginx/` | Values override for the Nginx Ingress Controller install |
| `python-app/charts/argocd/` | Values override for the ArgoCD install |
| `python-app/k8s/` | Raw Kubernetes manifests (alternative to Helm, for direct `kubectl apply`) |
| `python-app/catalog-info.yaml` | Backstage catalog registration |
| `.github/workflows/cicd.yaml` | The authoritative GitHub Actions workflow |
| `backstage/` | Backstage app (Git submodule) |
| `charts/` | Backstage Helm chart fork (Git submodule, unrelated to python-app) |

---

# Part 1 — Local Development

## Run the Python App Locally

```cmd
git clone https://github.com/christseng89/backstage.git
git clone https://github.com/christseng89/python-app

cd python-app
uv init
pyenv global 3.12.10
pyenv local 3.12.10

uv sync
uv pip install -r requirements.txt

uv run main.py
    Hello from python-app!

uv run src\app.py
    http://127.0.0.1:5000
    http://127.0.0.1:5000/api/v1/info
    http://127.0.0.1:5000/api/v1/healthz
```

## Build & Run with Docker

```cmd
cd python-app
docker build -t python-app:latest .
docker run -d -p 5000:5000 --name python-app python-app:latest
    http://127.0.0.1:5000
    http://127.0.0.1:5000/api/v1/info
    http://127.0.0.1:5000/api/v1/healthz

docker exec -it python-app sh
    apk add curl
    curl http://localhost:5000
    curl http://localhost:5000/api/v1/info
    curl http://localhost:5000/api/v1/healthz

docker logs python-app
docker stop python-app
docker rm python-app
```

Push the local image to Docker Hub:

```cmd
docker tag python-app:latest christseng89/python-app:latest
docker push christseng89/python-app:latest
```

---

# Part 2 — Kubernetes Cluster Setup

## Sanity-check the Cluster

```cmd
kubectl cluster-info
kubectl get nodes

kubectl get ns
kubectl get pod
kubectl get svc -A
kubectl get deployment -A
kubectl get ingress -A

kubectl get po -n ingress-nginx
```

## Local DNS Entries

Add the hostnames the manifests and ArgoCD UI expect:

```powershell
# Run as Administrator
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 python-app.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 argocd.test.com"
```

Or edit by hand:

```cmd
notepad C:\Windows\System32\drivers\etc\hosts
    127.0.0.1       python-app.test.com
    127.0.0.1       argocd.test.com
```

## Install Nginx Ingress Controller

```cmd
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace -f charts\nginx\values-nginx.yaml

kubectl get svc -n ingress-nginx | grep 9080
curl http://localhost:9080
```

---

# Part 3 — Deploy Python-App (Manual)

These are the manual paths — useful for learning and testing. The production path is GitOps via ArgoCD (Part 4).

## Method A — Raw `kubectl` Manifests

Behind the local DNS entry:

```cmd
cd python-app
kubectl apply -f k8s/python-app.yaml

curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz
```

Tear it down:

```cmd
kubectl delete -f k8s/python-app.yaml
kubectl get all
```

## Method B — Helm (Manual Install)

Tag and push a versioned image first:

```cmd
docker tag christseng89/python-app:latest christseng89/python-app:v2
docker push christseng89/python-app:v2
```

Install into the `default` namespace:

```cmd
helm install python-app charts\python-app --dry-run --debug
helm install python-app charts\python-app --set image.tag=v2

helm ls
kubectl get all

curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz
```

Uninstall:

```cmd
helm uninstall python-app
```

---

Or install into a dedicated `python-app` namespace:

```cmd
helm install python-app charts/python-app --set image.tag=v2 -n python-app --create-namespace

helm ls -n python-app
kubectl get all -n python-app

curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz

helm uninstall python-app -n python-app
```

---

# Part 4 — GitOps with ArgoCD

## Install ArgoCD

<https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>

```cmd
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f charts\argocd\values-argo.yaml

kubectl get ingress -n argocd
curl http://argocd.test.com:9080
```

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    Yy9Z7X4V0fF4D0cU
```

Log in via the browser:

```
http://argocd.test.com:9080
    Username: admin
    Password: Yy9Z7X4V0fF4D0cU
```

## Connect the Repository to ArgoCD

📌 How to get a GitHub PAT (if you don't have one)

1. Go to → <https://github.com/settings/tokens>
2. Click **Generate new token (classic)**
3. Note: `MasterBackstageIdp`
4. Scopes: ✅ `repo` (full control)
5. Click **Generate token** → copy it immediately

In ArgoCD → **Settings → Repositories → Connect Repo**:

| Field | Value |
|---|---|
| Connection Method | VIA HTTPS |
| Name | `MasterBackstageIdp` |
| Project | `default` |
| Repository URL | `https://github.com/christseng89/MasterBackstageIdp.git` |
| Username | `christseng89` |
| Password | _<your GitHub PAT>_ |

## Create the python-app Application

In ArgoCD → **Applications → New App**:

| Field | Value |
|---|---|
| Application Name | `python-app` ✅ |
| Project Name | `default` ✅ |
| Sync Policy | Manual |
| Sync Options | ✅ Auto-Create Namespace |
| Repository URL | `https://github.com/christseng89/MasterBackstageIdp.git` |
| Revision | `main` ← 🔑 any branch, tag, or commit |
| **Path** | **`python-app/charts/python-app`** ← 🔑 MUST match the chart that CI/CD updates |
| Cluster URL | `https://kubernetes.default.svc` |
| Namespace | `python-app` |
| Values Files | `values.yaml` |

> ⚠️ The `Path` above **MUST** be `python-app/charts/python-app`. The CD job in
> `.github/workflows/cicd.yaml` writes the new image tag into
> `python-app/charts/python-app/values.yaml` after every successful build. If
> ArgoCD is pointed at any other directory, `argocd app sync` will see no diff
> and the pod will never roll out the new image.

Click **Create → Sync → SYNCHRONIZE**, then verify:

```
http://python-app.test.com:9080
http://python-app.test.com:9080/api/v1/info
http://python-app.test.com:9080/api/v1/healthz
```

---

# Part 5 — CI/CD Automation (GitHub Actions)

The authoritative workflow is `.github/workflows/cicd.yaml`. The `ci` job runs on a GitHub-hosted `ubuntu-latest` runner; the `cd` job runs on your **self-hosted** Windows runner because it needs access to your local ArgoCD instance.

## Repository Settings

In GitHub → repository **Settings**:

- **Actions → General → Allow all actions and reusable workflows** ✅
- **Actions → General → Workflow permissions → Read and write permissions** ✅
  (needed so the CD job's `EndBug/add-and-commit` can push the values.yaml bump back to `main`)

## Create a Docker Hub Access Token

<https://hub.docker.com/settings/security>

- Description: `MasterBackstageIdp`
- Expiration: None
- Access permissions: **Read & Write**

## GitHub Secrets

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | `christseng89` |
| `DOCKERHUB_TOKEN` | _<your Docker Hub access token>_ |
| `ARGOCD_PASSWORD` | output of `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |

> The workflow reads these as `${{ secrets.DOCKERHUB_USERNAME }}`,
> `${{ secrets.DOCKERHUB_TOKEN }}`, and `${{ secrets.ARGOCD_PASSWORD }}`. The
> names **must** match exactly or `docker/login-action` / `argocd login` will
> fail.

## Install ArgoCD CLI on the Runner Host

The `cd` job calls `argocd login` and `argocd app sync`, so the CLI must exist on the self-hosted runner machine.

```cmd
choco install argocd-cli
argocd version
    argocd: v3.4.2+0dc6b1b
    BuildDate: 2026-05-12T21:00:01Z
    GitCommit: 0dc6b1b57dd5bb925d5b03c3d09419ab9fb4225e
    GitTreeState: clean
    GoVersion: go1.26.0
    Compiler: gc
    Platform: windows/amd64
    {"level":"fatal","msg":"Argo CD server address unspecified","time":"2026-05-14T20:24:49+08:00"}
```

(The `fatal` line is expected when `argocd version` runs without a configured server — the workflow itself handles the login.)

## Register the Self-Hosted Runner

GitHub → **Settings → Actions → Runners → New self-hosted runner**

**Download the runner package** (Git Bash on Windows):

```bash
# Create folder and enter it (relative to wherever Git Bash is opened, e.g. your home ~)
mkdir -p actions-runner && cd actions-runner

# Download the runner package
curl -L -o actions-runner-win-x64-2.334.0.zip \
  https://github.com/actions/runner/releases/download/v2.334.0/actions-runner-win-x64-2.334.0.zip

# Extract it (use PowerShell from Git Bash for unzip on Windows)
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; \
  [System.IO.Compression.ZipFile]::ExtractToDirectory('$(pwd -W)\\actions-runner-win-x64-2.334.0.zip', '$(pwd -W)')"
```

**Configure and start the runner** (replace the token with the one GitHub shows you on the *New self-hosted runner* page — it rotates):

```bash
./config.cmd --url https://github.com/christseng89/MasterBackstageIdp --token AC7NNQC2IOUD6UVAN5FPDV3KAXEMA

./run.cmd
```

---

# Part 6 — Verify the Pipeline

After everything above is in place, a code change in `python-app/src/**` should flow automatically to the cluster:

1. Edit `python-app/src/app.py` (e.g., change the `message` string) and push to `main`.
2. Watch the workflow run: GitHub → **Actions → cicd**. CI builds & pushes `christseng89/python-app:<commit-6>`; CD updates `python-app/charts/python-app/values.yaml` and runs `argocd app sync python-app`.
3. Confirm the new image tag landed in Git:

   ```cmd
   git pull
   grep "tag:" python-app/charts/python-app/values.yaml
   ```

4. Confirm the cluster rolled out the new pod:

   ```cmd
   kubectl get deploy python-app -n python-app -o jsonpath="{.spec.template.spec.containers[0].image}"
   kubectl get pods -n python-app
   ```

5. Hit the endpoint and confirm the response reflects your edit:

   ```cmd
   curl http://python-app.test.com:9080/api/v1/info
   ```

If the response still shows the old message, the most common cause is an ArgoCD `Path` that doesn't match `python-app/charts/python-app/` — re-check Part 4.
