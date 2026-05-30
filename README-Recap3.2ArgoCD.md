# Argo CD Plugin

<https://backstage.io/plugins/>
<https://github.com/backstage/community-plugins/tree/main/workspaces/argocd/plugins/argocd>

> Uses the **official Red Hat–maintained** plugin `@backstage-community/plugin-argocd`
> (+ its backend `@backstage-community/plugin-argocd-backend`), not the Roadie plugin.
> It integrates with the **Kubernetes plugin you already run** (keys off `backstage.io/kubernetes-id`,
> which your scaffolded Helm charts already emit), gives richer Deployment Lifecycle / Summary
> views, supports Argo Rollouts, and registers backend **Actions** that surface in Scaffolder + MCP.

**Two things to know going in:**

1. **It needs a backend plugin.** The frontend talks to a dedicated `argocd-backend` plugin, which
   holds the Argo CD instance config and token. No `proxy.endpoints` block is used.
2. **The frontend is still a legacy plugin.** Its `/alpha` export only ships translations — the
   entity views (`ArgocdDeploymentSummary`, `ArgocdDeploymentLifecycle`) are legacy React
   components. So in this app's **new frontend system** they must be bridged in with
   `EntityCardBlueprint` / `EntityContentBlueprint` (step 4) — it does *not* drop into the
   `features: [...]` array the way `githubActionsPlugin` did.

Verified against this repo: Backstage `1.50.0`, `@backstage/plugin-catalog-react` `2.1.4`
(ships `EntityCardBlueprint` + `EntityContentBlueprint` in `/alpha`), plugin `@backstage-community/plugin-argocd` `2.9.0`.

Follow the steps in order: **install → token → backend → frontend → run.** Component annotations
(`argocd/app-selector` + `backstage.io/kubernetes-id`) are set in the scaffolder templates'
`catalog-info.yaml`, not here. Argo Rollouts support lives in a separate note (`README-Recap3.3ArgoRollouts.md`).

---

## 1. Create the Argo CD auth token

The backend authenticates to Argo CD with an account API token, supplied via `${ARGOCD_AUTH_TOKEN}`.
Generate it before wiring the backend (step 3 references it):

```bash
# 2a. (one-time) allow the admin account to mint API tokens
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"accounts.admin":"apiKey,login"}}'
kubectl -n argocd rollout restart deploy argocd-server
kubectl -n argocd rollout status  deploy argocd-server

# 2b. clear any stale value — the argocd CLI reads ARGOCD_AUTH_TOKEN for auth and
#     will fail to log in if it holds an old or invalid value
unset ARGOCD_AUTH_TOKEN

# 2c. log in and generate a long-lived token
ARGO_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
argocd login argocd.test.com:9080 --username admin --password "$ARGO_PWD" --plaintext
argocd account generate-token --account admin   # prints the token
```

`--plaintext` matches the HTTP `:9080` ingress; ignore the gRPC warning on stderr. Add
`--expires-in 90d` to `generate-token` if you'd rather it not be permanent.

Copy the printed value into `.env` (alongside `GITHUB_TOKEN`, `K8S_SA_TOKEN`, `POSTGRES_*`):

```dotenv
ARGOCD_AUTH_TOKEN=eyJhbGciO...
```


## 2. Install the packages

```bash
# From backstage-app/backstage
```bash
cd backstage-app
mkdir techdocs-storage -p
source .env

docker run --rm --name backstage-local \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID \
  -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET \
  -e K8S_SA_TOKEN=$K8S_SA_TOKEN \
  -e POSTGRES_HOST=$POSTGRES_HOST \
  -e POSTGRES_PORT=$POSTGRES_PORT \
  -e POSTGRES_USER=$POSTGRES_USER \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e ARGOCD_AUTH_TOKEN=$ARGOCD_AUTH_TOKEN \
  -e NODE_OPTIONS="--dns-result-order=ipv4first" \
  --add-host=host.docker.internal:host-gateway \
  --add-host=argocd.test.com:host-gateway \
  -p 3000:3000 -ti -p 7007:7007 \
  -v //d/development/MasterBackstageIdp/backstage-app://app \
  -v //d/development/MasterBackstageIdp/backstage-app/techdocs-storage://app/techdocs-storage \
  -v //d/development/MasterBackstageIdp/backstage-app/templates://app/templates:ro \
  -w //app christseng89/node:24-bookwork-slim-pro bash
  ## Wait

  echo $ARGOCD_AUTH_TOKEN   # sanity check the token is in the container
  cd backstage
  yarn --cwd packages/app     add @backstage-community/plugin-argocd
  yarn --cwd packages/backend add @backstage-community/plugin-argocd-backend
