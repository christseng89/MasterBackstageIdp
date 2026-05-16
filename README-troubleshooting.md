# Troubleshooting — Master Backstage IdP

Real problems that bit during development of this project, with their fixes — grouped by symptom area so you can jump to the right section quickly.

For setup and architecture, see the [main README](./README.md).

## Contents

- [A. Deployment doesn't reflect your code change](#a-deployment-doesnt-reflect-your-code-change)
- [B. Pod starts but crashes immediately](#b-pod-starts-but-crashes-immediately)
- [C. Network slowness or timeouts from the in-cluster ARC pod](#c-network-slowness-or-timeouts-from-the-in-cluster-arc-pod)
- [D. CLI flag and image-build quirks](#d-cli-flag-and-image-build-quirks)
- [E. Runner environment gaps](#e-runner-environment-gaps)
- [F. Local laptop friction](#f-local-laptop-friction)

---

## A. Deployment doesn't reflect your code change

### `argocd app sync` succeeds but the pod still serves the old code

**Cause:** ArgoCD's `Path` doesn't match where CI/CD writes `values.yaml`.

**Fix:** In the ArgoCD application, ensure `Path = python-app/charts/python-app` exactly. The CD job rewrites `python-app/charts/python-app/values.yaml` — any other path means ArgoCD sees no diff.

### CD job fails with `argocd: command not found`

**Cause:** ARC runner pods are minimal and don't ship the ArgoCD CLI. The workflow's `Install ArgoCD CLI` step is responsible for putting the binary into `/tmp/argocd` (either by `docker pull`ing the mirror image or by restoring from `actions/cache`).

**Fix:** Make sure the `Install ArgoCD CLI` step exists and runs before `Argocd app sync`. Also confirm the mirror image exists on Docker Hub — if you bumped `ARGOCD_VERSION` in `cicd.yaml` without running `mirror-cli-binaries` first, the `docker pull` inside `Install ArgoCD CLI` will fail and `/tmp/argocd` won't be populated.

### CD job fails with `manifest for christseng89/argocd-bin:vX.Y.Z not found`

**Cause:** You bumped `ARGOCD_VERSION` in `cicd.yaml` but didn't re-run the mirror workflow for that new version.

**Fix:** Order matters. Always:

1. Run `mirror-cli-binaries` with the new version first (populates Docker Hub).
2. Then bump `ARGOCD_VERSION` in `cicd.yaml` and push.

Same rule applies for `YQ_VERSION`.

### CD job's `yq` step fails on ARM64 runner

**Cause:** Hardcoded `yq_linux_amd64` binary download — the wrong arch can't even execute.

**Fix:** The workflow already detects the runner architecture and pulls the matching arch from the Docker Hub mirror. Confirm the `Detect runner architecture` step runs before `Modify values file`.

---

## B. Pod starts but crashes immediately

### Pod shows `CrashLoopBackOff` with `exec /usr/local/bin/python: exec format error`

**Cause:** The container image's CPU architecture doesn't match the node. The GitHub-hosted CI runner is `linux/amd64`, but Surface Pro 11 / Apple Silicon nodes are `linux/arm64`.

**Fix:** The workflow already builds multi-arch via `docker/setup-qemu-action@v3` and `platforms: linux/amd64,linux/arm64`. Confirm with:

```cmd
docker buildx imagetools inspect christseng89/python-app:<tag>
```

You should see two `Manifests:` entries, one per platform.

---

## C. Network slowness or timeouts from the in-cluster ARC pod

> A common theme: ARC pods on Docker Desktop / Surface Pro 11 have **fast** access to Cloudflare-backed endpoints (`production.cloudflare.docker.com`) but **inconsistent** access to GitHub-controlled endpoints (`*.githubusercontent.com`, `auth.docker.io`). The pipeline is structured to keep slow operations off ARC.

### `Install ArgoCD CLI` step takes 10+ minutes (or hits the job timeout)

**Cause:** Direct download from GitHub Releases is slow from Asia (often 50–100 KB/s for the ~200 MB ARM64 binary), so the step blows past the CD job's `timeout-minutes: 25`. When the job times out, `actions/cache`'s post-step never runs, so the partial download is thrown away — every subsequent run starts from scratch (chicken-and-egg).

**Fix:** Use the Docker Hub mirror (see main README, Part 5, Step 5). Run the `mirror-cli-binaries` workflow once on a GitHub-hosted runner (fast); after that, every CD job pulls the binary from Cloudflare CDN in seconds rather than from GitHub Releases in hours.

### CD `Login to Docker Hub` step fails with `Client.Timeout exceeded while awaiting headers` against `auth.docker.io`

**Cause:** ARC pods can have intermittent egress problems specifically to `auth.docker.io`, even when `docker pull` against the Cloudflare-backed `production.cloudflare.docker.com` works fine. The two endpoints take different network paths from your cluster.

**Fix:** The CD job no longer runs `docker/login-action` at all — the mirror images are public on Docker Hub, so anonymous pulls work and don't need authentication. If you ever need to make the mirror repos private, you'll need to add the login step back and accept the occasional auth timeout (or wrap it in a retry-on-failure GitHub Action like `nick-fields/retry`).

### CI `Set up Docker Buildx` step hangs at 0.1 MB/s downloading from GitHub Releases

**Cause:** The CI job was set to `runs-on: [self-hosted, linux]` (ARC), which gave it the same slow path to GitHub Releases that hurt argocd. `docker/setup-buildx-action` downloads ~20 MB of buildx binary; at 0.1 MB/s that's 3+ minutes per run.

**Fix:** Move the CI job back to `runs-on: ubuntu-latest`. GitHub-hosted runners have fast internal access to GitHub Releases (seconds, not minutes), and the CI job doesn't need cluster access (it only talks to Docker Hub). Keep `cd` on ARC because only ARC pods can reach `argocd-server.argocd.svc.cluster.local`.

---

## D. CLI flag and image-build quirks

### `argocd login` fails with `WARNING: server is not configured with TLS. Proceed (y/n)?` and exits 20

**Cause:** `argocd-server` is configured with `server.insecure: "true"`, so it serves plain HTTP. The CLI defaults to HTTPS and falls back to an interactive prompt that EOFs in a non-interactive shell.

**Fix:** Add `--plaintext` (and drop `--insecure` / `--skip-test-tls` — those are HTTPS-only):

```bash
argocd login argocd-server.argocd.svc.cluster.local \
  --plaintext --grpc-web \
  --username admin --password "$ARGOCD_PASSWORD"
```

> Note: `argocd login` does **not** support `--password-stdin` (that flag exists only for `docker login`). The password must be passed via `--password <value>`. GitHub Actions masks the secret in logs, so the brief `ps`-visible exposure inside the runner pod is acceptable.

### `docker create` fails with `Error response from daemon: no command specified`

**Cause:** The mirror images (`christseng89/argocd-bin`, `christseng89/yq-bin`) are built `FROM scratch` with no `CMD` or `ENTRYPOINT`. Docker daemon refuses to create a container without a command — even though we only use `docker cp` and never actually start the container.

**Fix:** Pass any dummy arg to `docker create`; it's recorded but never executed. The workflow uses the file path itself for self-documentation:

```bash
cid=$(docker create christseng89/argocd-bin:v3.4.2 /argocd)
docker cp "$cid:/argocd" /tmp/argocd
docker rm "$cid"
```

The newer `mirror-cli-binaries.yaml` also adds `CMD ["/argocd"]` / `CMD ["/yq"]` to the Dockerfile so future re-mirrored images don't have this issue, but the workaround in `cicd.yaml` is harmless either way.

---

## E. Runner environment gaps

### Diagnose-on-failure step shows `kubectl: command not found`

**Cause:** Some ARC runner images don't bundle `kubectl`. The diagnostic step uses `|| true` so it doesn't fail the job, but it can't print pod details either.

**Fix:** Either switch to a runner image that includes `kubectl` (e.g., `summerwind/actions-runner` does), or add an `apt-get install -y kubectl` step before the diagnose step. The `argocd app get` / `argocd app history` parts of the diagnostic still work without `kubectl`.

---

## F. Local laptop friction

### `git status` reports `error: index uses ?<�d extension, which we do not understand` / `index file corrupt`

**Cause:** Git index sometimes corrupts on Windows after interrupted operations.

**Fix:** Rebuild it from `HEAD` (working-tree files are untouched):

```cmd
del .git\index
git reset
```

### Local `git push` rejected with `non-fast-forward` after the bot already pushed

**Cause:** The CD job's `EndBug/add-and-commit` pushed a `values.yaml` bump to `main` while you were editing locally.

**Fix:** Pull first, then push:

```bash
git pull --rebase
git push
```

Once-off setup so future pulls are clean and you don't accumulate merge commits:

```bash
git config --global pull.rebase true
```

Or enable VS Code's **Git: Autofetch** so the editor surfaces incoming commits in the Source Control panel within 60 seconds and you can pull with one click.
