# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a **Backstage IDP (Internal Developer Portal)** learning project. It contains two sample Python microservices (`python-app` and `python-app4`) used to demonstrate different GitOps/IDP workflow patterns: source → Docker image → Helm chart → ArgoCD → Kubernetes, with services registered in a Backstage catalog.

## Repository Layout

```
.github/workflows/     # Shared CI/CD pipeline (cicd.yaml) and binary mirror workflow
python-app/            # Python Flask microservice — single-environment GitOps pattern
python-app4/           # Python Flask microservice — multi-environment GitOps pattern (dev/staging/prod)
backstage-app/         # Backstage IDP application (tracked directory, not a submodule)
  backstage/           # Backstage monorepo — see backstage-app/backstage/CLAUDE.md for dev guidance
  Dockerfile           # Custom image: Node 24 + Python3 + mkdocs for TechDocs
  techdocs-storage/    # Built TechDocs output served by Backstage
actions-runner/        # GitHub Actions self-hosted ARC runner installation
```

Two submodules are declared in `.gitmodules` (`backstage` and `charts`) but are **not checked out locally**. The `backstage-app/backstage/` directory is a standalone clone of the Backstage repo; `charts/` (the Helm charts submodule) is also not present locally.

## Running the Python Apps Locally

Python version is managed with `pyenv`; dependencies are managed with `uv`.

```bash
cd python-app
pyenv local 3.12.10
uv sync
uv pip install -r requirements.txt

python src/app.py       # Flask server on 0.0.0.0:5000
```

Note: `uv run main.py` runs a stub that only prints "Hello from python-app!" — it does not start the Flask server.

API endpoints exposed by `src/app.py`:
- `GET /` — returns "Hello World!"
- `GET /api/v1/info` — returns time, hostname, and a message
- `GET /api/v1/healthz` — liveness/readiness probe

There are no automated tests in this repository.

## TechDocs Local Preview

```bash
cd python-app          # or python-app4
pip install mkdocs mkdocs-techdocs-core
mkdocs serve   # preview at http://localhost:8000
```

## Backstage App Development

See **`backstage-app/backstage/CLAUDE.md`** for full guidance. Key commands (run from `backstage-app/backstage/`):

```bash
yarn start          # frontend (localhost:3000) + backend (localhost:7007)
yarn build:backend  # build backend for Docker
yarn build-image    # build custom Backstage Docker image
yarn lint:all
yarn test:all
```

Requires Node 22 or 24 and Yarn 4.4.1 (Yarn Berry). Config layering: `app-config.yaml` → `app-config.local.yaml` → `app-config.production.yaml`.

**`app-config.local.yaml` overrides the base SQLite config with PostgreSQL.** Running `yarn start` locally requires a PostgreSQL instance and these env vars set:

```bash
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=<user>
export POSTGRES_PASSWORD=<password>
export GITHUB_TOKEN=<pat>
export AUTH_GITHUB_CLIENT_ID=<id>
export AUTH_GITHUB_CLIENT_SECRET=<secret>
export K8S_SA_TOKEN=<token>   # only if using the Kubernetes plugin
```

The sign-in resolvers in `app-config.local.yaml` try `emailMatchingUserEntityProfileEmail` first, then `usernameMatchingUserEntityName`. The GitHub user's email or username must match a `User` entity in the catalog.

## Architecture Overview

### Two GitOps Patterns

#### python-app — Single Environment

Defined in `.github/workflows/cicd.yaml`; triggered on pushes to `python-app/src/**` on `main`:

1. **CI** (`ubuntu-latest`): builds and pushes a **multi-arch** (linux/amd64 + linux/arm64) Docker image to Docker Hub tagged with the first 6 chars of the commit SHA (`christseng89/python-app:<commit_id>`).
2. **CD** (`self-hosted` ARC runner): uses `yq` to update `image.tag` in `python-app/charts/python-app/values.yaml`, commits back to `main` using `GH_PAT`, then calls `argocd app sync python-app`.

`python-app/charts/python-app/values.yaml` is the single source of truth for the deployed version. ArgoCD app: `python-app`.

#### python-app4 — Multi-Environment (dev / staging / prod)

> **Note:** The `python-app4` app directory is not checked out locally — this section documents the multi-environment GitOps pattern it demonstrates.

Two separate workflows in `python-app4/.github/workflows/`:

- **`python-app4-cicd.yaml`** — triggered on `python-app4/src/**` changes: runs CI (build + push image), then CD auto-deploys to **dev** by updating `charts/python-app4/values-dev.yaml` using `GITHUB_TOKEN` + `EndBug/add-and-commit@v9`.
- **`python-app4-cd.yaml`** — triggered when `values-staging.yaml` or `values-prod.yaml` change (manual promotion flow): detects which values file changed, validates the image tag is non-empty, then syncs the corresponding ArgoCD app (`python-app4-staging` or `python-app4-prod`).

