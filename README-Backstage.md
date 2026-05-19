# Backstage

> An Internal Developer Portal (IDP) reference setup — Backstage in Docker with
> GitHub OAuth, Catalog, and the new frontend system.

## Prerequisites

- Docker Desktop (Windows / macOS / Linux)
- A GitHub account (for OAuth + repo integration)
- ~6 GB free disk for the Node container + Backstage `node_modules`
- This guide uses `node:24-bookworm-slim`; Backstage officially supports Node 20 / 22 LTS.
  Node 24 works but may emit engine warnings — switch to `node:22-bookworm-slim` if
  you prefer the supported track.

## Deployment of Backstage in Docker

Reference: <https://backstage.io/docs/getting-started/>

**On host (PowerShell):**

```powershell
docker pull node:24-bookworm-slim
mkdir backstage-app

# Both ports are required:
#   3000 — frontend dev server (browser)
#   7007 — backend API (Catalog, Auth, etc.)
# Path mount: PowerShell accepts either Windows style (D:\...) or MSYS style (//d/...).
docker run --rm -p 3000:3000 -p 7007:7007 -ti `
  -v //d/development/MasterBackstageIdp/backstage-app://app `
  -w //app node:24-bookworm-slim bash
```

**Inside container:**

```bash
pwd                                  # should be /app
npx @backstage/create-app@latest     # answer "y" to the Ok-to-proceed prompt
                                     # accept default app name (backstage) or pick your own
ls
cd backstage

apt-get update && apt-get install -y curl nano

# Always edit app-config.local.yaml (it overrides app-config.yaml and is .gitignored
# by default). Never edit app-config.yaml directly — it's the committed baseline.
nano app-config.local.yaml
yarn explain peer-requirements
```

```yaml
# app-config.local.yaml — bind both servers to all interfaces so Docker
# port mapping can reach them from the host browser
app:
  listen:
    host: 0.0.0.0

backend:
  listen:
    host: 0.0.0.0
```

```bash
yarn start
# ...
# Rspack compiled successfully
#   Local: http://localhost:3000

exit
```

> **Why both ports?**
> The frontend (port 3000) is the UI; the backend (port 7007) serves the Catalog API.
> Without `-p 7007:7007` the browser cannot reach the backend and you get
> `TypeError: Failed to fetch` on the Catalog page.
> `backend.listen.host: 0.0.0.0` is equally required — without it the backend binds
> to `127.0.0.1` inside the container and Docker's port bridge cannot reach it.

---

## Running Backstage Locally (Without Docker)

The Backstage app can be run directly on the host machine (Node 22 or 24, Yarn 4.4.1) without Docker.

### Prerequisites

- Node 22 or 24 (required by Backstage CLI)
- Yarn 4.4.1 (`packageManager` field in root `package.json`)

### 1. Install dependencies

```bash
cd backstage-app/backstage
yarn install
```

### 2. Create `.env` in the backstage directory

```env
GITHUB_TOKEN=<your-github-pat>
AUTH_GITHUB_CLIENT_ID=<your-oauth-client-id>
AUTH_GITHUB_CLIENT_SECRET=<your-oauth-client-secret>
```

The file is `.gitignore`d by default.

### 3. Load env vars and start

**Git Bash:**

```bash
set -o allexport && source .env && set +o allexport
echo $AUTH_GITHUB_CLIENT_ID    # verify — must not be empty
yarn start
```

**CMD:**

```cmd
for /f "usebackq tokens=*" %i in (.env) do set %i
yarn start
```

**PowerShell:**

```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim())
    }
}
yarn start
```

> The env vars are scoped to the current shell session. Open a fresh terminal and repeat the load step each time.

### 4. Open the app

- Frontend: `http://localhost:3000`
- Backend API: `http://localhost:7007`

---

## Setup Authentication: Backstage + GitHub

### References

- <https://backstage.io/docs/getting-started/config/authentication>
- <https://backstage.io/docs/auth/>
- <https://backstage.io/docs/auth/github/provider>

### 1. Register a GitHub OAuth app

