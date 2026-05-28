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
| `org-runner.yaml` | 3 resources in one apply: `ServiceAccount`, `RunnerDeployment` (org-scope), `HorizontalRunnerAutoscaler` (`minReplicas: 1` so one runner is always idle and visible in the GitHub UI; flip back to 0 once you have a `workflow_job` webhook configured). |

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

## See also

- Root `README-Recap4GithubOrg.md` §5 — context on `intelligent-ltd` org
  setup, which template files would need to change to move scaffolded
  apps fully into the org, and the relationship between per-repo and
  org-level runners.
- Classic ARC docs: <https://github.com/actions/actions-runner-controller>
  (note: ARC v1 / `summerwind.dev` is in maintenance mode; long-term you
  should evaluate ARC v2 / Runner Scale Sets at
  <https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller>)
