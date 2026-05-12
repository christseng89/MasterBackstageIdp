# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a **Backstage IDP (Internal Developer Portal)** learning project. It contains a sample Python microservice (`python-app`) used to demonstrate a full GitOps/IDP workflow: source → Docker image → Helm chart → ArgoCD → Kubernetes, with the service registered in a Backstage catalog.

## Repository Layout

Two top-level directories are Git submodules (untracked by the main repo):
- `backstage/` — the Backstage application (cloned separately)
- `charts/` — the Helm charts repo; the CD pipeline updates `charts/python-app/values.yaml` here

`python-app/charts/` is a **local copy** of the Helm chart used for reference and manual deploys. The CI/CD pipeline writes to `charts/` (the submodule at root), not `python-app/charts/`.

## Running the Python App Locally

Python version is managed with `pyenv`; dependencies are managed with `uv`.

```bash
cd python-app
pyenv local 3.12.10
uv sync
uv pip install -r requirements.txt

# Run the entry-point script
uv run main.py

# Run the Flask server directly
python src/app.py   # listens on 0.0.0.0:5000
```

API endpoints exposed by `src/app.py`:
- `GET /` — returns "Hello World!"
- `GET /api/v1/info` — returns time, hostname, and a message
- `GET /api/v1/healthz` — liveness/readiness probe

There are no automated tests in this repository.

## TechDocs Local Preview

```bash
cd python-app
pip install mkdocs mkdocs-techdocs-core
mkdocs serve   # preview at http://localhost:8000
```

## Architecture Overview

### GitOps Pipeline

The CI/CD flow is fully GitOps (workflow: `python-app/.github/workflows/cicd.yaml`):

1. **CI** (`ubuntu-latest`): triggered on pushes to `src/**` on `main`. Builds and pushes a Docker image to Docker Hub tagged with the first 6 chars of the commit SHA (`ricardoandre9707/python-app:<commit_id>`).
2. **CD** (`self-hosted` runner): updates `charts/python-app/values.yaml` → `image.tag` (in the `charts/` submodule at repo root) with the new commit ID, commits it back, then triggers `argocd app sync python-app`.
3. **ArgoCD** watches the repo and reconciles the cluster state from `charts/python-app/values.yaml`.

The image tag in `charts/python-app/values.yaml` is the single source of truth for which version is deployed.

### Helm Chart vs Raw K8s Manifests

Two deployment methods coexist:
- `python-app/k8s/` — raw Kubernetes manifests (deploy, service, ingress) for direct `kubectl apply` use
- `python-app/charts/python-app/` — local Helm chart reference copy
- `charts/python-app/` — Helm chart submodule; what ArgoCD actually reads
- `python-app/charts/argocd/values-argo.yaml` — values override for deploying ArgoCD itself via Helm

### Backstage Integration

- `python-app/catalog-info.yaml` — registers the service in the Backstage catalog (kind: `Component`, type: `service`)
- `python-app/mkdocs.yaml` + `python-app/docs/` — TechDocs source; the `techdocs-core` plugin renders it inside Backstage
- The annotation `backstage.io/techdocs-ref: dir:.` points Backstage at the MkDocs config in the `python-app/` directory

### Docker Image

The Dockerfile uses `python:3.10-alpine`, copies only `requirements.txt` and `src/`, and runs `python /src/app.py`. Note: the local dev toolchain uses Python 3.12 via `pyenv`/`uv`, but the container image uses 3.10.

## Key Configuration

| File | Purpose |
|------|---------|
| `charts/python-app/values.yaml` | Helm values — `image.tag` is auto-updated by CI/CD (submodule) |
| `python-app/charts/argocd/values-argo.yaml` | ArgoCD Helm install overrides; domain is `argocd.test.com` |
| `python-app/k8s/ingress.yaml` | Raw ingress; host is `python-app.test.com` |
| `python-app/catalog-info.yaml` | Backstage catalog registration |

## Required Secrets (GitHub Actions)

- `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` — Docker Hub push access
- `ARGOCD_PASSWORD` — ArgoCD admin password for the self-hosted runner
