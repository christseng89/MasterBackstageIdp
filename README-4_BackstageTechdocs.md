# Backstage Techdocs

## Docs as Code

<https://backstage.io/docs/overview/what-is-backstage/>
<https://backstage.io/docs/features/techdocs/>
<https://stackedit.io/app#>

python-app/docs/index.md

```md
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
```

## Documents for python-app

python-app/mkdocs.yml

```yaml
site_name: "python-app"
site_description: "Main documentation for the python-app"
repo_url: https://github.com/christseng89/python-app
edit_uri: edit/main/python-app/docs

plugins:
  - techdocs-core
# For sidebar navigation on https://backstage.io/, see `microsite/sidebars.json`
nav:
  - Home: index.md
  - API Reference:
      - Endpoints: index.m

```

backstage-app/backstage/app-config.local.yaml

```yaml
...
techdocs:
  builder: "local"
  generator:
    runIn: "local" # ← was 'docker' in app-config.yaml; override here
  publisher:
    type: "local"

```

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

    apt-get update && apt-get install -y python3 python3-pip
    pip install --break-system-packages mkdocs-techdocs-core

    mkdocs --version   # sanity check
        #mkdocs, version 1.6.1 from /usr/local/lib/python3.11/dist-packages/mkdocs (Python 3.11)
    cd backstage
    yarn start
        local: http://localhost:3000
    exit


