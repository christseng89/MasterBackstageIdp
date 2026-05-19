# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```bash
yarn start          # Start both frontend (localhost:3000) and backend (localhost:7007)
yarn build:backend  # Build backend for Docker deployment
yarn build:all      # Build all packages
yarn build-image    # Build Docker image for the backend
yarn test           # Run Jest tests (changed files only)
yarn test:all       # Run all tests with coverage
yarn test:e2e       # Run Playwright E2E tests
yarn lint           # Lint changed files
yarn lint:all       # Lint all packages
yarn new            # Scaffold a new plugin or package
```

**Node version:** 22 or 24 (required). **Package manager:** Yarn 4.4.1 (Yarn Berry).

## Configuration

Three config files are layered in order:

| File | Purpose |
|------|---------|
| `app-config.yaml` | Base config — SQLite in-memory DB, localhost URLs, MCP actions |
| `app-config.local.yaml` | Local overrides — binds to `0.0.0.0`, enables GitHub OAuth |
| `app-config.production.yaml` | Production DB — PostgreSQL via env vars |

**Required environment variables for local dev:**
- `GITHUB_TOKEN` — GitHub PAT for catalog/integrations
- `AUTH_GITHUB_CLIENT_ID` / `AUTH_GITHUB_CLIENT_SECRET` — GitHub OAuth (app-config.local.yaml)

**Required env vars for production:**
- `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`

## Architecture

This is a Yarn monorepo with two primary packages:

```
packages/
  app/      # React frontend (Backstage new frontend plugin system)
  backend/  # Node.js backend (Backstage new backend system)
plugins/    # Empty — place custom plugins here
catalog/
  entities/ # users.yaml — catalog entities used in Docker deployments
examples/   # Sample entities, org, and scaffolder template
```

### Backend (`packages/backend/src/index.ts`)

Uses `createBackend()` from `@backstage/backend-defaults`. Plugins are registered as imports — no manual wiring needed. Enabled plugin modules:

- **Catalog** — with scaffolder entity model and error logging modules
- **Scaffolder** — with GitHub publishing and notifications modules
- **Auth** — guest provider + GitHub OAuth provider
- **TechDocs** — local builder and storage
- **Search** — in-memory engine indexing catalog and TechDocs
- **Kubernetes** — cluster resource viewer
- **Permissions** — allow-all policy (replace for production hardening)
- **Notifications + Signals** — real-time push via WebSockets
- **MCP Actions** — Model Context Protocol integration (auth, catalog, scaffolder sources)

### Frontend (`packages/app/src/App.tsx`)

Uses `createApp()` from `@backstage/frontend-defaults`. The sign-in page uses GitHub auth (`githubAuthApiRef`). The sidebar is custom-built in `packages/app/src/modules/nav/Sidebar.tsx` — that's why four nav items (`search`, `user-settings`, `catalog`, `scaffolder`) are disabled in `app-config.yaml` extensions and rendered manually instead.

### Authentication Flow

- **Dev:** Guest provider is available by default; GitHub OAuth activates when `app-config.local.yaml` is loaded with credentials.
- **Sign-in resolver:** `usernameMatchingUserEntityName` — the GitHub username must match a `User` entity name in the catalog.
- **Production:** Same providers; configure via env vars.

### Catalog Sources

Local development loads entities from `examples/` (entities, org, template). The Docker/production path loads from `/app/backstage/catalog/entities/users.yaml`.

### TechDocs

Configured as `builder: local` — the backend runs `mkdocs` to build docs on demand. For production, switch to CI-generated docs with cloud storage (S3/GCS).

### Docker Build

`packages/backend/Dockerfile` uses a multi-stage build: installs Python 3 + build tools (needed for `isolate-vm` in scaffolder and `better-sqlite3`), then copies the Yarn workspace skeleton and installs production-only dependencies. Runs as the non-root `node` user.
