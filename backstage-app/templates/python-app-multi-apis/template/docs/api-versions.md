# API versions

This service exposes three API namespaces side-by-side. Their full
specs live as Backstage `API` entities in the catalog — this page is a
quick at-a-glance reference.

| Path prefix | Endpoints | Lifecycle | Backstage entity |
|---|---|---|---|
| `/api/v1` | 3 | `deprecated` — sunset 2025-12-31 | `api:default/${{values.app_name}}-api-v1` |
| `/api/v2` | 5 | `production` (default) | `api:default/${{values.app_name}}-api-v2` |
| `/api/v3` | 8 | `experimental` | `api:default/${{values.app_name}}-api-v3` |

## v1 endpoints (deprecated)

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/info` | Service info (time + hostname) |
| GET | `/api/v1/healthz` | Liveness / readiness probe |
| GET | `/api/v1/hostname` | Pod hostname |

Every response carries:

```http
Deprecation: true
Sunset: Wed, 31 Dec 2025 23:59:59 GMT
Link: </api/v2>; rel="successor-version"
Link: </docs/migration-v1-to-v2>; rel="deprecation"
```

## v2 endpoints (production default)

| Method | Path | Description |
|---|---|---|
| GET | `/api/v2/info` | Service info + `deployed_on` context |
| GET | `/api/v2/healthz` | Liveness / readiness probe |
| GET | `/api/v2/hostname` | Pod hostname |
| POST | `/api/v2/echo` | Echoes the request body |
| GET | `/api/v2/time` | Current UTC time (ISO 8601) |

## v3 endpoints (experimental — preview)

v2 carries forward unchanged, plus three v3-only endpoints:

| Method | Path | Description |
|---|---|---|
| GET | `/api/v3/random` | Pseudo-random integer in [1, 100] |
| GET | `/api/v3/uptime` | Process uptime in seconds |
| GET | `/api/v3/env` | Allow-listed env vars (no secrets) |

## Operational endpoints (always available, unversioned)

| Method | Path | Description |
|---|---|---|
| GET | `/` | Greeting page (HTML) |
| GET | `/version` | Runtime metadata — image, git SHA, supported versions |
