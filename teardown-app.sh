#!/usr/bin/env bash
# teardown-app.sh — Full cleanup of a Backstage-scaffolded app.
#
# Removes, in safe dependency order:
#   1. ArgoCD applications  (<app>-dev, -staging, -prod)
#   2. ArgoCD repository registration
#   3. K8s namespaces       (<app>-dev, -staging, -prod) — defensive
#   4. ARC self-hosted runner (RunnerDeployment + per-app ServiceAccount)
#   5. Backstage catalog entities (1 Component + N API entities)
#   6. GitHub repository
#   7. Windows hosts file entries
#
# Usage:
#   bash teardown-app.sh <app-name>
#   bash teardown-app.sh <app-name> --yes               # skip the prompt
#   bash teardown-app.sh <app-name> --skip-github       # keep GitHub repo
#   bash teardown-app.sh <app-name> --skip-backstage    # keep catalog entries
#   bash teardown-app.sh <app-name> --skip-hosts        # keep hosts entries
#
# Requirements:
#   - .env in cwd with ARGOCD_PASSWORD (and optionally BACKSTAGE_TOKEN)
#   - gh CLI authenticated (with delete_repo scope if --skip-github not set)
#   - kubectl pointing at docker-desktop context
#   - argocd CLI installed and reachable at $ARGOCD_SERVER
#   - Backstage backend running at $BACKSTAGE_URL (default http://localhost:7007)

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
APP="${1:-}"
if [ -z "$APP" ] || [ "${APP:0:2}" = "--" ]; then
  echo "Usage: bash $(basename "$0") <app-name> [--yes] [--skip-github] [--skip-backstage] [--skip-hosts]" >&2
  exit 1
fi
shift

SKIP_GITHUB=false
SKIP_BACKSTAGE=false
SKIP_HOSTS=false
YES=false
for arg in "$@"; do
  case "$arg" in
    --yes)            YES=true ;;
    --skip-github)    SKIP_GITHUB=true ;;
    --skip-backstage) SKIP_BACKSTAGE=true ;;
    --skip-hosts)     SKIP_HOSTS=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Config — override via .env or env vars before running
# ---------------------------------------------------------------------------
GITHUB_OWNER="${GITHUB_OWNER:-christseng89}"
BACKSTAGE_URL="${BACKSTAGE_URL:-http://localhost:7007}"
RUNNER_NS="${RUNNER_NS:-github-runners}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd.test.com:9080}"
HOSTS=/c/Windows/System32/drivers/etc/hosts

if [ -f .env ]; then
  # shellcheck source=/dev/null
  source .env
fi
: "${ARGOCD_PASSWORD:?ARGOCD_PASSWORD must be set in .env or environment}"

