# Triggering Backstage Catalog Refresh from GitHub Actions

How to make Backstage pick up changes to a repo's `catalog-info.yaml` —
including `apiVersion` bumps, metadata edits, or new annotations — using
a GitHub Actions workflow.

---

## Overview

Backstage discovers entities by reading `catalog-info.yaml` files from
registered locations. When that file changes (e.g. you bump an
`apiVersion` on an `API` entity), Backstage needs to re-ingest it before
the UI reflects the change.

There are **two ways** for the refresh to happen:

| Path | How it works | Latency | Setup effort |
| --- | --- | --- | --- |
| **Passive polling** *(default)* | Backstage catalog processor polls every registered location on a schedule | ~100s (configurable) | None — already enabled |
| **Active push** | A GitHub Actions workflow `POST`s to `/api/catalog/refresh` whenever `catalog-info.yaml` changes | <5s after merge | One-time auth setup + workflow file |

For most teams the default polling is sufficient. Use the active push
path when you need instant updates (e.g. dashboards rely on the new
version before the build finishes).

---

## Prerequisites

- Backstage is deployed and reachable from your GitHub Actions runners.
  This guide assumes self-hosted runners inside the same Kubernetes
  cluster as Backstage, addressed via
  `http://backstage.backstage.svc.cluster.local:7007`.
- You have `kubectl` access to the cluster.
- You have the `gh` CLI authenticated against the GitHub org that owns
  the repo.

---

## Part A: Generate `BACKSTAGE_CI_TOKEN`

The token is a high-entropy random string you generate yourself.
Backstage compares it byte-for-byte against the `Authorization: Bearer`
header on incoming requests. The same value goes in two places:

1. The Backstage backend (as the expected token).
2. A GitHub Actions secret (sent by the workflow).

### Step 1 — Generate the value

Run **one** of the following on your workstation. Don't commit the
output anywhere.

```bash
# Linux / macOS / Git Bash
openssl rand -base64 32

# Alternative — Node (already available wherever Backstage runs)
node -p "require('crypto').randomBytes(32).toString('base64')"
```

Sample output:

```
Qj7y9z2X8mNk4pL3vR1wH6tF5sA0bC8dE9gJiK2nO4=
```

Copy this exact value (no trailing newline). You'll paste it twice in
the next steps.

### Step 2 — Store the token as a Kubernetes Secret

```bash
kubectl create secret generic backstage-auth \
  --namespace backstage \
  --from-literal=BACKSTAGE_CI_TOKEN='Qj7y9z2X8mNk4pL3vR1wH6tF5sA0bC8dE9gJiK2nO4='
```

### Step 3 — Reference the Secret in the Backstage deployment

Edit your Backstage deployment manifest (or Helm values) so the
container exposes the token as an env var:

```yaml
spec:
  template:
    spec:
      containers:
        - name: backstage
          env:
            - name: BACKSTAGE_CI_TOKEN
              valueFrom:
                secretKeyRef:
                  name: backstage-auth
                  key: BACKSTAGE_CI_TOKEN
```

### Step 4 — Tell Backstage to accept the token

Add an `externalAccess` block to `app-config.yaml` (or
`app-config.production.yaml`):

```yaml
backend:
  auth:
    externalAccess:
      - type: static
        options:
          token: ${BACKSTAGE_CI_TOKEN}      # env var lookup
          subject: github-actions-ci        # shows up in audit logs
        accessRestrictions:
          - plugin: catalog                 # least privilege
```

The `${BACKSTAGE_CI_TOKEN}` syntax tells Backstage to read the value
from the env var injected in Step 3 — so the secret itself is never
committed to your config repo.

### Step 5 — Roll the Backstage deployment

```bash
kubectl rollout restart deploy/backstage -n backstage
kubectl rollout status  deploy/backstage -n backstage
```

Confirm the env var arrived inside the pod:

```bash
kubectl exec -it -n backstage deploy/backstage -- bash
# inside the container:
echo "$BACKSTAGE_CI_TOKEN"        # should print the token
printenv | grep -i backstage      # broader sanity check
exit
```

---

## Part B: Store the token as a GitHub Actions secret

The GitHub Actions side needs the same value. Use the `gh` CLI:

```bash
# Org-wide (preferred for templates — every scaffolded repo inherits it)
gh secret set BACKSTAGE_TOKEN \
  --org christseng89 \
  --visibility all \
  --body 'Qj7y9z2X8mNk4pL3vR1wH6tF5sA0bC8dE9gJiK2nO4='

# Or per-repo
gh secret set BACKSTAGE_TOKEN \
  --repo christseng89/python-johnny \
  --body 'Qj7y9z2X8mNk4pL3vR1wH6tF5sA0bC8dE9gJiK2nO4='
```

> **Note the naming asymmetry:** the env var inside the Backstage pod
> is `BACKSTAGE_CI_TOKEN`, but the GitHub Actions secret is
> `BACKSTAGE_TOKEN`. Same value, different systems, different naming
> conventions.

If you'd like the template's `setup.sh` to provision the secret during
scaffolding, add the value to your local `.env` and add this line
alongside the other `gh secret set` calls:

```bash
# .env
BACKSTAGE_CI_TOKEN=Qj7y9z2X8mNk4pL3vR1wH6tF5sA0bC8dE9gJiK2nO4=
```

```bash
# setup.sh, Step 2
gh secret set BACKSTAGE_TOKEN --body "$BACKSTAGE_CI_TOKEN" --repo "$REPO"
```

---

## Part C: Add the refresh workflow

Create a new workflow file in your repo at
`.github/workflows/<app-name>-catalog-refresh.yaml`:

```yaml
name: ${{values.app_name}}-catalog-refresh

on:
  push:
    paths:
      - catalog-info.yaml
    branches: [main]
  workflow_dispatch:

jobs:
  refresh:
    # Self-hosted runner so backstage.backstage.svc.cluster.local resolves.
    # Use ubuntu-latest only if Backstage is exposed on a public URL.
    runs-on: [self-hosted, linux]
    timeout-minutes: 5
    env:
      BACKSTAGE_URL: http://backstage.backstage.svc.cluster.local:7007
      ENTITY_REF: component:default/${{values.app_name}}
    steps:
      - name: Refresh Backstage entity
        shell: bash
        run: |
          set -euo pipefail
          curl -fsSL -X POST \
            -H "Authorization: Bearer ${{ secrets.BACKSTAGE_TOKEN }}" \
            -H "Content-Type: application/json" \
            -d "{\"entityRef\": \"${ENTITY_REF}\"}" \
            "${BACKSTAGE_URL}/api/catalog/refresh"
          echo "Triggered refresh for ${ENTITY_REF}"
```

Design choices worth knowing:

- **`paths: catalog-info.yaml`** — the workflow only fires when that
  file actually changes. An `apiVersion` bump triggers it; a normal
  `src/**` push does not.
- **`runs-on: [self-hosted, linux]`** — same reason your CD workflow
  uses it. The in-cluster service DNS doesn't resolve from
  GitHub-hosted runners. If Backstage is exposed externally (e.g.
  `https://backstage.test.com`), switch to `ubuntu-latest` and update
  `BACKSTAGE_URL`.
- **Entity ref format** — `<kind>:<namespace>/<name>`. For a Component
  named `python-johnny` in the default namespace it's
  `component:default/python-johnny`.

---

## Part D: Verify end-to-end

### D.1 — Direct cURL test

From inside the cluster (e.g. a runner pod in your `python-johnny`
namespace, or by `kubectl exec` into any pod), run:

```bash
curl -i -X POST \
  -H "Authorization: Bearer $BACKSTAGE_CI_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entityRef": "component:default/python-johnny"}' \
  http://backstage.backstage.svc.cluster.local:7007/api/catalog/refresh
```

Expected responses:

| Status | Meaning | Fix |
| --- | --- | --- |
| `200 OK` | Refresh queued | You're done |
| `401 Unauthorized` | Token mismatch | Re-check both copies are byte-identical — no trailing newline, no truncated paste |
| `403 Forbidden` | Token valid but `accessRestrictions` blocks the plugin | Check `plugin: catalog` is spelled correctly |
| `404 Not Found` | Entity ref doesn't exist | Run `curl .../api/catalog/entities` to list known refs |

### D.2 — End-to-end workflow test