```text
GitHub → Settings → Developer Settings → OAuth Apps → New OAuth App
    Application name:            Backstage
    Homepage URL:                http://localhost:3000
    Authorization callback URL:  http://localhost:7007/api/auth/github/handler/frame
→ Register application
→ Generate a new client secret (note: shown only once)
```

### 2. Save credentials to a host-side `.env`

Create `D:\development\MasterBackstageIdp\backstage-app\backstage\.env` (NOT inside the container):

```env
GITHUB_TOKEN=<your-github-pat>
AUTH_GITHUB_CLIENT_ID=<your-oauth-client-id>
AUTH_GITHUB_CLIENT_SECRET=<your-oauth-client-secret>
ARGOCD_PASSWORD=<argocd-admin-password>   # optional, only needed for CD pipeline
```

> ⚠️ Add `.env` to `.gitignore` to keep secrets out of the repo.

### 3. Update Backstage configuration

**On host (PowerShell) — load `.env` and start the container:**

```bash
source .env
# Robust .env loader: skips blank lines and # comments, strips surrounding quotes

echo $AUTH_GITHUB_CLIENT_ID
echo $AUTH_GITHUB_CLIENT_SECRET

docker run --rm -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET -p 3000:3000 -ti -p 7007:7007 -v //d/development/MasterBackstageIdp/backstage-app://app -w //app node:24-bookworm-slim bash

```

**Inside container — verify env vars were passed through:**

```bash
echo $AUTH_GITHUB_CLIENT_ID
echo $AUTH_GITHUB_CLIENT_SECRET

cd backstage
apt-get update && apt-get install -y nano
```

Create the complete `app-config.local.yaml`:

```bash
nano app-config.local.yaml
```

```yaml
# app-config.local.yaml
app:
  listen:
    host: 0.0.0.0

backend:
  listen:
    host: 0.0.0.0

auth:
  environment: development
  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
        ## uncomment if using GitHub Enterprise
        # enterpriseInstanceUrl: ${AUTH_GITHUB_ENTERPRISE_INSTANCE_URL}
        ## uncomment to set lifespan of user session
        # sessionDuration: { hours: 24 }
        signIn:
          resolvers:
            # See https://backstage.io/docs/auth/github/provider#resolvers
            - resolver: emailMatchingUserEntityProfileEmail
            - resolver: usernameMatchingUserEntityName
```

### 4. Backstage backend — add GitHub auth provider

**Inside container (same session):**

```bash
# Build toolchain is required by some native node deps (e.g. better-sqlite3)
apt-get install -y python3 make g++

# Add the GitHub auth provider module (yarn add already runs install — no need to repeat)
yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-github-provider

nano packages/backend/src/index.ts
```

In `packages/backend/src/index.ts` make two changes:

**Add** the GitHub provider import (after the existing `plugin-auth-backend` line):

```ts
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-github-provider'));  // ADD THIS
```

**Remove** the PostgreSQL search engine import (this scaffold uses the default SQLite
DB, so the PG module would fail at boot. The search backend falls back to its built-in
in-memory Lunr engine when no engine module is registered):

```ts
// REMOVE this line:
backend.add(import('@backstage/plugin-search-backend-module-pg'));
```

You can run `yarn start` here to smoke-test the backend before continuing, or
skip ahead and start once everything is wired up.

### 5. Backstage frontend — sign-in page with GitHub SSO

**Inside container (same session or new `docker run`):**

```bash
cd backstage
nano packages/app/src/App.tsx
```

Replace `packages/app/src/App.tsx` with the version below. This wires
**GitHub as the sole SSO provider** into the new frontend system (`createApp`
from `@backstage/frontend-defaults`). Note the singular `provider={{ ... }}`
prop — using one object instead of the `providers={[ ... ]}` array hides the
Guest card and forces every visitor through GitHub OAuth.

> 💡 If you want the Guest card back for quick local dev (no real auth), swap
> `provider={{ ... }}` for `providers={['guest', { id: 'github-auth-provider', ... }]}`
> and the SignInPage will render both cards again.