REPO="$GITHUB_OWNER/$APP"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
skip() { printf '  ↷ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*" >&2; }

# kubectl delete that swallows "not found"
kdel() {
  kubectl delete "$@" --ignore-not-found=true 2>&1 | sed 's/^/    /' || true
}

# ---------------------------------------------------------------------------
# Pre-flight checks — fail fast on missing deps/env vars so we don't hang
# half-way through.  Each check prints what's missing AND what's the
# corresponding --skip-* flag (so user can re-run without that surface).
# ---------------------------------------------------------------------------
preflight_errors=0
preflight_warnings=0

preflight_fail() {
  printf '  ✗ %s\n' "$*" >&2
  preflight_errors=$((preflight_errors + 1))
}
preflight_warn() {
  printf '  ⚠ %s\n' "$*" >&2
  preflight_warnings=$((preflight_warnings + 1))
}

printf '\n→ Pre-flight checks\n'

# --- required everywhere ---
if ! command -v kubectl >/dev/null 2>&1; then
  preflight_fail "kubectl not found in PATH — required for Steps 3 and 4"
elif ! kubectl cluster-info >/dev/null 2>&1; then
  preflight_fail "kubectl can't reach the cluster — run 'kubectl config use-context docker-desktop'"
else
  ok "kubectl reachable"
fi

# --- argocd CLI (optional — falls back to kubectl, but worth telling the user) ---
if ! command -v argocd >/dev/null 2>&1; then
  preflight_warn "argocd CLI not found — Steps 1/2 will use kubectl fallback (Application/repo registration won't be cleanly deregistered)"
else
  ok "argocd CLI present"
  # Probe TCP reachability before login, so a wrong ARGOCD_SERVER fails here
  # instead of hanging Step 1.  argocd-cli itself does the login attempt later.
  host="${ARGOCD_SERVER%:*}"
  port="${ARGOCD_SERVER##*:}"
  if ! timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
    preflight_warn "ArgoCD server '$ARGOCD_SERVER' unreachable — Steps 1/2 will use kubectl fallback"
  else
    ok "ArgoCD server $ARGOCD_SERVER reachable"
  fi
fi

# --- GitHub CLI (only if NOT --skip-github) ---
if [ "$SKIP_GITHUB" != true ]; then
  if ! command -v gh >/dev/null 2>&1; then
    preflight_fail "gh CLI not found — install it or re-run with --skip-github"
  elif ! gh auth status >/dev/null 2>&1; then
    preflight_fail "gh CLI not authenticated — run 'gh auth login' or re-run with --skip-github"
  else
    # Check delete_repo scope
    if ! gh auth status 2>&1 | grep -q 'delete_repo'; then
      preflight_warn "gh PAT may lack 'delete_repo' scope — Step 6 will warn and ask you to run: gh auth refresh -h github.com -s delete_repo"
    else
      ok "gh CLI authenticated with delete_repo scope"
    fi
  fi
fi

# --- Backstage backend (only if NOT --skip-backstage) ---
# Probe semantics: ANY HTTP response (200, 401, 403, 404...) proves the server
# is listening.  Only a connection failure / timeout counts as "not reachable".
# Without -f, curl returns 0 for HTTP errors too, so we use -w '%{http_code}'
# and treat anything >= 100 as "server up".
if [ "$SKIP_BACKSTAGE" != true ]; then
  if ! command -v curl >/dev/null 2>&1; then
    preflight_warn "curl not found — Step 5 will be a no-op; remove entity manually via Backstage UI"
  else
    BS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
              "$BACKSTAGE_URL/api/catalog/entities?limit=1" 2>/dev/null || echo "000")
    if [ "$BS_CODE" = "000" ]; then
      preflight_warn "Backstage at $BACKSTAGE_URL not reachable (no HTTP response) — Step 5 will print manual UI steps. Start backend with 'yarn start' or re-run with --skip-backstage."
    elif [ "$BS_CODE" = "401" ] || [ "$BS_CODE" = "403" ]; then
      if [ -n "${BACKSTAGE_TOKEN:-}" ]; then
        ok "Backstage reachable at $BACKSTAGE_URL (HTTP $BS_CODE — using BACKSTAGE_TOKEN for Step 5)"
      else
        ok "Backstage reachable at $BACKSTAGE_URL (HTTP $BS_CODE — SSO/auth enabled; Step 5 will print manual UI steps)"
      fi
    elif [ "$BS_CODE" -ge 200 ] && [ "$BS_CODE" -lt 500 ]; then
      ok "Backstage reachable at $BACKSTAGE_URL (HTTP $BS_CODE)"
    else
      preflight_warn "Backstage at $BACKSTAGE_URL returned HTTP $BS_CODE — server up but API endpoint may be wrong"
    fi
  fi
fi

# --- Windows hosts (only if NOT --skip-hosts AND on Windows-like path) ---
if [ "$SKIP_HOSTS" != true ] && [ -f "$HOSTS" ] && [ ! -w "$HOSTS" ]; then
  preflight_warn "$HOSTS not writable — Step 7 will print manual commands. Re-open Git Bash as Administrator if you want auto-cleanup"
fi

# --- Bail out on hard failures ---
if [ "$preflight_errors" -gt 0 ]; then
  printf '\n✗ %d hard error(s) above — fix them or use --skip-* flags, then re-run.\n' "$preflight_errors" >&2
  exit 1
fi
if [ "$preflight_warnings" -gt 0 ]; then
  printf '  (%d warning(s) — script will continue with reduced effect on those surfaces.)\n' "$preflight_warnings"
fi

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
if [ "$YES" != true ]; then
  cat <<INFO
