# `intelligent-ltd` org-level self-hosted runner

> **Scope:** TESTING / EXPLORATION ONLY.
> Per-repo runners scaffolded by the Backstage `python-app` and
> `python-app-multi-apis` templates are **not affected** — they continue to
> use their own per-repo `RunnerDeployment` (`spec.template.spec.repository`)
> and per-repo secrets/variables. Nothing in this folder rewrites the
> templates' behaviour; it just adds an additional shared pool you can
> opt into from workflows under `intelligent-ltd`.

## What this gives you

A single ARC `RunnerDeployment` registered to the **GitHub organization**
`intelligent-ltd` (not to any specific repo). Workflows in any repo under
that org can route their jobs to it by writing:

```yaml
jobs:
  cd:
    runs-on: [self-hosted, org-runner]
```

The `org-runner` label is set in `spec.template.spec.labels` so the org
pool is only matched when explicitly opted into — your existing
`runs-on: self-hosted` jobs (without the extra label) keep falling through
to whatever per-repo runner you already have.

## What's in here

| File | Purpose |
|---|---|
| `org-runner.yaml` | 3 resources in one apply: `ServiceAccount`, `RunnerDeployment` (org-scope), `HorizontalRunnerAutoscaler` (`minReplicas: 1` so one runner is always idle and visible in the GitHub UI; flip back to 0 once you have a `workflow_job` webhook configured). `maxReplicas: 5`. |
| `webhook-server.yaml` | **Optional.** Standalone Deployment + Service for the ARC webhook server, used to enable true auto-scaling on `workflow_job` events. Only apply when ARC was installed without Helm — Helm users should enable via `helm upgrade ... --set githubWebhookServer.enabled=true` instead. See `## Optional: enable webhook server`. |

## Prerequisites

1. **ARC controller already running** in `actions-runner-system`.
2. **PAT in `actions-runner-system/controller-manager` secret must include `admin:org`.**

   The PAT you already use for per-repo runners probably only has `repo`+`workflow`,
   which is enough for repo-level registration but **not** for org-level. There are
   two ways to fix this — pick whichever is convenient:

   **Easiest — extend the existing PAT in place:**

   1. Go to <https://github.com/settings/tokens>
   2. Click the PAT that ARC is currently using
   3. Tick `admin:org` (auto-includes `write:org`, `read:org`, `manage_runners:org`)
   4. Click **Update token** at the bottom

   The token value does NOT change, so the K8s secret stays as is. Just restart
   the controller so it re-tries the failed RunnerDeployment immediately:

   ```bash
   kubectl -n actions-runner-system rollout restart deployment
   ```

   **Or — rotate to a brand new PAT** (only needed if the existing PAT is
   expired or you want to reset its scope from scratch):

   ```bash
   NEW_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
   kubectl -n actions-runner-system create secret generic controller-manager \
     --from-literal=github_token="$NEW_PAT" \
     --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n actions-runner-system rollout restart deployment
   ```

3. **`github-runners` namespace already exists** (it does, from the
   scaffolded `runner-rbac.yaml`).

## Apply

```bash
kubectl apply -f github-org-runner/org-runner.yaml
```

## Verify

```bash
# 1) RunnerDeployment + Pod exist
kubectl get runnerdeployment,pod -n github-runners | grep intelligent-ltd
#   should see RunnerDeployment AVAILABLE=1 and a pod 2/2 Running

# 2) Runner pod log shows successful org registration
POD=$(kubectl get pods -n github-runners --no-headers | grep '^intelligent-ltd-' | awk '{print $1}' | head -1)
kubectl logs -n github-runners "$POD" -c runner --tail=30 \
  | grep -iE 'gitHubUrl|organization|Connected|Listening'

# 3) GitHub API confirms the runner is attached to the org
#    (Git Bash users: omit leading slash to avoid MSYS path conversion)
gh api orgs/intelligent-ltd/actions/runners \
  --jq '.runners[] | {name, status, labels: [.labels[].name]}'

# 4) GitHub UI — Self-hosted runners tab on the org
#    https://github.com/organizations/intelligent-ltd/settings/actions/runners
```

## Use from a workflow (test)

In any repo under `intelligent-ltd`, add a job:

```yaml
jobs:
  test-org-runner:
    runs-on: [self-hosted, org-runner]
    steps:
      - run: |
          echo "Running on $(hostname) — org-level runner"
          echo "Runner name: $RUNNER_NAME"
```

Trigger it manually:

```bash
gh workflow run test-org-runner.yaml --repo intelligent-ltd/<some-repo>
gh run watch --repo intelligent-ltd/<some-repo>
```

Because the runner is **ephemeral**, the pod that runs your job exits when
the job completes; ARC immediately spins up a fresh pod to honour
`minReplicas: 1`. So the pod name suffix in `kubectl get pods` will change
across job runs — this is normal.

## Teardown (when done testing)

```bash
kubectl delete -f github-org-runner/org-runner.yaml
```

Removing this file does **not** affect per-repo runners scaffolded by the
templates.

## Optional: enable webhook server (true auto-scaling)

Without a webhook, the HRA's `scaleUpTriggers` never fires — GitHub never tells
ARC that new `workflow_job` events are queued, so the pool stays at
`minReplicas: 1`. For local Docker Desktop testing that's fine. To actually
scale up to `maxReplicas: 5` on demand, install the webhook server, expose it
to GitHub, and configure an org-level webhook.

### Which path applies to you?

Run this once to find out:

```bash
helm list -A | grep actions-runner-controller
```