```tsx
import { createApp } from '@backstage/frontend-defaults';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import { navModule } from './modules/nav';

import { githubAuthApiRef } from '@backstage/core-plugin-api';
import { SignInPageBlueprint } from '@backstage/plugin-app-react';
import { SignInPage } from '@backstage/core-components';
import { createFrontendModule } from '@backstage/frontend-plugin-api';

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => props =>
      (
        <SignInPage
          {...props}
          provider={{
            id: 'github-auth-provider',
            title: 'GitHub',
            message: 'Sign in using GitHub',
            apiRef: githubAuthApiRef,
          }}
        />
      ),
  },
});

export default createApp({
  features: [
    catalogPlugin,
    navModule,
    createFrontendModule({
      pluginId: 'app',
      extensions: [signInPage],
    }),
  ],
});
```

### 6. Catalog: register the User entity for sign-in resolver

Reference: <https://backstage.io/docs/auth/github/provider#configuration>
Example file: `https://github.com/backstage/backstage/blob/master/packages/catalog-model/examples/acme/team-a-group.yaml`

The sign-in resolvers require a User entity whose `metadata.name` exactly matches
the GitHub login and whose `spec.profile.email` matches the GitHub account email.
Without it, sign-in succeeds but resolution fails and you'll see a 401 from
`/api/auth/...`.

**Inside container, from `/app/backstage`:**

```bash
mkdir -p catalog/entities
nano catalog/entities/users.yaml
```

```yaml
# catalog/entities/users.yaml
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: team-a
spec:
  type: team
  children: []
---
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: christseng89          # MUST match your GitHub login exactly
spec:
  profile:
    displayName: Chris Tseng
    email: samfire5200@gmail.com
    picture: https://api.dicebear.com/7.x/avataaars/svg?seed=Leo&backgroundColor=transparent
  # Uncomment once you also define a Group entity called "team-a", otherwise
  # Backstage will log an unresolved-relation warning at startup.
  # memberOf: [team-a]
```

> **Local development (non-Docker) note:** The absolute path
> `/app/backstage/catalog/entities/users.yaml` only exists inside the Docker
> container. For local dev, the reliable approach is to add the User (and Group)
> entity directly to `examples/org.yaml`, which is loaded unconditionally by
> `app-config.yaml` with an explicit `allow: [User, Group]` per-location rule.
> Append these blocks to `examples/org.yaml`:
>
> ```yaml
> ---
> apiVersion: backstage.io/v1alpha1
> kind: User
> metadata:
>   name: christseng89        # must match GitHub login exactly
> spec:
>   profile:
>     displayName: Christ Tseng
>     email: samfire5200@gmail.com
>   memberOf: [team-a]
> ---
> apiVersion: backstage.io/v1alpha1
> kind: Group
> metadata:
>   name: team-a
> spec:
>   type: team
>   children: []
> ```
>
> Also, for local dev the `catalog` section should be **removed** from
> `app-config.local.yaml` — its `locations` array can shadow or conflict with
> the base config's locations.

**Complete `app-config.local.yaml` — Docker (container) version:**

```bash
nano app-config.local.yaml
```

```yaml
# app-config.local.yaml — Docker / container version
app:
  listen:
    host: 0.0.0.0

backend:
  listen:
    host: 0.0.0.0

auth:
  environment: development
  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
        signIn:
          resolvers:
            # See https://backstage.io/docs/auth/github/provider#resolvers for more resolvers
            - resolver: emailMatchingUserEntityProfileEmail
            - resolver: usernameMatchingUserEntityName

catalog:
  rules:
    - allow: [User, Group, Component, System, API, Resource, Location]
  locations:
    # Absolute path inside the container (/app = volume mount root on host)
    - type: file
      target: /app/backstage/catalog/entities/users.yaml
```

**Complete `app-config.local.yaml` — Local dev (host machine) version:**

For local development the `catalog` section is omitted entirely. The user entity is
added directly to `examples/org.yaml` (loaded unconditionally by `app-config.yaml`),
so no extra catalog location is needed.