About to delete EVERYTHING related to:  $APP

  1. ArgoCD apps        : $APP-dev / $APP-staging / $APP-prod
  2. ArgoCD repo        : https://github.com/$REPO
  3. K8s namespaces     : $APP-dev / $APP-staging / $APP-prod
  4. ARC runner         : $APP-self-hosted-runner (ns=$RUNNER_NS)
  5. Backstage catalog  : 1 Component + N API entities  $([ "$SKIP_BACKSTAGE" = true ] && echo '(SKIPPED)')
  6. GitHub repository  : $REPO                          $([ "$SKIP_GITHUB"    = true ] && echo '(SKIPPED)')
  7. Windows hosts      : $APP-{dev,staging,prod}.test.com  $([ "$SKIP_HOSTS"   = true ] && echo '(SKIPPED)')

This is IRREVERSIBLE.
INFO
  read -rp "Type the app name '$APP' to confirm: " typed
  if [ "$typed" != "$APP" ]; then
    echo "Confirmation mismatch. Aborting." >&2
    exit 1
  fi
fi

# ===========================================================================
# Step 1 — ArgoCD applications (cascade-deletes all managed K8s resources)
# ===========================================================================
# Try argocd CLI first; if it hangs (cert prompt, port closed, missing CLI) we
# fall through to kubectl after 15 seconds.  </dev/null closes stdin so any
# interactive prompt fails immediately rather than blocking the script.
log "Step 1: ArgoCD applications"
ARGOCD_OK=false
if command -v argocd >/dev/null 2>&1; then
  if timeout 15 argocd login "$ARGOCD_SERVER" \
       --username admin --password "$ARGOCD_PASSWORD" \
       --insecure --grpc-web </dev/null >/dev/null 2>&1; then
    ARGOCD_OK=true
  else
    warn "argocd login did not succeed within 15s (timeout / cert prompt / wrong server)"
  fi
else
  warn "argocd CLI not installed; using kubectl directly"
fi

if [ "$ARGOCD_OK" = true ]; then
  for env in dev staging prod; do
    name="$APP-$env"
    if argocd app get "$name" </dev/null >/dev/null 2>&1; then
      if timeout 30 argocd app delete "$name" --cascade --yes </dev/null >/dev/null 2>&1; then
        ok "deleted ArgoCD app $name"
      else
        warn "argocd app delete $name timed out; falling back to kubectl"
        kdel application.argoproj.io "$name" -n "$ARGOCD_NS"
      fi
    else
      skip "$name not found in ArgoCD"
    fi
  done
else
  # kubectl fallback — works even without argocd CLI / port reachable
  for env in dev staging prod; do
    name="$APP-$env"
    if kubectl get application.argoproj.io "$name" -n "$ARGOCD_NS" &>/dev/null; then
      kdel application.argoproj.io "$name" -n "$ARGOCD_NS"
      ok "deleted Application/$name via kubectl"
    else
      skip "$name not found"
    fi
  done
fi

# ===========================================================================
# Step 2 — ArgoCD repository registration
# ===========================================================================
log "Step 2: ArgoCD repository registration"
REPO_URL="https://github.com/$REPO"
if [ "$ARGOCD_OK" = true ]; then
  if timeout 15 argocd repo get "$REPO_URL" </dev/null >/dev/null 2>&1; then
    if timeout 15 argocd repo rm "$REPO_URL" </dev/null >/dev/null 2>&1; then
      ok "deregistered $REPO_URL"
    else
      warn "argocd repo rm failed (may already be gone)"
    fi
  else
    skip "$REPO_URL not registered in ArgoCD"
  fi
else
  skip "ArgoCD CLI unavailable — repo deregistration skipped (Application deletion already cleaned up its dependencies)"
fi