```

## 3. Wire the backend

Add the backend plugin in `packages/backend/src/index.ts`:

```ts
const backend = createBackend();
// ...
backend.add(import('@backstage-community/plugin-argocd-backend'));   // ← add
backend.start();
```

Then add the Argo CD instance config to **`app-config.local.yaml`** (same file that already holds
your local `kubernetes` clusters and GitHub integration — the URL points at your local cluster):

```yaml
argocd:
  # Your ingress serves Argo CD over plain HTTP on :9080, so relax the HTTPS requirement
  localDevelopment: true
  # Frontend deep-link target. Without it the card's external link degrades to the
  # Argo CD applications *list*; with it you get .../applications/<ns>/<app>.
  baseUrl: http://argocd.test.com:9080
  appLocatorMethods:
    - type: 'config'
      instances:
        - name: docker-desktop
          url: http://argocd.test.com:9080
          token: ${ARGOCD_AUTH_TOKEN}
```

> Two URLs, two purposes: the instance `url` is what the **backend** calls (so inside the container
> it must resolve — see the `--add-host` note below), while `baseUrl` is the **frontend** link the
> browser opens (so it's whatever you type in your own browser, `http://argocd.test.com:9080`).
>
> The backend process makes the Argo CD calls. When the backend runs **inside the container**, it
> can't resolve `argocd.test.com` from the Windows hosts file — add
> `--add-host=argocd.test.com:host-gateway` to your `docker run` so the container reaches the host
> ingress on `:9080`. (Keep the URL as `argocd.test.com`, not `host.docker.internal` — the ingress
> routes by the `Host` header.)

## 4. Bridge the frontend into the new frontend system

The plugin's README shows the legacy `EntityPage.tsx` wiring, which this app doesn't have.

> **Important — routable extensions.** Both `ArgocdDeploymentSummary` and
> `ArgocdDeploymentLifecycle` are *routable* legacy extensions (`createRoutableExtension`,
> `mountPoint: rootRouteRef`). Bridging them is not symmetric:
>
> - `convertLegacyEntityContentExtension` **binds the routeRef** (it reads `core.mountPoint` and
>   passes `routeRef: convertLegacyRouteRef(mountPoint)` to the blueprint) → the **tab works**.
> - `convertLegacyEntityCardExtension` does **not** handle the mount point at all → a routable
>   *card* like `ArgocdDeploymentSummary` can't resolve its routeRef and the page throws
>   *"Routable extension component … routeRef{…backstage-community-argocd} was not discovered in
>   the app element tree."*
>
> So expose **only the lifecycle as a tab**. It's the full Argo CD view (per-env sync / health /
> history) and covers what the summary card showed. Don't add the summary card unless a future
> plugin version ships it as a non-routable or native new-system extension.

> **Also register the plugin's APIs.** `DeploymentLifecycle` calls `useApi(argoCDApiRef)`
> (`apiRef{plugin.argo.cd.service}`). Bridging the component does **not** register that API, so
> the tab throws *"No implementation available for apiRef{plugin.argo.cd.service}"*. Register the
> legacy plugin's `getApis()` factories as `ApiBlueprint` extensions (the same thing Backstage's
> own `core-compat-api` does).

Create `packages/app/src/modules/argocd.tsx`:

```tsx
import { ApiBlueprint, createFrontendModule } from '@backstage/frontend-plugin-api';
import { convertLegacyEntityContentExtension } from '@backstage/plugin-catalog-react/alpha';
import {
  ArgocdDeploymentLifecycle,
  argocdPlugin,
  isArgocdConfigured,
} from '@backstage-community/plugin-argocd';

// 1) Register the legacy plugin's API factories (argoCDApiRef + instance API) so
//    useApi() inside DeploymentLifecycle resolves.
const argocdApiExtensions = [...argocdPlugin.getApis()].map(factory =>
  ApiBlueprint.make({
    name: factory.api.id,
    params: defineParams => defineParams(factory),
  }),
);

// 2) Deployment lifecycle -> a dedicated "Deployments" tab at /argocd
const argocdLifecycleContent = convertLegacyEntityContentExtension(
  ArgocdDeploymentLifecycle,
  {
    name: 'argocd-deployment-lifecycle',
    path: 'argocd',
    title: 'Deployments',
    filter: entity => Boolean(isArgocdConfigured(entity)),
  },
);

export const argocdModule = createFrontendModule({
  pluginId: 'catalog',
  extensions: [...argocdApiExtensions, argocdLifecycleContent],
});
```

