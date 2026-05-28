# ${{values.app_name}}

This repo was scaffolded from the **`python-app-multi-apis`** Backstage template.

It demonstrates the **additive multi-API-version** pattern — one image
simultaneously serves `/api/v1` (deprecated), `/api/v2` (production),
`/api/v3` (experimental). Backstage shows 1 Component + 3 API entities;
the running service exposes a `/version` metadata endpoint and emits
RFC 9745 / RFC 8594 `Deprecation` + `Sunset` headers on deprecated paths.

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
│   ├── values.yaml                           ← base Helm defaults (incl. apiVersions.*)
│   ├── values-dev.yaml                       ← default v3 (preview / dogfood)
│   ├── values-staging.yaml                   ← default v2 (mirrors prod)
│   ├── values-prod.yaml                      ← default v2 (production)
│   └── templates/                            ← Deployment (with API-version labels), Service, Ingress
├── src/
│   ├── app.py                                ← Flask entrypoint — registers v1/v2/v3 blueprints + /version
│   ├── api_v1.py                             ← /api/v1/* — 3 endpoints (DEPRECATED)
│   ├── api_v2.py                             ← /api/v2/* — 5 endpoints (PRODUCTION)
│   ├── api_v3.py                             ← /api/v3/* — 8 endpoints (EXPERIMENTAL)
│   ├── deprecated_headers.py                 ← RFC 9745 / RFC 8594 middleware
│   ├── version_endpoint.py                   ← /version runtime metadata
│   └── templates/                            ← Greeting page + cat gifs
├── docs/
│   ├── index.md                              ← Overview, /version usage
│   ├── api-versions.md                       ← Endpoint matrix for v1 / v2 / v3
│   └── migration-v1-to-v2.md                 ← Linked by the Sunset header
├── Dockerfile
├── catalog-info.yaml                         ← 1 Component + 3 API entities (deprecated/production/experimental)
├── runnerdeployment.yaml                     ← ARC self-hosted runner spec
├── setup.sh                                  ← post-clone bootstrap (secrets/variables, hosts, first pipeline)
└── mkdocs.yaml + docs/                       ← TechDocs source
```

---

## Multi-API-version cheat sheet

| Path | Endpoints | Lifecycle | Backstage entity ref |
|---|---|---|---|
| `/api/v1/*` | 3 | `deprecated` (sunset 2025-12-31) | `api:default/${{values.app_name}}-api-v1` |
| `/api/v2/*` | 5 | `production` (default) | `api:default/${{values.app_name}}-api-v2` |
| `/api/v3/*` | 8 | `experimental` | `api:default/${{values.app_name}}-api-v3` |
| `/version` | 1 | always | (metadata; not versioned) |

**dev** ships with `apiVersions.default = v3` so the team can dogfood the
preview. **staging** + **prod** ship with `v2` until v3 is promoted to
`lifecycle: production` in `catalog-info.yaml`.

The deployed Kubernetes Deployment carries `app.kubernetes.io/version`
set to `apiVersions.default`, so the Backstage K8s plugin shows the
current default version next to the pod listing without any extra config.

---

## Admin Setup (run once after scaffolding)

### 1. Clone and enter the repo

```bash
git clone https://github.com/christseng89/${{values.app_name}}.git
cd ${{values.app_name}}
```

### 2. Create `.env`

`setup.sh` sources this file before doing anything. Create it in the repo root:

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

### 3. Run setup.sh

```bash
gh auth login          # one-time, if not already authenticated
bash setup.sh          # runs all steps and triggers the first CI/CD pipeline
```

`setup.sh` sets 4 secrets + 3 variables on this repo, registers the per-app
ARC runner, mirrors CLI binaries (skip with `--skip-mirror`), writes the
hosts file entries for dev/staging/prod, and triggers the first CI/CD run.
Re-runs overwrite existing values, so rotating tokens is just `bash setup.sh`.

```bash
bash setup.sh --skip-mirror               # skip Docker Hub mirror step
bash setup.sh --skip-cicd                 # skip triggering the first pipeline run
```

### 4. Add Windows hosts entries (manual — requires Administrator)

`setup.sh` writes three entries — one per environment — so later promotions
to staging/prod don't need additional hosts edits. If Git Bash is **not**
running as Administrator the script prints the commands and exits.
Open **PowerShell as Administrator** and run:

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-dev.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-staging.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-prod.test.com"
```

### 5. Verify

Once the first pipeline run succeeds:

- ArgoCD dashboard: `http://argocd.test.com:9080/`
- App (dev): `http://${{values.app_name}}-dev.test.com:9080/`
- Version metadata: `http://${{values.app_name}}-dev.test.com:9080/version`
- Try a deprecated endpoint to see the headers:
  `curl -i http://${{values.app_name}}-dev.test.com:9080/api/v1/info`

You should see `Deprecation: true` and `Sunset: Wed, 31 Dec 2025 23:59:59 GMT`
in the response headers.

---

## Normal Workflow After Setup

### Deploy to Dev — push source changes

```bash
git add src/
git commit -m "your change"
git push origin main
```

`cicd.yaml` triggers automatically: builds `christseng89/${{values.app_name}}:<sha>`,
writes the tag into `values-dev.yaml`, then ArgoCD syncs `${{values.app_name}}-dev`.

### Promote to Staging / Prod

Edit `charts/${{values.app_name}}/values-staging.yaml` (or `values-prod.yaml`)
and bump `image.tag`:

```yaml
image:
  tag: a1b2c3    # replace with the tag tested in the previous env
```

Push to `main`; the staging-cd / prod-cd workflow takes care of the rest.

> The image tag is the first 6 characters of the Git commit SHA.
> Git history on `values-staging.yaml` and `values-prod.yaml` is the audit
> trail of who promoted what version and when.

### Promoting an API version's lifecycle

When v3 is ready for production (e.g. v2 traffic has been moved over):

1. Edit `catalog-info.yaml` — change v3's `lifecycle: experimental` → `production`
2. Edit `values-staging.yaml` / `values-prod.yaml` to set
   `apiVersions.default: v3` (so the K8s label flips too)
3. Mark v2 as `deprecated` in `catalog-info.yaml` and add `/api/v2` to
   `DEPRECATED_PREFIXES` in `src/deprecated_headers.py` with a new sunset date
4. Update `mkdocs.yaml` / `docs/migration-v2-to-v3.md` for the new transition

For the full sunset / 410-Gone procedure, see the API versioning best
practice doc in the platform repo.