# ===========================================================================
# Step 3 — K8s namespaces (defensive — ArgoCD cascade should have done this)
# ===========================================================================
# Sequence per namespace:
#   3a. kubectl delete ns         (graceful, respects finalizers)
#   3b. wait up to 30s for it to disappear
#   3c. if still in Terminating state, list orphaned resources for the user
#       and finalize by patching out spec.finalizers (last resort)
log "Step 3: K8s namespaces"
for env in dev staging prod; do
  ns="$APP-$env"
  if ! kubectl get ns "$ns" &>/dev/null; then
    skip "namespace $ns not present"
    continue
  fi

  # 3a — graceful delete
  kubectl delete namespace "$ns" --wait=false --ignore-not-found=true 2>&1 | sed 's/^/    /' || true

  # 3b — wait up to 30s for it to actually leave the cluster
  for i in 1 2 3 4 5 6; do
    if ! kubectl get ns "$ns" &>/dev/null; then
      ok "deleted namespace $ns"
      continue 2
    fi
    sleep 5
  done

  # 3c — still around → it's stuck in Terminating because a finalizer is blocking
  warn "namespace $ns stuck in Terminating after 30s — likely a finalizer"
  warn "still-present resources blocking shutdown:"
  while read -r resource; do
    kubectl get "$resource" -n "$ns" --ignore-not-found 2>/dev/null | tail -n +2
  done < <(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null) \
    | head -20 | sed 's/^/      /' || true

  # Re-check first — by the time we got here, the namespace may have actually
  # finished terminating (kubectl get listed some pods as "Terminating" not
  # because they're blocking but because they're on their way out).
  if ! kubectl get ns "$ns" &>/dev/null; then
    ok "namespace $ns finished terminating during the wait — no force-finalize needed"
    continue
  fi

  # Force-finalize by stripping spec.finalizers from the namespace object.
  # This is the documented escape hatch for "stuck Terminating" namespaces:
  # https://kubernetes.io/docs/tasks/administer-cluster/namespaces/#deleting-a-namespace
  warn "force-finalizing $ns by patching out spec.finalizers"
  NS_JSON=$(kubectl get namespace "$ns" -o json 2>/dev/null || true)
  if [ -z "$NS_JSON" ]; then
    ok "namespace $ns disappeared between checks — done"
    continue
  fi
  printf '%s' "$NS_JSON" \
    | python3 -c "import sys, json; ns=json.load(sys.stdin); ns.get('spec',{})['finalizers']=[]; print(json.dumps(ns))" \
    | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - >/dev/null 2>&1 \
    && ok "force-finalized $ns" \
    || warn "force-finalize failed; investigate with: kubectl describe ns $ns"
done

# ===========================================================================
# Step 4 — ARC self-hosted runner
# ===========================================================================
log "Step 4: ARC self-hosted runner"
RD="$APP-self-hosted-runner"
if kubectl get runnerdeployment "$RD" -n "$RUNNER_NS" &>/dev/null; then
  kdel runnerdeployment "$RD" -n "$RUNNER_NS"
  ok "deleted RunnerDeployment $RD"
else
  skip "RunnerDeployment $RD not present"
fi
if kubectl get serviceaccount "$RD" -n "$RUNNER_NS" &>/dev/null; then
  kdel serviceaccount "$RD" -n "$RUNNER_NS"
  ok "deleted ServiceAccount $RD"
fi

# ===========================================================================
# Step 5 — Backstage catalog entities
# ---------------------------------------------------------------------------
# Why this is mostly manual:
#   Backstage is typically wired to GitHub OAuth SSO; the catalog API rejects
#   anonymous calls (HTTP 401) and there's no clean way to mint a backend token
#   from a shell script.  Rather than fight that, we PRINT explicit UI steps
#   the user can follow in ~30 seconds.
#
# Auto-delete only happens if BACKSTAGE_TOKEN is set in .env (advanced users
# who've extracted a Bearer token from DevTools or configured static auth).
# ===========================================================================
if [ "$SKIP_BACKSTAGE" = true ]; then
  log "Step 5: Backstage catalog (SKIPPED)"