ArgoCD apps: `python-app4-dev` (namespace `dev`), `python-app4-staging` (namespace `staging`), `python-app4-prod` (namespace `prod`).

**Promotion model:** edit the target `values-{env}.yaml` with a new `image.tag` and push to `main` — the CD workflow fires automatically.

### Helm Chart vs Raw K8s Manifests

Each app has both:
- `<app>/charts/<app>/` — Helm chart; what ArgoCD reads; `values.yaml` is the base, `values-{env}.yaml` per-env overrides
- `<app>/k8s/` — raw Kubernetes manifests for direct `kubectl apply` use

Shared infrastructure charts:
- `python-app/charts/argocd/values-argo.yaml` — values override for deploying ArgoCD itself via Helm (domain `argocd.test.com`)
- `python-app/charts/nginx/values-nginx.yaml` — Nginx Ingress Controller overrides

### ARC Runner

`python-app/runnerdeployment.yaml` deploys a self-hosted GitHub Actions runner (using `actions.summerwind.dev/v1alpha1`) in the `python-app` namespace with `dockerEnabled: true`. `python-app/k8s/runner-rbac.yaml` grants it read access to pods and deployments via a `ClusterRole`. The runner needs in-cluster DNS to reach `argocd-server.argocd.svc.cluster.local`.

### Backstage Integration

- `<app>/catalog-info.yaml` — registers the app as a Backstage `Component`; `python-app` also registers an `API` (type: openapi) pointing at `python-app/openapi.yaml`
- `<app>/mkdocs.yaml` + `<app>/docs/` — TechDocs source; `backstage.io/techdocs-ref: dir:.` points Backstage at the MkDocs config
- `backstage-app/backstage/catalog/entities/` — `groups.yaml` + `users.yaml` loaded in Docker/production deployments (not in base `app-config.yaml`)
- TechDocs is configured as `builder: local` — Backstage backend runs mkdocs on demand
- MCP Actions are enabled in the backend (`pluginSources: auth, catalog, scaffolder`) via `app-config.yaml`

### Scaffolder Template

`backstage-app/templates/python-app/template.yaml` is a Backstage software template that provisions a new Python Flask microservice: it fetches skeleton files from `./template/`, creates a GitHub repo under `christseng89/<component_id>`, and registers the new component in the Backstage catalog. Registered in `app-config.local.yaml` as a local file source (`/app/templates/python-app/template.yaml` inside the container).

### Local Hosts File

The ingress and ArgoCD use custom hostnames that require `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`) entries:

```
127.0.0.1  python-app.test.com
127.0.0.1  argocd.test.com
```

### Docker Image (python-app / python-app4)

Both `Dockerfile`s use `python:3.10-alpine`, copy `requirements.txt` and `src/`, run `python /src/app.py`. Local dev uses Python 3.12 via `pyenv`/`uv`; the container uses 3.10.

The custom Backstage image (`backstage-app/Dockerfile`) uses Node 24 + Python3 + mkdocs for in-container TechDocs generation.

### Binary Mirror Workflow

`mirror-cli-binaries.yaml` (exists in both `.github/workflows/` and `python-app4/.github/workflows/`) mirrors ArgoCD, yq, and kubectl binaries to Docker Hub (`christseng89/{argocd,yq,kubectl}-bin`) for fast in-cluster pulls. The CD jobs cache these binaries at `/tmp/{argocd,yq,kubectl}` keyed by version + arch.

## Key Configuration

| File | Purpose |
|------|---------|
| `python-app/charts/python-app/values.yaml` | Helm values — `image.tag` auto-updated by CI/CD |
| `python-app4/charts/python-app4/values-dev.yaml` | Dev values — `image.tag` auto-updated by CI/CD |
| `python-app4/charts/python-app4/values-{staging,prod}.yaml` | Manually updated to promote to staging/prod |
| `python-app/charts/argocd/values-argo.yaml` | ArgoCD Helm install overrides; domain `argocd.test.com` |
| `python-app/k8s/ingress.yaml` | Raw ingress; host `python-app.test.com` |
| `python-app/catalog-info.yaml` | Backstage Component + API registration |
| `python-app/openapi.yaml` | OpenAPI spec served via the Backstage API catalog |
| `python-app4/catalog-info.yaml` | Backstage Component registration (no API entity) |
| `backstage-app/backstage/app-config.yaml` | Backstage base config (SQLite, localhost, MCP actions) |
| `backstage-app/backstage/app-config.local.yaml` | Local overrides (0.0.0.0 binding, GitHub OAuth) |

## Required Secrets (GitHub Actions)

- `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` — Docker Hub push access (CI jobs)
- `ARGOCD_PASSWORD` — ArgoCD admin password (CD jobs)
- `GH_PAT` — GitHub PAT used by `python-app` CD job for git push (python-app4 uses `GITHUB_TOKEN`)