1. In the scaffolded repo, edit `catalog-info.yaml` — e.g. change
   `metadata.description` or bump an `apiVersion`.
2. Commit and push to `main`.
3. Watch the `*-catalog-refresh` workflow run in GitHub Actions.
4. Open the entity in the Backstage UI — the change should be visible
   within seconds.

### D.3 — If you can't `docker exec` into the Backstage container

If Backstage runs in Kubernetes (not plain Docker), `docker exec` won't
find it. Use `kubectl exec` instead — the `--` separates kubectl's
flags from the command to run inside:

```bash
# Find the pod
kubectl get pods -n backstage

# Drop into a shell
kubectl exec -it -n backstage deploy/backstage -- bash
# Or by exact pod name
kubectl exec -it -n backstage backstage-7d8f9c5b6-abcde -- bash
```

If `bash` isn't installed (Alpine-based images), fall back to `sh`:

```bash
kubectl exec -it -n backstage deploy/backstage -- sh
```

---

## Part E: Refreshing multiple entities

If your `catalog-info.yaml` declares more than one entity (a Component
*plus* an API, for example), refresh each one. Add this to the
workflow step instead of the single curl:

```bash
for REF in \
  "component:default/${APP_NAME}" \
  "api:default/${APP_NAME}-api"; do
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${{ secrets.BACKSTAGE_TOKEN }}" \
    -H "Content-Type: application/json" \
    -d "{\"entityRef\": \"${REF}\"}" \
    "${BACKSTAGE_URL}/api/catalog/refresh"
done
```

---

## Part F: Token rotation

Treat `BACKSTAGE_CI_TOKEN` like any other shared secret.

1. Generate a fresh value (Step 1 above).
2. Add a **second** `externalAccess` entry to `app-config.yaml`
   alongside the existing one — both tokens accepted simultaneously.
3. `kubectl rollout restart deploy/backstage`.
4. Update the GitHub Actions secret (`gh secret set BACKSTAGE_TOKEN`).
5. Once you've confirmed workflows are succeeding with the new value,
   remove the old `externalAccess` entry and roll Backstage again.

Rotate at least annually, or immediately if a runner pod is ever
compromised.

---

## Appendix: Alternatives

### A. Reduce the polling interval

If you don't want active push but find ~100s too slow, lower the
default in `app-config.yaml`:

```yaml
catalog:
  processingInterval: { seconds: 30 }
```

The trade-off is more load on the catalog backend.

### B. GitHub webhook → Backstage events

For orgs with many repos where you don't want a workflow in each one,
install:

- `@backstage/plugin-events-backend`
- `@backstage/plugin-catalog-backend-module-github`

Configure an org-level GitHub webhook pointed at
`https://backstage.test.com/api/events/http/github`. Backstage then
refreshes affected entities automatically on every push.

Setup is heavier (webhook secret, event router config) but scales
better than per-repo workflows.

### C. OIDC federation

For prod-grade environments, replace the static token with OIDC trust
between GitHub Actions and Backstage. Short-lived tokens minted per
workflow run, no shared secret to rotate. Overkill unless you're
shipping multiple critical services through this path.

---

## Quick reference

```text
┌─────────────────────┐         ┌──────────────────────────────────┐
│  GitHub repo        │         │  Backstage backend                │
│                     │         │                                   │
│  catalog-info.yaml  │         │  app-config.yaml                  │
│      │              │         │    backend.auth.externalAccess    │
│      │ push         │         │      - type: static               │
│      ▼              │         │        token: ${BACKSTAGE_CI_…}   │
│  Actions workflow   │  POST   │                                   │
│   curl --bearer ────┼────────▶│  /api/catalog/refresh             │
│   ${{ secrets.       │         │      ▲                            │
│     BACKSTAGE_TOKEN}}│         │      │ compares Bearer token to  │
│                     │         │      └─ env var BACKSTAGE_CI_TOKEN│
└─────────────────────┘         └──────────────────────────────────┘
```

## Troubleshooting

Backstage => Catalog => Select Component => Kubernetes

- If the pos error, then kubectl rollout restart deployment <name-of-app-deployment> -n <namespace>
  For example, kubectl rollout restart deployment python-app -n python-app
- One Backstage catalog can refer to all related environments in Kubernetes, such as dev, staging, prod. 