elif [ -n "${BACKSTAGE_TOKEN:-}" ]; then
  log "Step 5: Backstage catalog (BACKSTAGE_TOKEN set — attempting API delete)"
  AUTH=(-H "Authorization: Bearer $BACKSTAGE_TOKEN")

  # ---------------------------------------------------------------------------
  # Helpers — these survive Git Bash MSYS quirks because:
  #   (a) python3 -c uses single-quoted single-line code (no embedded newlines)
  #   (b) $APP is passed as sys.argv[1], not interpolated into Python source
  #   (c) HTTP status is always checked before parsing — no silent JSON failures
  # ---------------------------------------------------------------------------
  # bs_delete_uid <uid> — DELETE entity by uid, return 0 on 204/200
  bs_delete_uid() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "${AUTH[@]}" \
      "$BACKSTAGE_URL/api/catalog/entities/by-uid/$1" 2>/dev/null || echo "000")
    [ "$code" = "204" ] || [ "$code" = "200" ]
  }

  # 5a. Find Location entities whose target contains <APP>, delete them.
  #     Locations must die FIRST — otherwise the catalog processor will re-
  #     register the Component+API on the next refresh (~100s).
  LOC_BODY=$(mktemp)
  LOC_CODE=$(curl -s -o "$LOC_BODY" -w '%{http_code}' "${AUTH[@]}" \
    "$BACKSTAGE_URL/api/catalog/entities?filter=kind=location" 2>/dev/null || echo "000")
  if [ "$LOC_CODE" = "200" ]; then
    # Single-line Python; $APP passed via argv to avoid bash interpolation into source.
    LOC_UIDS=$(python3 -c 'import sys,json,re; data=json.load(sys.stdin); APP=sys.argv[1]; pat=re.compile(r"(^|[/:])"+re.escape(APP)+r"(/|$)"); [print(e["metadata"]["uid"]) for e in data if pat.search(e.get("spec",{}).get("target","") or "")]' "$APP" < "$LOC_BODY" 2>/dev/null || true)
    if [ -n "$LOC_UIDS" ]; then
      while IFS= read -r uid; do
        [ -z "$uid" ] && continue
        if bs_delete_uid "$uid"; then
          ok "deleted Location entity $uid"
        else
          warn "Location $uid: DELETE failed (returned non-2xx)"
        fi
      done <<< "$LOC_UIDS"
    else
      skip "no Location entity targets $APP"
    fi
  else
    warn "Location list returned HTTP $LOC_CODE — token may be expired (or backend down). Falling through to by-name sweep."
  fi
  rm -f "$LOC_BODY"

  # 5b. By-name sweep for Component + API entities.
  #     Uses ?filter=metadata.name=... (array response) instead of /by-name
  #     because filter is more resilient to namespace/quoting quirks and
  #     returns [] for not-found instead of 404 — much easier to handle.
  ENTITIES=("component:$APP")
  for v in v1 v2 v3 v4 v5 v6; do
    ENTITIES+=("api:$APP-api-$v")
  done
  ENTITIES+=("api:$APP-api")   # single-API template

  found_any=false
  for ref in "${ENTITIES[@]}"; do
    kind="${ref%%:*}"
    name="${ref#*:}"
    TMP_BODY=$(mktemp)
    HTTP_CODE=$(curl -s -o "$TMP_BODY" -w '%{http_code}' "${AUTH[@]}" \
      "$BACKSTAGE_URL/api/catalog/entities?filter=kind=$kind,metadata.name=$name" 2>/dev/null || echo "000")
    case "$HTTP_CODE" in
      200)
        # Single-line; reads stdin (no path quoting issues).
        ENTITY_UID=$(python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["metadata"]["uid"]) if d else None' < "$TMP_BODY" 2>/dev/null || true)
        if [ -n "$ENTITY_UID" ] && [ "$ENTITY_UID" != "None" ]; then
          if bs_delete_uid "$ENTITY_UID"; then
            ok "deleted $kind:default/$name (uid=$ENTITY_UID)"
            found_any=true
          else
            warn "$kind:default/$name found (uid=$ENTITY_UID) but DELETE failed"
          fi
        fi
        # else: empty array — entity genuinely not present, silent
        ;;
      401|403) warn "$kind:default/$name → HTTP $HTTP_CODE (BACKSTAGE_TOKEN expired?)" ;;
      000)     warn "$kind:default/$name → no HTTP response — backend down" ;;
      *)       warn "$kind:default/$name → unexpected HTTP $HTTP_CODE (body: $(head -c 200 "$TMP_BODY" 2>/dev/null))" ;;
    esac
    rm -f "$TMP_BODY"
  done
  [ "$found_any" = false ] && skip "no $APP entities found via API (already gone)"