> `isArgocdConfigured(entity)` is `true` only when the entity carries an `argocd/app-name` or
> `argocd/app-selector` annotation — which the scaffolder templates already set in each
> component's `catalog-info.yaml` — so the tab stays hidden on unrelated components. (An entity
> *with* the annotation is what surfaced the routable-extension crash, because the component
> actually tries to render.)

Register the module in `packages/app/src/App.tsx` — same one-line pattern as `githubActionsPlugin`:

```tsx
import githubActionsPlugin from '@backstage-community/plugin-github-actions/alpha';
import { argocdModule } from './modules/argocd';   // ← add

export default createApp({
  features: [
    catalogPlugin,
    navModule,
    techDocsReportIssueAddonModule,
    githubActionsPlugin,
    argocdModule,                                   // ← add
    createFrontendModule({
      pluginId: 'app',
      extensions: [signInPage],
    }),
  ],
});
```

## 5. Run

```bash
# in backstage-app/backstage, with ARGOCD_AUTH_TOKEN in your env
yarn start
```

Open a component that has the `argocd/*` annotation — a **Deployments** tab (`/argocd`) shows the
deployment lifecycle across dev/staging/prod, backed by Argo CD at `http://argocd.test.com:9080`.

---

## Why this differs from Recap 3.1 (GitHub Actions)

| | GitHub Actions (Recap 3.1) | Argo CD (this doc) |
|---|---|---|
| Package | `@backstage-community/plugin-github-actions` | `@backstage-community/plugin-argocd` (+ `-backend`) |
| Frontend system | New — native `/alpha` feature | Legacy components — bridged via blueprints |
| Frontend wiring | push plugin into `features` | `convertLegacyEntityContentExtension` module (Deployments tab) |
| Backend | none | `argocd-backend` plugin + instance config + token |
| Component opt-in | `github.com/project-slug` | `argocd/app-selector` (+ `backstage.io/kubernetes-id`), set in the scaffolder template |

## Troubleshooting

- **`token is malformed` when running `argocd login` / `generate-token`** — the `argocd` CLI is
  reading a stale `ARGOCD_AUTH_TOKEN` from your shell. Run `unset ARGOCD_AUTH_TOKEN` first
  (step 1), then retry.
- **401 from the backend** — `ARGOCD_AUTH_TOKEN` is unset, expired, or not the value printed by
  `generate-token`. Regenerate per step 1 and make sure the token is in `.env`.
- **`unable to connect` / TLS errors** — `localDevelopment: true` is missing, or the `url` is
  `https://`. Argo CD here is plain HTTP on `:9080`; keep `localDevelopment: true` and an
  `http://` URL.
- **`ECONNREFUSED`** — the backend can't reach the `url`. Use `http://argocd.test.com:9080` for
  host `yarn start`, `http://host.docker.internal:9080` for the Dockerized backend.
- **Deployments tab doesn't render** — the `argocd/app-name` (or `argocd/app-selector`) annotation
  is missing from the component's `catalog-info.yaml`, or the catalog hasn't re-read it.
  `isArgocdConfigured` gates visibility on that annotation.
- **Plugin error about annotations** — both `argocd/app-name` and `argocd/app-selector` are set.
  Use only one.
- **`Routable extension component … routeRef{…backstage-community-argocd} was not discovered in
  the app element tree`** — the module tried to expose the **summary card**. That component is a
  routable extension and `convertLegacyEntityCardExtension` doesn't bind its routeRef, so it
  crashes on any entity with the `argocd/*` annotation. Expose only the lifecycle **tab** via
  `convertLegacyEntityContentExtension` (step 4) — do not add the card. After fixing, do a clean
  rebuild (the dev server's HMR may keep the old module registered): stop `yarn start`, optionally
  `rm -rf node_modules/.cache`, restart, and hard-refresh the browser.

- **`NotImplementedError: No implementation available for apiRef{plugin.argo.cd.service}`** — the
  module bridged the component but didn't register the plugin's API factories. Add the
  `ApiBlueprint` registration from `argocdPlugin.getApis()` (step 4).
- **Card's external link opens the Argo CD applications *list* instead of the specific app** —
  top-level `argocd.baseUrl` isn't set. Add `baseUrl: http://argocd.test.com:9080` (step 3); the
  link then resolves to `.../applications/<namespace>/<app>`.

For Argo Rollouts setup and its troubleshooting, see `README-Recap3.3ArgoRollouts.md`.