| Output | Path | What to apply |
|---|---|---|
| One line listing `actions-runner-controller` | **Path A — Helm** | Use `helm upgrade --set githubWebhookServer.enabled=true` (see below). **Do NOT `kubectl apply` `webhook-server.yaml`** — it would duplicate the Deployment that Helm already owns. |
| Empty result | **Path B — standalone manifests** | `kubectl apply -f webhook-server.yaml` after creating the secret. |

> **This repo's current cluster is on Helm** (`actions-runner-controller-0.23.7 / app v0.27.6`).
> Use Path A. `webhook-server.yaml` is kept for reference / non-Helm reinstalls only.

### Path A — ARC was installed via Helm (preferred)

The webhook server ships in the same chart; just upgrade with one extra flag:

```bash
# Generate a shared secret (used by both K8s secret and GitHub webhook config)
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Keep this — you'll paste it into GitHub later:"
echo "$WEBHOOK_SECRET"

# Re-run the helm install/upgrade that originally deployed ARC, with extras.
# `--version 0.23.7` pins the chart to whatever you currently run so the upgrade
# only adds the webhook server and doesn't bump ARC itself.  Drop the pin when
# you want to consciously upgrade ARC at the same time.
helm upgrade actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system \
  --version 0.23.7 \
  --reuse-values \
  --set githubWebhookServer.enabled=true \
  --set githubWebhookServer.ports.http=8000 \
  --set githubWebhookServer.secret.create=true \
  --set githubWebhookServer.secret.github_webhook_secret_token="$WEBHOOK_SECRET"

# Helm-managed service name has the release prefix:
kubectl -n actions-runner-system get svc | grep webhook
#   actions-runner-controller-github-webhook-server   ClusterIP   ...
```

### Path B — ARC was installed via static manifests (no Helm)

Apply the standalone `webhook-server.yaml` in this folder:

```bash
# 1. Generate shared secret
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "$WEBHOOK_SECRET" > webhook-secret.txt   # save it for GitHub later

# 2. Create K8s secret BEFORE applying the manifest
kubectl -n actions-runner-system create secret generic github-webhook-server \
  --from-literal=github_webhook_secret_token="$WEBHOOK_SECRET"

# 3. Apply the Deployment + Service
kubectl apply -f github-org-runner/webhook-server.yaml
kubectl -n actions-runner-system get pods -l app.kubernetes.io/name=github-webhook-server
```

### Expose the webhook to GitHub

GitHub must reach the webhook server over the public internet. For Docker
Desktop, two zero-config options:

**ngrok (easiest):**

```bash
# Port-forward the K8s service to localhost
kubectl -n actions-runner-system port-forward svc/github-webhook-server 8000:80

# In another terminal, expose 8000 publicly
ngrok http 8000
# → ngrok gives you a public URL like https://abcd1234.ngrok-free.app
# Keep both terminals open while testing.
```

**cloudflared tunnel** (no signup required for quick tests):

```bash
kubectl -n actions-runner-system port-forward svc/github-webhook-server 8000:80
cloudflared tunnel --url http://localhost:8000
# → cloudflared prints a public URL like https://random-words.trycloudflare.com
```

Copy the public URL from whichever tool you used. You'll paste it into the
next step.

### Configure the GitHub org webhook

1. Go to <https://github.com/organizations/intelligent-ltd/settings/hooks>
2. Click **Add webhook**
3. Fill in:

   | Field | Value |
   |---|---|
   | **Payload URL** | The public URL from ngrok / cloudflared **+ `/`** (the webhook server listens at root) |
   | **Content type** | `application/json` |
   | **Secret** | The same `$WEBHOOK_SECRET` you generated above |
   | **SSL verification** | Enable (ngrok / cloudflared certs are valid) |
   | **Which events?** | Select **Let me select individual events** → tick only **Workflow jobs** |
   | **Active** | ☑ |

4. Click **Add webhook**. GitHub immediately sends a ping; check the webhook
   detail page → **Recent Deliveries** tab → green ✓ means the server is
   reachable.

### Verify the full loop

```bash
# Trigger a job that needs a runner the org pool would scale up for
gh workflow run test-org-runner.yaml --repo intelligent-ltd/<some-repo>

# Watch — within 10 seconds, ARC should scale from 1 to 2 pods
kubectl get pods -n github-runners -l 'app.kubernetes.io/component=runner' -w

# Cross-check: webhook server received the event
kubectl logs -n actions-runner-system -l app.kubernetes.io/name=github-webhook-server --tail=20 \
  | grep -i 'workflow_job\|scaling'
```

If scale-up worked, you can now flip `org-runner.yaml`'s `minReplicas` from
`1` back to `0` for true scale-to-zero — the webhook will wake the pool on
demand.

### Teardown

```bash
# Path A (Helm):
helm upgrade actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system --reuse-values \
  --set githubWebhookServer.enabled=false

# Path B (standalone manifest):
kubectl delete -f github-org-runner/webhook-server.yaml
kubectl -n actions-runner-system delete secret github-webhook-server

# Delete the GitHub webhook from the UI as well.
```

---

## See also

- Root `README-Recap4GithubOrg.md` §5 — context on `intelligent-ltd` org
  setup, which template files would need to change to move scaffolded
  apps fully into the org, and the relationship between per-repo and
  org-level runners.
- Classic ARC docs: <https://github.com/actions/actions-runner-controller>
  (note: ARC v1 / `summerwind.dev` is in maintenance mode; long-term you
  should evaluate ARC v2 / Runner Scale Sets at
  <https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller>)