else
  # No BACKSTAGE_TOKEN — print manual UI steps.  This is the normal path for
  # the typical SSO-protected Backstage install.
  log "Step 5: Backstage catalog — MANUAL ACTION REQUIRED"
  cat >&2 <<EOF
  ⚠ Backstage catalog requires SSO / token auth; script cannot delete via API.
  ⚠ No BACKSTAGE_TOKEN in .env, so this step will not call the catalog API.

  → Open Backstage UI and remove $APP manually (≈30 seconds):

     1. ${BACKSTAGE_URL/7007/3000}/catalog                 ← open this URL
     2. Search box: type    $APP
     3. Click the Component entity   '$APP'
     4. Top-right ⋮ menu  →  'Unregister entity'
     5. In the dialog, choose  'Unregister Location'
        (this also removes the API entity/entities tied to the same
         catalog-info.yaml — Component + APIs disappear together)
     6. (Optional) Switch Kind filter to 'API' and confirm no
        '$APP-api*' entities remain.

  → If you want this step to run automatically next time, extract a Bearer
    token from DevTools (Network tab → any /api/catalog/* request → copy
    'Authorization: Bearer ...') and add to .env:
        BACKSTAGE_TOKEN=eyJ...
    (User tokens expire ~1h; for a permanent fix, configure a static
     externalAccess token in app-config.local.yaml.)

EOF
fi

# Always remind about hardcoded catalog.locations regardless of auto/manual path.
if [ "$SKIP_BACKSTAGE" != true ]; then
  if grep -lE "(^|[^a-zA-Z0-9-])$APP([^a-zA-Z0-9-]|$)" \
       backstage-app/backstage/app-config*.yaml \
       backstage-app/backstage/catalog/*.yaml 2>/dev/null | head -1 > /dev/null; then
    warn "Found '$APP' hardcoded in one of:"
    grep -lE "(^|[^a-zA-Z0-9-])$APP([^a-zA-Z0-9-]|$)" \
       backstage-app/backstage/app-config*.yaml \
       backstage-app/backstage/catalog/*.yaml 2>/dev/null | sed 's/^/      /'
    warn "Remove those lines, then restart Backstage — otherwise it will re-register on the next catalog refresh."
  else
    ok "no '$APP' hardcode found in app-config*.yaml or catalog/ — safe from auto re-registration"
  fi
fi

# ===========================================================================
# Step 6 — GitHub repository
# ===========================================================================
if [ "$SKIP_GITHUB" = true ]; then
  log "Step 6: GitHub repository (SKIPPED)"
else
  log "Step 6: GitHub repository"
  if gh repo view "$REPO" &>/dev/null; then
    if gh repo delete "$REPO" --yes &>/dev/null; then
      ok "deleted $REPO"
    else
      warn "gh repo delete failed. Token may lack delete_repo scope."
      warn "Run: gh auth refresh -h github.com -s delete_repo"
    fi
  else
    skip "$REPO doesn't exist"
  fi
fi

# ===========================================================================
# Step 7 — Windows hosts file entries
# ===========================================================================
# ===========================================================================
# Step 7 — Windows hosts file entries
# ===========================================================================
if [ "$SKIP_HOSTS" = true ]; then
  log "Step 7: Windows hosts (SKIPPED)"
else
  log "Step 7: Windows hosts cleanup"
  if [ ! -f "$HOSTS" ]; then
    skip "hosts file not found at $HOSTS — not on Windows or path differs"
  elif [ -w "$HOSTS" ]; then
    pattern="${APP}-(dev|staging|prod)\.test\.com"
    TMP=$(mktemp)
    grep -Ev "$pattern" "$HOSTS" > "$TMP" || true
    if cmp -s "$HOSTS" "$TMP"; then
      skip "no host entries for $APP"
    else
      cp "$TMP" "$HOSTS" && ok "removed $APP host entries"
    fi
    rm -f "$TMP"
  else
    warn "hosts file not writable. Open Git Bash as Administrator and re-run, OR"
    warn "remove these lines manually from C:\\Windows\\System32\\drivers\\etc\\hosts:"
    echo "    127.0.0.1 $APP-dev.test.com"
    echo "    127.0.0.1 $APP-staging.test.com"
    echo "    127.0.0.1 $APP-prod.test.com"
  fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<DONE

================================================================
  Teardown complete for: $APP
================================================================

Final sanity checks (all should return empty / not-found):

  kubectl get ns | grep $APP
  kubectl get runners,runnerdeployment -n $RUNNER_NS | grep $APP
  argocd app list | grep $APP
  argocd repo list | grep $APP
  gh api repos/$REPO 2>&1 | grep -i 'not found'

DONE
