# API versions

Six API versions live in the same image; each environment exposes a different
subset via three env vars set by the Helm chart's `values-{dev,staging,prod}.yaml`:

| Env var | Per-version behaviour |
|---|---|
| `ENABLED_VERSIONS` | Comma list. Blueprint registered → normal responses. |
| `DEPRECATED_VERSIONS` | Subset of enabled. Response also carries `Deprecation` + `Sunset` headers. |
| `REMOVED_VERSIONS` | Comma list. Catch-all blueprint returns `410 Gone` with successor link. |

Anything not listed in any of the three → vanilla `404`.

## Per-environment distribution

| | v1 | v2 | v3 | v4 | v5 | v6 |
|---|---|---|---|---|---|---|
| **dev**     | `410` removed | `410` removed | `410` removed | stable | stable | stable (preview) |
| **staging** | `410` removed | `410` removed | stable        | stable | stable | stable (preview) |
| **prod**    | `410` removed | deprecated*   | stable        | stable | `404` not deployed | `404` not deployed |

*deprecated = still 200 OK, but with `Deprecation: true` + `Sunset: Tue, 30 Jun 2026 23:59:59 GMT` headers.

## Endpoint matrix

The carry-over pattern: each version implements everything the previous
version had, then adds net-new endpoints.

| Endpoint | v1 | v2 | v3 | v4 | v5 | v6 |
|---|---|---|---|---|---|---|
| `GET /info`            | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `GET /healthz`         | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `GET /hostname`        | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `POST /echo`           |   | ✓ | ✓ | ✓ | ✓ | ✓ |
| `GET /time`            |   | ✓ | ✓ | ✓ | ✓ | ✓ |
| `GET /random`          |   |   | ✓ | ✓ | ✓ | ✓ |
| `GET /uptime`          |   |   | ✓ | ✓ | ✓ | ✓ |
| `GET /env`             |   |   | ✓ |   |   |   |
| `GET /metrics`         |   |   |   | ✓ | ✓ | ✓ |
| `GET /list`            |   |   |   |   | ✓ | ✓ |
| `GET /events` (SSE)    |   |   |   |   |   | ✓ |

> v3's `/env` was dropped in v4+ because `/metrics` covers the same surface
> without exposing arbitrary env vars. v1/v2 are deprecated/retired so their
> column reflects the legacy shape.

## Always-on, unversioned

| Method | Path | Description |
|---|---|---|
| GET | `/` | Greeting page (HTML) |
| GET | `/version` | Runtime metadata — image, git SHA, current env's enabled/deprecated/removed |

## Deprecation behaviour

A version in `DEPRECATED_VERSIONS` returns its normal response **plus** these
headers, set by `src/deprecated_headers.py`:

```http
Deprecation: true
Sunset: Tue, 30 Jun 2026 23:59:59 GMT
Link: </api/v3>; rel="successor-version"
Link: </docs/migration-v2-to-v3>; rel="deprecation"
```

Currently only **v2 on prod** is deprecated. Other envs already removed v2.

## Removal behaviour (410 Gone)

A version in `REMOVED_VERSIONS` gets a catch-all blueprint, registered by
`src/removed_handlers.py`. Any path under that version's prefix returns:

```http
HTTP/1.1 410 Gone
Content-Type: application/json
Sunset: Wed, 31 Dec 2024 23:59:59 GMT
Link: </api/v2>; rel="successor-version"
Link: </docs/migration-v1-to-v2>; rel="deprecation"

{
  "error": "Gone",
  "message": "/api/v1/* was removed on 2024-12-31.",
  "successor": "v2",
  "migration_guide": "/docs/migration-v1-to-v2"
}
```

`410` is intentional — distinct from `404`. It tells the client "this WAS a
real endpoint, intentionally retired" with a pointer to its successor. v1 in
every env, v2 in dev+staging, v3 in dev — all behave this way.

## Promoting / retiring a version

To **promote** a new version to a new env:

1. Bump that env's `apiVersions.enabled` in `values-{env}.yaml` to include it.
2. (If the env already lists older versions as `removed` and you want the new
   version to also be the default, update `apiVersions.default` and the
   liveness/readiness probe path.)

To **retire** a version (move it from "deprecated" → "removed"):

1. Remove it from `DEPRECATED_VERSIONS` in the env that still serves it.
2. Add it to `REMOVED_VERSIONS` in the same env.
3. Update `removed_handlers.SUNSET_INFO[<version>]` if the sunset date or
   successor changed.

In Backstage catalog, flip the API entity's `lifecycle` to match the new
status (`production` → `deprecated`, `deprecated` → `deprecated` with a
"retired" tag, etc.) so consumers see the change.
