#!/usr/bin/env bash
# Org-level bootstrap for the `intelligent-ltd` GitHub organization.
# Sets secrets AND variables once for the whole org. Every repo
# (existing + future) under the org inherits these via `--visibility all`,
# so per-repo `gh secret set` / `gh variable set` calls are unnecessary.
#
# Usage:
#   bash setup-org.sh                        # both: secrets + variables
#   bash setup-org.sh --secrets-only         # only secrets
#   bash setup-org.sh --variables-only       # only variables
#
# Requirements:
#   - gh CLI authenticated with `admin:org` scope
#       gh auth refresh -h github.com -s admin:org
#   - .env in the repo root (required when secrets run; optional when only
#     variables run — defaults below cover ARGOCD/YQ/KUBECTL versions):
#
#       DOCKERHUB_USERNAME=your-username
#       DOCKERHUB_TOKEN=your-token
#       ARGOCD_PASSWORD=your-argocd-admin-password
#       GITHUB_PAT=your-github-personal-access-token
#       # optional version overrides:
#       ARGOCD_VERSION=v3.4.2
#       YQ_VERSION=v4.44.3
#       KUBECTL_VERSION=v1.36.1
#
# Behaviour: every run overwrites the current org-level values with what's
# in `.env` (so a rotated token or bumped version is picked up by simply
# re-running this script — no flag needed).

set -euo pipefail

ORG="intelligent-ltd"
DO_SECRETS=true
DO_VARIABLES=true

for arg in "$@"; do
  case "$arg" in
    --secrets-only)   DO_VARIABLES=false ;;
    --variables-only) DO_SECRETS=false ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Load .env (required when setting secrets, optional otherwise)
# ---------------------------------------------------------------------------
if [ -f .env ]; then
  # shellcheck source=/dev/null
  source .env
elif [ "$DO_SECRETS" = true ]; then
  cat >&2 <<'EOF'
Error: .env file not found in the current directory.
Create one in the repo root with:

  DOCKERHUB_USERNAME=your-username
  DOCKERHUB_TOKEN=your-token
  ARGOCD_PASSWORD=your-argocd-admin-password
  GITHUB_PAT=your-github-personal-access-token

Optional version overrides:

  ARGOCD_VERSION=v3.4.2
  YQ_VERSION=v4.44.3
  KUBECTL_VERSION=v1.36.1
EOF
  exit 1
fi

# Validate required secret values when --variables-only was NOT passed
if [ "$DO_SECRETS" = true ]; then
  for var in DOCKERHUB_USERNAME DOCKERHUB_TOKEN ARGOCD_PASSWORD GITHUB_PAT; do
    if [ -z "${!var:-}" ]; then
      echo "Error: $var is not set in .env" >&2
      exit 1
    fi
  done
fi

# Apply defaults for version variables
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.2}"
YQ_VERSION="${YQ_VERSION:-v4.44.3}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.1}"

# ---------------------------------------------------------------------------
# Check gh authentication + admin:org scope
# ---------------------------------------------------------------------------
if ! gh auth status &>/dev/null; then
  echo "Error: gh CLI is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

if ! gh auth status 2>&1 | grep -q "admin:org"; then
  echo "Error: gh token is missing the 'admin:org' scope." >&2
  echo "Run: gh auth refresh -h github.com -s admin:org" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1 — Org-level secrets (always overwrite)
# ---------------------------------------------------------------------------
if [ "$DO_SECRETS" = true ]; then
  echo ""
  echo "=== Step 1: Setting org-level secrets on $ORG (overwrite) ==="

  declare -A SECRETS=(
    [DOCKERHUB_USERNAME]="${DOCKERHUB_USERNAME:-}"
    [DOCKERHUB_TOKEN]="${DOCKERHUB_TOKEN:-}"
    [ARGOCD_PASSWORD]="${ARGOCD_PASSWORD:-}"
    [GH_PAT]="${GITHUB_PAT:-}"
  )

  for name in DOCKERHUB_USERNAME DOCKERHUB_TOKEN ARGOCD_PASSWORD GH_PAT; do
    gh secret set "$name" --body "${SECRETS[$name]}" --org "$ORG" --visibility all
    echo "  $name set in org $ORG."
  done

  echo ""
  echo "Current org secrets:"
  gh secret list --org "$ORG"
else
  echo ""
  echo "=== Step 1: Skipped (--variables-only) ==="
fi

# ---------------------------------------------------------------------------
# Step 2 — Org-level variables (always overwrite)
# ---------------------------------------------------------------------------
if [ "$DO_VARIABLES" = true ]; then
  echo ""
  echo "=== Step 2: Setting org-level variables on $ORG (overwrite) ==="
  echo "  ARGOCD_VERSION  = $ARGOCD_VERSION"
  echo "  YQ_VERSION      = $YQ_VERSION"
  echo "  KUBECTL_VERSION = $KUBECTL_VERSION"
  echo ""

  declare -A VARIABLES=(
    [ARGOCD_VERSION]="$ARGOCD_VERSION"
    [YQ_VERSION]="$YQ_VERSION"
    [KUBECTL_VERSION]="$KUBECTL_VERSION"
  )

  for name in ARGOCD_VERSION YQ_VERSION KUBECTL_VERSION; do
    gh variable set "$name" --body "${VARIABLES[$name]}" --org "$ORG" --visibility all
    echo "  $name set in org $ORG."
  done

  echo ""
  echo "Current org variables:"
  gh variable list --org "$ORG"
else
  echo ""
  echo "=== Step 2: Skipped (--secrets-only) ==="
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Done ==="
echo "All repos under $ORG can now read these secrets/variables in workflows."
if [ "$DO_VARIABLES" = true ]; then
  echo ""
  echo "Tip: after bumping a version, run the mirror-cli-binaries workflow"
  echo "     on any repo BEFORE the CD job picks up the new tag."
fi
