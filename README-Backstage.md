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

Create `D:\development\MasterBackstageIdp\.env` (NOT inside the container):

```env
AUTH_GITHUB_CLIENT_ID=<your-client-id>
AUTH_GITHUB_CLIENT_SECRET=<your-client-secret>
```

> ⚠️ Add `.env` to `.gitignore` to keep secrets out of the repo.

### 3. Update Backstage configuration

**On host (PowerShell) — load `.env` and start the container:**

```powershell
# Robust .env loader: skips blank lines and # comments, strips surrounding quotes
Get-Content .env | Where-Object { $_ -match '^\s*[^#\s]' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    if ($k -and $v) {
        $v = $v.Trim().Trim('"').Trim("'")
        [System.Environment]::SetEnvironmentVariable($k.Trim(), $v)
    }
}

echo $env:AUTH_GITHUB_CLIENT_ID
echo $env:AUTH_GITHUB_CLIENT_SECRET

docker run --rm `
  -e AUTH_GITHUB_CLIENT_ID=$env:AUTH_GITHUB_CLIENT_ID `
  -e AUTH_GITHUB_CLIENT_SECRET=$env:AUTH_GITHUB_CLIENT_SECRET `
  -p 3000:3000 -p 7007:7007 -ti `
  -v //d/development/MasterBackstageIdp/backstage-app://app `
  -w //app node:24-bookworm-slim bash
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
Example file: `backstage/packages/catalog-model/examples/acme/team-a-group.yaml`

The `usernameMatchingUserEntityName` resolver requires a User entity whose
`metadata.name` exactly matches the GitHub login. Without it, sign-in succeeds
but resolution fails and you'll see a 401 from `/api/auth/...`.

**Inside container, from `/app/backstage`:**

```bash
mkdir -p catalog/entities
nano catalog/entities/users.yaml
```

```yaml
# catalog/entities/users.yaml
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

Update `app-config.local.yaml` to add the catalog section (complete final file):

```bash
nano app-config.local.yaml
```

```yaml
# app-config.local.yaml — complete file
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
            - resolver: usernameMatchingUserEntityName

catalog:
  rules:
    - allow: [User, Group, Component, System, API, Resource, Location]
  locations:
    # Absolute path inside the container (/app = volume mount root on host)
    - type: file
      target: /app/backstage/catalog/entities/users.yaml
```

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