```yaml
# app-config.local.yaml — local dev version
app:
  listen:
    host: 0.0.0.0

backend:
  listen:
    host: 0.0.0.0

auth:
  environment: development
  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
        signIn:
          resolvers:
            # See https://backstage.io/docs/auth/github/provider#resolvers for more resolvers
            - resolver: emailMatchingUserEntityProfileEmail
            - resolver: usernameMatchingUserEntityName
```

**Complete `examples/org.yaml` — local dev (with real user added):**

```yaml
---
# https://backstage.io/docs/features/software-catalog/descriptor-format#kind-user
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: guest
spec:
  memberOf: [guests]
---
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: christseng89        # MUST match your GitHub login exactly
spec:
  profile:
    displayName: Christ Tseng
    email: samfire5200@gmail.com  # MUST match primary email on your GitHub account
  memberOf: [team-a]
---
# https://backstage.io/docs/features/software-catalog/descriptor-format#kind-group
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: guests
spec:
  type: team
  children: []
---
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: team-a
spec:
  type: team
  children: []
```

> `examples/org.yaml` is referenced in `app-config.yaml` with an explicit
> `allow: [User, Group]` per-location rule, so entities added here are always
> ingested regardless of the global catalog rules. This is the most reliable
> location for user entities in local development.

### 7. Start Backstage and verify sign-in

```bash
yarn start
```

You should see Rspack compile both `backend` and `app`, with messages similar to:

```text
[1] webpack compiled successfully
[0]  info Listening on :7007
[1]   Local: http://localhost:3000
```

Open `http://localhost:3000` in a browser on the host. You should see the
**SignInPage** with a single card:

- **GitHub** — header reads "GitHub", body reads "Sign in using GitHub", and a
  `SIGN IN` button. Click it → GitHub OAuth consent screen appears → approve →
  you land in Backstage authenticated as `christseng89`.

There is **no Guest card** because `App.tsx` uses the singular
`provider={{ ... }}` prop. This is closer to a production-ready setup: every
visitor must authenticate via GitHub.

> The `findDOMNode`, missing `key` prop, and `<h5><h2>` warnings in the browser
> DevTools Console all originate from Backstage's own packages
> (`core-components`, `plugin-catalog`) and `@material-ui/core` v4. They are
> harmless and will disappear after Backstage finishes its MUI v5 migration.
> To hide them, paste this filter into the Console filter box:
>
> ```text
> -findDOMNode -"unique \"key\" prop" -validateDOMNesting -DEPRECATION
> ```

---

## 8. Register `python-app` as a Catalog Component (this repo's payload)

The whole point of this IDP setup is to surface the sample service in the
Backstage catalog. Append a second location to `app-config.local.yaml`:

```yaml
catalog:
  locations:
    - type: file
      target: /app/backstage/catalog/entities/users.yaml
    # Register the python-app via its catalog-info.yaml
    - type: file
      target: /workspaces/MasterBackstageIdp/python-app/catalog-info.yaml
```

For a real deployment, switch the python-app location to a `type: url` pointing
at the GitHub raw URL of `python-app/catalog-info.yaml` so Backstage can
auto-discover updates.

---

## Restart Backstage
```bash
cd backstage-app
source .env
docker run --rm -e GITHUB_TOKEN=$GITHUB_TOKEN -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET -p 3000:3000 -ti -p 7007:7007 -v //d/development/MasterBackstageIdp/backstage-app://app -w //app node:24-bookworm-slim bash

    cd backstage
    yarn start
        local: http://localhost:3000
    exit

```

## Dependency Maintenance

Run `yarn explain peer-requirements` from the backstage directory to audit peer dependency gaps. Most warnings are internal Backstage package gaps and are harmless; a few are actionable:

| Symptom | Likely cause | Fix |
|---|---|---|
| `yarn explain peer-requirements` shows ✘ for `@testing-library/react` | `packages/app` pinned to v14 but `@backstage/frontend-test-utils` requires v16 | Set `"@testing-library/react": "^16.0.0"` and `"@testing-library/dom": "^10.0.0"` in `packages/app/package.json`, then `yarn install` |
| `yarn explain peer-requirements` shows ✘ for `@types/react` | `packages/app` pinned to `^19` but `react` runtime is v18 | Set `"@types/react": "^18"` in `packages/app/package.json` to match the runtime version |
| Remaining ~45 ✘ peer warnings | Internal Backstage package gaps and optional module-federation peers | Expected — these don't affect runtime; no action needed |

