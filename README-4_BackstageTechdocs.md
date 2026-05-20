# Backstage TechDocs

Wire `python-app/docs/` up to Backstage TechDocs so the Docs tab on the
catalog entity renders the MkDocs site directly.

## References

- <https://backstage.io/docs/overview/what-is-backstage/>
- <https://backstage.io/docs/features/techdocs/>
- <https://stackedit.io/app#>

## Pipeline at a Glance

```text
python-app/docs/*.md
        │
        ▼  mkdocs build (techdocs-core plugin)
python-app/site/  (transient, inside container)
        │
        ▼  TechDocs publisher (local)
backstage-app/backstage/node_modules/.../static/docs/default/component/python-app/
        │
        ▼  Backstage UI iframe
http://localhost:3000/docs/default/component/python-app
```

## 1. Link the catalog entity to the docs

`python-app/catalog-info.yaml` must include the TechDocs annotation:

```yaml
metadata:
  name: python-app
  annotations:
    backstage.io/techdocs-ref: dir:.   # docs live next to this file
```

`dir:.` means MkDocs config is in the same directory as `catalog-info.yaml`
(i.e. `python-app/`).

## 2. Author the docs source

`python-app/docs/index.md`

````md
# python-app

A Flask service that returns a greeting, current time/hostname, and a health check.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/` | Returns a `Hello World!` greeting |
| GET | `/api/v1/info` | Returns current time, hostname, and a message |
| GET | `/api/v1/healthz` | Liveness/readiness probe |

## How to access the app

The service is exposed via the nginx ingress controller running on Docker Desktop.

```bash
curl http://python-app.test.com:9080/
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz
```
````

## 3. Configure MkDocs

`python-app/mkdocs.yaml`

```yaml
site_name: "python-app"
site_description: "Main documentation for the python-app"
repo_url: https://github.com/christseng89/MasterBackstageIdp
edit_uri: edit/main/python-app/docs

plugins:
  - techdocs-core

# For sidebar navigation on https://backstage.io/, see `microsite/sidebars.json`
nav:
  - Home: index.md
```

Key fields:

- `repo_url` → controls the "Edit this page" link target in the rendered docs.
- `edit_uri` → path appended to `repo_url` for the edit link. Because the
  docs live in a subfolder of the monorepo, the value is
  `edit/main/python-app/docs` (not just `edit/main/docs`).
- `plugins: - techdocs-core` → required for Backstage to consume the site.

Validate the YAML before pushing:

```bash
python -c "import yaml; print(yaml.safe_load(open('python-app/mkdocs.yaml')))"
```

## 4. Tell Backstage to build locally (not via Docker)

The default `backstage-app/backstage/app-config.yaml` ships with
`generator.runIn: 'docker'`, which requires the Backstage container to
have access to the host's Docker socket. We override it in the local
config so the TechDocs generator runs MkDocs **in the same container as
Backstage** — simpler, no socket mount needed.

`backstage-app/backstage/app-config.local.yaml` (append at the bottom):

```yaml
techdocs:
  builder: "local"
  generator:
    runIn: "local"   # ← override 'docker' from app-config.yaml
  publisher:
    type: "local"
```

## 5. Run Backstage with MkDocs installed in the container

```bash
cd backstage-app
source .env
echo $K8S_SA_TOKEN

docker run --rm \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID \
  -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET \
  -e K8S_SA_TOKEN=$K8S_SA_TOKEN \
  --add-host=host.docker.internal:host-gateway \
  -p 3000:3000 -ti -p 7007:7007 \
  -v //d/development/MasterBackstageIdp/backstage-app://app \
  -w //app node:24-bookworm-slim bash

# inside the container:
apt-get update && apt-get install -y python3 python3-pip
pip install --break-system-packages mkdocs-techdocs-core

mkdocs --version   # sanity check
  # mkdocs, version 1.6.1 from /usr/local/lib/python3.11/dist-packages/mkdocs (Python 3.11)

cd backstage
yarn start
  # ▶ Backstage running at http://localhost:3000
```

> 💡 To avoid re-installing MkDocs on every container start, bake it into
> a custom image:
>
> ```dockerfile
> FROM node:24-bookworm-slim
> RUN apt-get update && apt-get install -y python3 python3-pip && \
>     pip install --break-system-packages mkdocs-techdocs-core
> ```
>
> Build once (`docker build -t backstage-dev .`) and swap
> `node:24-bookworm-slim` → `backstage-dev` in the `docker run` line.

## 6. Open the docs in Backstage

Browser → <http://localhost:3000> → **Catalog → python-app → Docs** tab.

First load triggers an MkDocs build (10–60 s spinner). When it completes,
a green banner appears:

> ✅ A newer version of this documentation is now available, please refresh to view.

Click **REFRESH** — the docs render. Subsequent loads are cached.

## 7. Optional: preview the site standalone (no Backstage)

Useful for fast iteration on markdown content:

```cmd
cd D:\development\MasterBackstageIdp\python-app
pip install mkdocs mkdocs-techdocs-core
mkdocs serve
  # local: http://127.0.0.1:8000/
```

## Verification

After step 6 succeeds, you should see in Backstage's terminal log:

```text
techdocs info Published site stored at
  /app/backstage/node_modules/@backstage/plugin-techdocs-backend/static/docs/default/component/python-app
```

The frontend hits these endpoints (all should return 200 or 304):

- `GET /api/techdocs/sync/default/component/python-app`
- `GET /api/techdocs/metadata/entity/default/component/python-app`
- `GET /api/techdocs/static/docs/default/component/python-app/index.html`
- `GET /api/techdocs/static/docs/default/component/python-app/search/search_index.json`

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Docs tab stuck on "Loading…" with a green REFRESH banner | First build finished but iframe didn't auto-swap | Click **REFRESH**, then `Ctrl+Shift+R` |
| `mkdocs: command not found` in container | Skipped `pip install` step | Re-run `pip install --break-system-packages mkdocs-techdocs-core` |
| Build error mentioning `'nav'` or YAML parse failure | `mkdocs.yaml` has a trailing empty list item or stray bytes | Re-run the YAML validator in §3; rewrite the file if needed |
| `curl http://localhost:7007/api/techdocs/static/.../index.html` returns 401 | Expected — endpoint requires auth | The browser provides it via session cookie. 401 (not 404) confirms the file exists |
| "Edit this page" pencil link 404s | Wrong `repo_url` or `edit_uri` in `mkdocs.yaml` | For this repo: `repo_url: https://github.com/christseng89/MasterBackstageIdp` and `edit_uri: edit/main/python-app/docs` |
| Docs don't update after a `git push` | Backstage cached the previous build | Click the green REFRESH banner, or restart `yarn start` |

## What's now wired up

After completing this guide, the full IDP loop is in place:

```text
Code  →  Image  →  Helm  →  ArgoCD  →  Kubernetes
                                            │
                              Backstage     ▼
                              ├── Catalog (Component, API)
                              ├── Kubernetes tab (live cluster view)
                              └── Docs tab (TechDocs)
```
