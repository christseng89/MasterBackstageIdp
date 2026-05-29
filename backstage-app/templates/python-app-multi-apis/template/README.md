# ${{values.app_name}}

This repo was scaffolded from the **`python-app-multi-apis`** Backstage template.

It demonstrates the **additive multi-API-version** pattern with **per-env routing**:
the same image carries six API blueprints (`/api/v1` … `/api/v6`), but each
environment exposes a different subset via Helm-injected env vars
(`ENABLED_VERSIONS`, `DEPRECATED_VERSIONS`, `REMOVED_VERSIONS`). Backstage shows
1 Component + 6 API entities; the running service exposes a `/version`
metadata endpoint and emits RFC 9745 / RFC 8594 `Deprecation` + `Sunset`
headers on deprecated paths and `410 Gone` (with successor link) on removed
paths.

One setup script handles all post-scaffolding bootstrap — run it once after cloning.
ArgoCD apps are created automatically on the first successful pipeline run.

---

## Per-environment version distribution

| | v1 | v2 | v3 | v4 | v5 | v6 |
|---|---|---|---|---|---|---|
| **dev**     | `410` | `410`        | `410`  | stable | stable | stable (preview) |
| **staging** | `410` | `410`        | stable | stable | stable | stable (preview) |
| **prod**    | `410` | `200 deprecated` | stable | stable | `404` n/a | `404` n/a |

> `410` = removed, `200 deprecated` = served with `Deprecation` + `Sunset` headers,
> `404` = blueprint not registered (intentionally not deployed to that env).

See `docs/api-versions.md` for the full endpoint matrix and 410 / Deprecation
header details.

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
│   ├── values.yaml                           ← base Helm defaults (incl. apiVersions.enabled/deprecated/removed)
│   ├── values-dev.yaml                       ← enabled=v4,v5,v6  removed=v1,v2,v3  default=v6
│   ├── values-staging.yaml                   ← enabled=v3,v4,v5,v6  removed=v1,v2  default=v4
│   ├── values-prod.yaml                      ← enabled=v2,v3,v4  deprecated=v2  removed=v1  default=v4
│   └── templates/                            ← Deployment (with API-version labels + 4 env vars), Service, Ingress
├── src/
│   ├── app.py                                ← Flask entrypoint — reads 3 env vars, conditionally registers blueprints
│   ├── api_v1.py / api_v2.py / api_v3.py     ← Legacy versions; registered only if env's ENABLED_VERSIONS lists them
│   ├── api_v4.py                             ← /api/v4/* — production default (8 endpoints)
│   ├── api_v5.py                             ← /api/v5/* — production-ready, dev+staging (+1 /list)
│   ├── api_v6.py                             ← /api/v6/* — experimental, dev+staging (+1 /events SSE)
│   ├── removed_handlers.py                   ← Catch-all 410 Gone factory for REMOVED_VERSIONS
│   ├── deprecated_headers.py                 ← RFC 9745 / RFC 8594 middleware, env-driven
│   ├── version_endpoint.py                   ← /version runtime metadata (reflects current env)
│   └── templates/                            ← Greeting page + cat gifs
├── docs/
│   ├── index.md                              ← Overview + /version usage
│   ├── api-versions.md                       ← Per-env distribution + endpoint matrix
│   └── migration-v1-to-v2.md                 ← Linked by Sunset header (extend for v2→v3 etc. when needed)
├── Dockerfile
├── catalog-info.yaml                         ← 1 Component + 6 API entities (lifecycle reflects org-wide status)
├── runnerdeployment.yaml                     ← ARC self-hosted runner spec
├── setup.sh                                  ← post-clone bootstrap (secrets/variables, hosts, first pipeline)
└── mkdocs.yaml + docs/                       ← TechDocs source
```

---

## How env-driven routing works

`src/app.py` reads three comma-separated env vars at startup and registers
blueprints accordingly:

```python
ALL_VERSION_BLUEPRINTS = {"v1": v1_bp, "v2": v2_bp, ..., "v6": v6_bp}

for v in ENABLED_VERSIONS:    app.register_blueprint(ALL[v])           # normal routes
for v in REMOVED_VERSIONS:    app.register_blueprint(make_removed(v))  # 410 Gone catch-all
                                                                       # (DEPRECATED is a subset of ENABLED,
                                                                       # handled by an after_request middleware)
```

So changing the per-env behaviour is a Helm values change, not a code change.
Promotion / retirement workflow is in `docs/api-versions.md`.

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
don't need additional hosts edits. If Git Bash is **not** running as Administrator
the script prints the commands and exits. Open **PowerShell as Administrator** and run:

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-dev.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-staging.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 ${{values.app_name}}-prod.test.com"
```

### 5. Verify

Once the first pipeline run succeeds, sanity-check the per-env routing:

```bash
# Dev — should respond from v4/v5/v6 only, 410 on v1/v2/v3
curl -i http://${{values.app_name}}-dev.test.com:9080/api/v1/info   # → 410 Gone
curl -i http://${{values.app_name}}-dev.test.com:9080/api/v6/info   # → 200 OK
curl    http://${{values.app_name}}-dev.test.com:9080/version

# Prod — should serve v2 (deprecated) + v3/v4, 410 on v1, 404 on v5/v6
curl -i http://${{values.app_name}}-prod.test.com:9080/api/v2/info  # → 200 + Deprecation header
curl -i http://${{values.app_name}}-prod.test.com:9080/api/v5/info  # → 404
```

`/version` returns the env's current state:

```json
{
  "image": "a1b2c3",
  "git_sha": "a1b2c3",
  "api_versions": {
    "enabled":    ["v4","v5","v6"],
    "deprecated": [],
    "removed":    ["v1","v2","v3"]
  },
  "default_api_version": "v6",
  ...
}
```

---

## Normal Workflow After Setup

### Deploy new image to all envs (typical case)

```bash
git add src/
git commit -m "your change"
git push origin main
```

`cicd.yaml` triggers automatically: builds `christseng89/${{values.app_name}}:<sha>`,
writes the tag into `values-dev.yaml`, then ArgoCD syncs `${{values.app_name}}-dev`.
Promote to staging / prod via the `values-staging.yaml` / `values-prod.yaml`
edit-and-push flow.

### Change which versions an env exposes (no image rebuild)

Edit `charts/${{values.app_name}}/values-{env}.yaml`:

```yaml
apiVersions:
  enabled: "v3,v4,v5,v6"     # ← add or remove versions here
  deprecated: ""              # ← mark sunsetting versions
  removed: "v1,v2"            # ← move retired versions here (410 instead of 404)
  default: v4                 # ← the version surfaced via app.kubernetes.io/version label
```

Push to `main` → ArgoCD restarts the deployment with new env vars → routing
changes within ~30s, **same image**.

### Promote a version's lifecycle (e.g. v5 → production in prod)

1. Edit `catalog-info.yaml` — confirm v5's `lifecycle` is `production`
2. Edit `values-prod.yaml` — add `v5` to `apiVersions.enabled`
3. Optionally update `apiVersions.default: v5` + health probe path to `/api/v5/healthz`
4. Push to `main`; ArgoCD picks it up

### Retire a version (deprecated → removed)

1. Remove it from `DEPRECATED_VERSIONS`, add to `REMOVED_VERSIONS` in the
   relevant env's `values-*.yaml`
2. Optionally update `removed_handlers.SUNSET_INFO[<version>]` with the
   actual sunset date and successor
3. Push to `main`; clients calling that prefix now get `410 Gone` with a
   pointer to the successor

For the full sunset / 410-Gone procedure plus Backstage catalog flips, see
the API versioning best practice doc in the platform repo.