### Corrected `packages/app/package.json` devDependencies

The scaffold generates incorrect versions for several devDependencies. Apply these corrections, then run `yarn install`:

```json
"devDependencies": {
  "@backstage/frontend-test-utils": "^0.5.2",
  "@playwright/test": "^1.32.3",
  "@testing-library/dom": "^10.0.0",
  "@testing-library/jest-dom": "^6.0.0",
  "@testing-library/react": "^16.0.0",
  "@testing-library/user-event": "^14.0.0",
  "@types/react": "^18",
  "@types/react-dom": "*",
  "cross-env": "^7.0.0",
  "jest": "^30.4.2"
}
```

Key changes from the scaffold defaults:
- `@testing-library/dom`: `^9` → `^10` (`@testing-library/react` v16 requires dom v10+)
- `@testing-library/react`: `^14` → `^16` (required by `@backstage/frontend-test-utils@^0.5.2`)
- `@types/react`: `^19` → `^18` (must match the `react@^18` runtime; `^19` causes type/peer conflicts)

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `TypeError: Failed to fetch` on Catalog page | Backend (7007) not reachable from host | Add `-p 7007:7007` and `backend.listen.host: 0.0.0.0` |
| OAuth redirect → "redirect_uri_mismatch" | Callback URL in GitHub OAuth app wrong | Must be exactly `http://localhost:7007/api/auth/github/handler/frame` |
| 401 after GitHub sign-in succeeds | No matching User entity for resolver | Ensure `metadata.name` equals your GitHub login |
| Backend boot crash on `plugin-search-backend-module-pg` | PG search module loaded with no PG | Remove that `backend.add(...)` line (see Step 4) |
| Console: unresolved relation `group:team-a` | `memberOf: [team-a]` references missing Group | Either define a `team-a` Group entity or remove `memberOf` |
| `engine "node" is incompatible` warnings | Node 24 newer than Backstage's tested set | Switch base image to `node:22-bookworm-slim` |
| Sign-in page only shows GitHub, want Guest back | `App.tsx` uses singular `provider={{ ... }}` | Swap to `providers={['guest', { id: 'github-auth-provider', title: 'GitHub', message: 'Sign in using GitHub', apiRef: githubAuthApiRef }]}` in `packages/app/src/App.tsx` |
| `Entity context is not available` at `/kubernetes` | Kubernetes plugin route is entity-scoped, opened without an entity | Navigate via `/catalog → python-app → Kubernetes tab` (URL ends with `/component/python-app/kubernetes`) |
| "unable to resolve user identity" after GitHub OAuth | User entity not in catalog OR GitHub username/email doesn't match catalog entity | Add user to `examples/org.yaml` (always loaded) with matching `metadata.name` and `spec.profile.email`; use both `emailMatchingUserEntityProfileEmail` and `usernameMatchingUserEntityName` resolvers |
| `catalog/entities/users.yaml` not loaded in local dev | Absolute path `/app/backstage/...` only works inside Docker container | For local dev, add user entity to `examples/org.yaml` instead; remove `catalog` section from `app-config.local.yaml` |
| Auth env vars empty when `yarn start` is run | `.env` not sourced before starting | Run `set -o allexport && source .env && set +o allexport` in Git Bash before `yarn start` |

---

## Production considerations

This guide is for **local development only**:

- `auth.environment: development` — production should use `production` and a
  separate set of OAuth credentials with the real callback URL.
- `app-config.local.yaml` is dev-only. Production config belongs in
  `app-config.production.yaml` plus secrets via env vars or a secret manager.
- The in-memory SQLite database is wiped on container restart. Production
  should run Backstage against a real PostgreSQL instance (see
  `docker-compose.deps.yml` for a reference).
- StrictMode-style React deprecation warnings are dev-only; `yarn build:all`
  + `yarn start` against the production build is silent.
